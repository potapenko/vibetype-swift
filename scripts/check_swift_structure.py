#!/usr/bin/env python3
"""Enforce the repository's ratcheting Swift file-shape contract."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BASELINE = REPOSITORY_ROOT / "scripts" / "swift_structure_baseline.json"
PREFERRED_MAX_LINES = 300
HARD_MAX_LINES = 500
SCHEMA_VERSION = 1

EXCLUDED_PREFIXES = (
    ".build/",
    ".swiftpm/",
    "DerivedData/",
    "build/",
    "dist/",
    "references/",
)
EXCLUDED_COMPONENTS = frozenset({".build", ".swiftpm", "DerivedData", "Pods", "Carthage"})
VIEW_PROTOCOLS = frozenset(
    {
        "View",
        "UIViewRepresentable",
        "NSViewRepresentable",
        "UIViewControllerRepresentable",
        "NSViewControllerRepresentable",
    }
)
VIEW_DECLARATION = re.compile(
    r"^(?P<access>public|internal|package|fileprivate|private)?\s*"
    r"(?:(?:final|indirect)\s+)?(?:struct|class)\s+"
    r"(?P<name>[A-Za-z_][A-Za-z0-9_]*)"
    r"(?:<[^>{}]+>)?\s*:\s*(?P<conformances>[^{}]+)\s*\{"
)
LEGACY_PREVIEW = re.compile(r"\bPreviewProvider\b")


@dataclass(frozen=True)
class SwiftFileSnapshot:
    path: str
    lines: int
    primary_views: tuple[str, ...]
    preview_count: int

    @property
    def lacks_preview(self) -> bool:
        return bool(self.primary_views) and self.preview_count == 0


@dataclass(frozen=True)
class ExceptionRule:
    path: str
    rule: str
    limit: int | None


class StructureError(RuntimeError):
    pass


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline",
        type=Path,
        default=DEFAULT_BASELINE,
        help="baseline JSON path",
    )
    parser.add_argument(
        "--report",
        action="store_true",
        help="print inventory bands after checking",
    )
    parser.add_argument(
        "--update-baseline",
        action="store_true",
        help="lower or remove existing debt after a real cleanup",
    )
    parser.add_argument(
        "--print-snapshot",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    arguments = parser.parse_args()
    if arguments.update_baseline and arguments.print_snapshot:
        parser.error("--update-baseline and --print-snapshot are mutually exclusive")
    return arguments


def git_swift_paths() -> list[str]:
    command = [
        "git",
        "ls-files",
        "-z",
        "--cached",
        "--others",
        "--exclude-standard",
        "--",
        "*.swift",
    ]
    try:
        result = subprocess.run(
            command,
            cwd=REPOSITORY_ROOT,
            check=True,
            capture_output=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise StructureError(f"could not enumerate Swift files: {error}") from error

    paths = result.stdout.decode("utf-8").split("\0")
    return sorted(path for path in paths if path and is_repo_owned_source(path))


def is_repo_owned_source(path: str) -> bool:
    if Path(path).name == "Package.swift":
        return False
    if path.startswith(EXCLUDED_PREFIXES):
        return False
    return not (set(Path(path).parts) & EXCLUDED_COMPONENTS)


def primary_view_names(source: str) -> tuple[str, ...]:
    names: list[str] = []
    for line in source.splitlines():
        match = VIEW_DECLARATION.match(line)
        if match is None or match.group("access") in {"private", "fileprivate"}:
            continue
        conformances = {
            token
            for token in re.findall(r"[A-Za-z_][A-Za-z0-9_]*", match.group("conformances"))
        }
        if conformances & VIEW_PROTOCOLS:
            names.append(match.group("name"))
    return tuple(names)


def snapshot_file(path: str, generated_files: set[str]) -> SwiftFileSnapshot | None:
    if path in generated_files:
        return None
    absolute_path = REPOSITORY_ROOT / path
    try:
        source = absolute_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise StructureError(f"could not read {path}: {error}") from error
    return SwiftFileSnapshot(
        path=path,
        lines=len(source.splitlines()),
        primary_views=primary_view_names(source),
        preview_count=source.count("#Preview") + len(LEGACY_PREVIEW.findall(source)),
    )


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise StructureError(f"baseline is missing: {path}") from error
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise StructureError(f"could not read baseline {path}: {error}") from error
    if not isinstance(value, dict):
        raise StructureError("baseline root must be a JSON object")
    return value


def require_mapping(value: Any, field: str) -> dict[str, int]:
    if not isinstance(value, dict):
        raise StructureError(f"baseline field {field!r} must be an object")
    result: dict[str, int] = {}
    for raw_path, raw_limit in value.items():
        if not isinstance(raw_path, str) or not raw_path:
            raise StructureError(f"baseline field {field!r} has an invalid path")
        if not isinstance(raw_limit, int) or isinstance(raw_limit, bool) or raw_limit < 1:
            raise StructureError(f"baseline entry {field}.{raw_path} must be a positive integer")
        result[raw_path] = raw_limit
    return result


def validate_baseline(data: dict[str, Any]) -> None:
    if data.get("schemaVersion") != SCHEMA_VERSION:
        raise StructureError(f"baseline schemaVersion must be {SCHEMA_VERSION}")
    policy = data.get("policy")
    if policy != {
        "preferredMaxLines": PREFERRED_MAX_LINES,
        "hardMaxLines": HARD_MAX_LINES,
    }:
        raise StructureError("baseline policy does not match the checker constants")
    generated_files = data.get("generatedFiles")
    if not isinstance(generated_files, list) or any(
        not isinstance(path, str) or not path for path in generated_files
    ):
        raise StructureError("baseline generatedFiles must be an array of exact paths")
    require_mapping(data.get("oversizedFiles"), "oversizedFiles")
    require_mapping(data.get("missingPreviews"), "missingPreviews")
    require_mapping(data.get("multiplePrimaryViews"), "multiplePrimaryViews")
    if not isinstance(data.get("exceptions"), list):
        raise StructureError("baseline exceptions must be an array")


def load_exceptions(data: dict[str, Any]) -> dict[tuple[str, str], ExceptionRule]:
    result: dict[tuple[str, str], ExceptionRule] = {}
    for index, raw in enumerate(data["exceptions"]):
        if not isinstance(raw, dict):
            raise StructureError(f"exception {index} must be an object")
        path = raw.get("path")
        rule = raw.get("rule")
        reason = raw.get("reason")
        owner = raw.get("owner")
        review_by = raw.get("reviewBy")
        if not all(isinstance(value, str) and value.strip() for value in (path, rule, reason, owner)):
            raise StructureError(f"exception {index} requires path, rule, reason, and owner")
        if rule not in {"line-limit", "preview", "primary-view-count"}:
            raise StructureError(f"exception {index} has unknown rule {rule!r}")
        try:
            review_date = date.fromisoformat(review_by)
        except (TypeError, ValueError) as error:
            raise StructureError(f"exception {index} has invalid reviewBy") from error
        if review_date < date.today():
            raise StructureError(f"exception expired on {review_by}: {path} ({rule})")
        limit = raw.get("limit")
        if rule in {"line-limit", "primary-view-count"}:
            if not isinstance(limit, int) or isinstance(limit, bool) or limit < 1:
                raise StructureError(f"exception {index} requires a positive integer limit")
        elif limit is not None:
            raise StructureError(f"preview exception {index} must not declare a limit")
        key = (path, rule)
        if key in result:
            raise StructureError(f"duplicate exception for {path} ({rule})")
        result[key] = ExceptionRule(path=path, rule=rule, limit=limit)
    return result


def collect_snapshots(generated_files: set[str]) -> dict[str, SwiftFileSnapshot]:
    snapshots: dict[str, SwiftFileSnapshot] = {}
    for path in git_swift_paths():
        snapshot = snapshot_file(path, generated_files)
        if snapshot is not None:
            snapshots[path] = snapshot
    return snapshots


def current_debt(
    snapshots: dict[str, SwiftFileSnapshot],
) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    oversized = {
        path: snapshot.lines
        for path, snapshot in snapshots.items()
        if snapshot.lines > HARD_MAX_LINES
    }
    missing_previews = {
        path: 1 for path, snapshot in snapshots.items() if snapshot.lacks_preview
    }
    multiple_views = {
        path: len(snapshot.primary_views)
        for path, snapshot in snapshots.items()
        if len(snapshot.primary_views) > 1
    }
    return oversized, missing_previews, multiple_views


def exception_allows(
    exceptions: dict[tuple[str, str], ExceptionRule],
    path: str,
    rule: str,
    value: int,
) -> bool:
    exception = exceptions.get((path, rule))
    if exception is None:
        return False
    return exception.limit is None or value <= exception.limit


def debt_errors(
    current: dict[str, int],
    baseline: dict[str, int],
    exceptions: dict[tuple[str, str], ExceptionRule],
    rule: str,
    label: str,
    include_improvements: bool,
) -> list[str]:
    errors: list[str] = []
    for path, value in sorted(current.items()):
        recorded = baseline.get(path)
        if recorded is None:
            if not exception_allows(exceptions, path, rule, value):
                errors.append(f"new {label}: {path} ({value})")
        elif value > recorded:
            errors.append(f"increased {label}: {path} ({recorded} -> {value})")
        elif include_improvements and value < recorded:
            errors.append(
                f"reduced {label} needs --update-baseline: {path} ({recorded} -> {value})"
            )
    if include_improvements:
        for path in sorted(set(baseline) - set(current)):
            errors.append(f"resolved {label} needs --update-baseline: {path}")
    return errors


def stale_exception_errors(
    exceptions: dict[tuple[str, str], ExceptionRule],
    debts: dict[str, dict[str, int]],
) -> list[str]:
    errors: list[str] = []
    for (path, rule), _exception in sorted(exceptions.items()):
        if path not in debts[rule]:
            errors.append(f"stale exception: {path} ({rule})")
    return errors


def evaluate(
    data: dict[str, Any],
    snapshots: dict[str, SwiftFileSnapshot],
    include_improvements: bool,
) -> list[str]:
    exceptions = load_exceptions(data)
    oversized, missing_previews, multiple_views = current_debt(snapshots)
    debts = {
        "line-limit": oversized,
        "preview": missing_previews,
        "primary-view-count": multiple_views,
    }
    errors = debt_errors(
        oversized,
        require_mapping(data["oversizedFiles"], "oversizedFiles"),
        exceptions,
        "line-limit",
        "line limit",
        include_improvements,
    )
    errors += debt_errors(
        missing_previews,
        require_mapping(data["missingPreviews"], "missingPreviews"),
        exceptions,
        "preview",
        "missing preview",
        include_improvements,
    )
    errors += debt_errors(
        multiple_views,
        require_mapping(data["multiplePrimaryViews"], "multiplePrimaryViews"),
        exceptions,
        "primary-view-count",
        "primary View count",
        include_improvements,
    )
    errors += stale_exception_errors(exceptions, debts)
    return sorted(errors)


def serialized_snapshot(
    data: dict[str, Any], snapshots: dict[str, SwiftFileSnapshot]
) -> dict[str, Any]:
    oversized, missing_previews, multiple_views = current_debt(snapshots)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "policy": {
            "preferredMaxLines": PREFERRED_MAX_LINES,
            "hardMaxLines": HARD_MAX_LINES,
        },
        "generatedFiles": sorted(data.get("generatedFiles", [])),
        "oversizedFiles": dict(sorted(oversized.items())),
        "missingPreviews": dict(sorted(missing_previews.items())),
        "multiplePrimaryViews": dict(sorted(multiple_views.items())),
        "exceptions": data.get("exceptions", []),
    }


def write_baseline(path: Path, value: dict[str, Any]) -> None:
    rendered = json.dumps(value, indent=2, sort_keys=False) + "\n"
    path.write_text(rendered, encoding="utf-8")


def is_test_path(path: str) -> bool:
    return any(part.endswith("Tests") or part.endswith("UITests") for part in Path(path).parts)


def print_inventory(snapshots: dict[str, SwiftFileSnapshot]) -> None:
    for label, selected in (
        ("production", [item for item in snapshots.values() if not is_test_path(item.path)]),
        ("tests", [item for item in snapshots.values() if is_test_path(item.path)]),
    ):
        bands = [0, 0, 0, 0]
        for item in selected:
            if item.lines <= 200:
                bands[0] += 1
            elif item.lines <= PREFERRED_MAX_LINES:
                bands[1] += 1
            elif item.lines <= HARD_MAX_LINES:
                bands[2] += 1
            else:
                bands[3] += 1
        print(
            f"{label}: files={len(selected)} lines={sum(item.lines for item in selected)} "
            f"<=200={bands[0]} 201-300={bands[1]} 301-500={bands[2]} >500={bands[3]}"
        )
    view_files = [item for item in snapshots.values() if item.primary_views]
    print(
        "ui: "
        f"files={len(view_files)} views={sum(len(item.primary_views) for item in view_files)} "
        f"missing_preview_files={sum(item.lacks_preview for item in view_files)} "
        f"multiple_primary_view_files={sum(len(item.primary_views) > 1 for item in view_files)}"
    )


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.print_snapshot:
            snapshots = collect_snapshots(set())
            print(json.dumps(serialized_snapshot({}, snapshots), indent=2) + "\n", end="")
            return 0

        baseline_path = arguments.baseline.resolve()
        data = load_json(baseline_path)
        validate_baseline(data)
        snapshots = collect_snapshots(set(data["generatedFiles"]))

        if arguments.update_baseline:
            regressions = evaluate(data, snapshots, include_improvements=False)
            if regressions:
                for error in regressions:
                    print(f"[fail] {error}", file=sys.stderr)
                print("baseline not updated", file=sys.stderr)
                return 1
            write_baseline(baseline_path, serialized_snapshot(data, snapshots))
            print(f"swift structure baseline updated: {baseline_path.relative_to(REPOSITORY_ROOT)}")
            return 0

        errors = evaluate(data, snapshots, include_improvements=True)
        if errors:
            for error in errors:
                print(f"[fail] {error}", file=sys.stderr)
            return 1
        oversized, missing_previews, multiple_views = current_debt(snapshots)
        print(
            "swift structure: pass "
            f"({len(snapshots)} files; {len(oversized)} oversized baseline; "
            f"{len(missing_previews)} preview-debt files; "
            f"{len(multiple_views)} multi-View files)"
        )
        if arguments.report:
            print_inventory(snapshots)
        return 0
    except StructureError as error:
        print(f"[fail] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
