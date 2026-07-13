#!/usr/bin/env python3
"""Fail-closed verification for a built HoldType iOS Release app bundle."""

from __future__ import annotations

import argparse
import json
import plistlib
import stat
import struct
import subprocess
import zlib
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Callable, Sequence


APP_BUNDLE_IDENTIFIER = "app.holdtype.HoldType.ios"
APP_EXECUTABLE = "HoldType-iOS"
KEYBOARD_BUNDLE_IDENTIFIER = f"{APP_BUNDLE_IDENTIFIER}.keyboard"
KEYBOARD_EXECUTABLE = "HoldTypeKeyboard"
KEYBOARD_EXTENSION_NAME = "HoldTypeKeyboard.appex"
MICROPHONE_PURPOSE = (
    "HoldType uses the microphone to record speech you choose to transcribe."
)
DEFAULT_TOOL_TIMEOUT_SECONDS = 10.0
SHARED_APP_GROUP = "group.app.holdtype.HoldType.shared"

SYSTEM_DEPENDENCY_PREFIXES = (
    "/System/Library/",
    "/usr/lib/",
)

APP_PRIVACY_MANIFEST = {
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": [
        {
            "NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeAudioData",
            "NSPrivacyCollectedDataTypeLinked": True,
            "NSPrivacyCollectedDataTypeTracking": False,
            "NSPrivacyCollectedDataTypePurposes": [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ],
        },
        {
            "NSPrivacyCollectedDataType": (
                "NSPrivacyCollectedDataTypeOtherUserContent"
            ),
            "NSPrivacyCollectedDataTypeLinked": True,
            "NSPrivacyCollectedDataTypeTracking": False,
            "NSPrivacyCollectedDataTypePurposes": [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ],
        },
    ],
    "NSPrivacyAccessedAPITypes": [
        {
            "NSPrivacyAccessedAPIType": (
                "NSPrivacyAccessedAPICategoryFileTimestamp"
            ),
            "NSPrivacyAccessedAPITypeReasons": ["C617.1"],
        }
    ],
}

KEYBOARD_PRIVACY_MANIFEST = {
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": [],
    "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyAccessedAPITypes": [],
}

FORBIDDEN_RELEASE_APP_MARKERS = (
    "KeyboardBridgeProbeView",
    "IOSAcceptedOutputDeliveryQualificationFixture",
    "IOSProviderConsentQualificationFixture",
    "Publish Keyboard Test Sample",
    "ios.voice.publish-practice-sample",
    "ios.keyboard.phase0",
    "HOLDTYPE_UI_QUALIFICATION",
    "IOSUIQualificationRoute",
    "IOSUIQualificationRootView",
    "Qualification Gallery",
    "Qualification Route Unavailable",
    "ios.qualification.",
)

# These markers name containing-app-only modules, services, and platform APIs.
# The keyboard may display bridge state, but it must never link or embed these
# implementation boundaries.
FORBIDDEN_KEYBOARD_MARKERS = (
    "HoldTypeDomain",
    "HoldTypeIOSCore",
    "HoldTypePersistence",
    "HoldTypeOpenAI",
    "OpenAI",
    "ProviderConsent",
    "PendingRecording",
    "AcceptedOutput",
    "FailedHistory",
    "TranscriptionHistory",
    "Keychain",
    "SecItem",
    "IOSMicrophonePermission",
    "IOSAudioSession",
    "IOSForegroundFinalization",
    "IOSVoiceBoundaryFeedback",
    "IOSForegroundVoiceRecorder",
    "AVAudioSession",
    "AVAudioRecorder",
    "AVAudioApplication",
    "AVAudioEngine",
    "SFSpeechRecognizer",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "UIBackgroundModes",
    "URLSession",
    "NWConnection",
    "api.openai.com",
)

MACH_O_MAGICS = {
    b"\xca\xfe\xba\xbe",  # universal, big endian
    b"\xbe\xba\xfe\xca",  # universal, little endian
    b"\xca\xfe\xba\xbf",  # universal 64, big endian
    b"\xbf\xba\xfe\xca",  # universal 64, little endian
    b"\xfe\xed\xfa\xce",  # Mach-O 32, big endian
    b"\xce\xfa\xed\xfe",  # Mach-O 32, little endian
    b"\xfe\xed\xfa\xcf",  # Mach-O 64, big endian
    b"\xcf\xfa\xed\xfe",  # Mach-O 64, little endian
}


@dataclass(frozen=True)
class Check:
    name: str
    status: str
    message: str


@dataclass(frozen=True)
class ToolResult:
    returncode: int
    stdout: str = ""
    stderr: str = ""


ToolRunner = Callable[[Sequence[str]], ToolResult]


def pass_check(name: str, message: str) -> Check:
    return Check(name=name, status="pass", message=message)


def fail_check(name: str, message: str) -> Check:
    return Check(name=name, status="fail", message=message)


def manual_check(name: str, message: str) -> Check:
    return Check(name=name, status="manual", message=message)


def run_command(
    command: Sequence[str],
    *,
    timeout: float = DEFAULT_TOOL_TIMEOUT_SECONDS,
) -> ToolResult:
    try:
        completed = subprocess.run(
            list(command),
            capture_output=True,
            check=False,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError as error:
        return ToolResult(returncode=127, stderr=str(error))
    except subprocess.TimeoutExpired:
        return ToolResult(
            returncode=124,
            stderr=f"timed out after {timeout:.1f}s",
        )
    return ToolResult(
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


def compact_tool_error(result: ToolResult) -> str:
    detail = (result.stderr or result.stdout).strip().splitlines()
    if detail:
        return f"exit {result.returncode}: {detail[0]}"
    return f"exit {result.returncode} without diagnostics"


def load_plist(path: Path, label: str) -> tuple[dict[str, object] | None, list[Check]]:
    if not path.is_file():
        return None, [fail_check(label, f"missing {path}")]
    try:
        with path.open("rb") as handle:
            value = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        return None, [fail_check(label, f"invalid property list: {error}")]
    if not isinstance(value, dict):
        return None, [fail_check(label, "property list root must be a dictionary")]
    return value, [pass_check(label, str(path))]


def check_nonempty_file(path: Path, name: str) -> Check:
    if not path.is_file():
        return fail_check(name, f"missing {path}")
    try:
        size = path.stat().st_size
    except OSError as error:
        return fail_check(name, f"could not inspect {path}: {error}")
    if size <= 0:
        return fail_check(name, f"empty {path}")
    return pass_check(name, f"{path} ({size} bytes)")


def check_compiled_rgb_png(
    path: Path,
    *,
    expected_width: int,
    expected_height: int,
    name: str,
) -> Check:
    try:
        payload = path.read_bytes()
    except OSError as error:
        return fail_check(name, f"could not read {path}: {error}")
    if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
        return fail_check(name, f"missing PNG signature in {path}")

    offset = 8
    ihdr: tuple[int, int, int, int] | None = None
    saw_idat = False
    saw_iend = False
    saw_transparency = False
    try:
        while offset < len(payload):
            if len(payload) - offset < 12:
                raise ValueError("truncated chunk header")
            length = struct.unpack(">I", payload[offset : offset + 4])[0]
            chunk_type = payload[offset + 4 : offset + 8]
            data_start = offset + 8
            data_end = data_start + length
            crc_end = data_end + 4
            if crc_end > len(payload):
                raise ValueError("truncated chunk payload")
            chunk_data = payload[data_start:data_end]
            expected_crc = struct.unpack(">I", payload[data_end:crc_end])[0]
            actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
            if actual_crc != expected_crc:
                raise ValueError(f"invalid {chunk_type!r} CRC")

            if chunk_type == b"IHDR":
                if ihdr is not None or offset != 8 or length != 13:
                    raise ValueError("invalid IHDR placement or size")
                width, height, bit_depth, color_type = struct.unpack(
                    ">IIBB", chunk_data[:10]
                )
                ihdr = (width, height, bit_depth, color_type)
            elif chunk_type == b"IDAT":
                saw_idat = True
            elif chunk_type == b"tRNS":
                saw_transparency = True
            elif chunk_type == b"IEND":
                if length != 0 or crc_end != len(payload):
                    raise ValueError("invalid IEND placement or size")
                saw_iend = True
                break
            offset = crc_end
    except (ValueError, struct.error) as error:
        return fail_check(name, f"invalid PNG {path}: {error}")

    expected = (expected_width, expected_height, 8, 2)
    if ihdr != expected:
        return fail_check(name, f"expected opaque RGB8 {expected}, got {ihdr!r}")
    if not saw_idat or not saw_iend or saw_transparency:
        return fail_check(
            name,
            "compiled icon must contain IDAT/IEND and no transparency chunk",
        )
    return pass_check(
        name,
        f"{path.name}: {expected_width}x{expected_height}, opaque RGB8",
    )


def check_exact(plist: dict[str, object], key: str, expected: object, name: str) -> Check:
    actual = plist.get(key)
    if actual == expected and type(actual) is type(expected):
        return pass_check(name, repr(expected))
    return fail_check(name, f"expected {expected!r}, got {actual!r}")


def check_absent(plist: dict[str, object], key: str, name: str) -> Check:
    if key not in plist:
        return pass_check(name, "absent")
    return fail_check(name, f"must be absent, got {plist[key]!r}")


def exact_structure_matches(actual: object, expected: object) -> bool:
    if type(actual) is not type(expected):
        return False
    if isinstance(expected, dict):
        if not isinstance(actual, dict) or actual.keys() != expected.keys():
            return False
        return all(
            exact_structure_matches(actual[key], expected_value)
            for key, expected_value in expected.items()
        )
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(actual) != len(expected):
            return False
        return all(
            exact_structure_matches(actual_value, expected_value)
            for actual_value, expected_value in zip(actual, expected)
        )
    return actual == expected


def check_exact_privacy_manifest(
    manifest: dict[str, object],
    expected: dict[str, object],
    name: str,
) -> Check:
    if exact_structure_matches(manifest, expected):
        return pass_check(name, "matches the exact P4 privacy contract")
    return fail_check(name, "does not match the exact P4 privacy contract")


def check_executable(
    bundle: Path,
    plist: dict[str, object],
    *,
    expected_name: str,
    label: str,
) -> tuple[Path | None, list[Check]]:
    checks: list[Check] = []
    executable_name = plist.get("CFBundleExecutable")
    if executable_name != expected_name:
        checks.append(
            fail_check(
                f"{label}:executable-name",
                f"expected {expected_name!r}, got {executable_name!r}",
            )
        )
        return None, checks
    checks.append(pass_check(f"{label}:executable-name", expected_name))

    executable = bundle / expected_name
    if not executable.is_file():
        checks.append(fail_check(f"{label}:executable", f"missing {executable}"))
        return None, checks
    try:
        mode = executable.stat().st_mode
        with executable.open("rb") as handle:
            magic = handle.read(4)
    except OSError as error:
        checks.append(
            fail_check(f"{label}:executable", f"could not inspect {executable}: {error}")
        )
        return None, checks

    if not mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
        checks.append(fail_check(f"{label}:executable-mode", "not marked executable"))
    else:
        checks.append(pass_check(f"{label}:executable-mode", "executable"))

    if magic not in MACH_O_MAGICS:
        checks.append(
            fail_check(
                f"{label}:executable-format",
                f"expected Mach-O magic, got {magic.hex() or 'empty'}",
            )
        )
    else:
        checks.append(pass_check(f"{label}:executable-format", magic.hex()))
    return executable, checks


def parse_otool_dependencies(output: str) -> list[str]:
    dependencies: list[str] = []
    for raw_line in output.splitlines():
        if not raw_line[:1].isspace():
            continue
        line = raw_line.strip()
        if not line:
            continue
        dependencies.append(line.split(" (compatibility version", 1)[0])
    return dependencies


def matching_markers(
    text: str,
    markers: Sequence[str] = FORBIDDEN_KEYBOARD_MARKERS,
) -> list[str]:
    folded = text.casefold()
    return sorted(marker for marker in markers if marker.casefold() in folded)


def check_keyboard_embedded_dependencies(keyboard_bundle: Path, executable: Path) -> list[Check]:
    checks: list[Check] = []
    unexpected: list[str] = []
    symlinks: list[str] = []
    executable_files: list[str] = []
    try:
        paths = sorted(keyboard_bundle.rglob("*"))
    except OSError as error:
        return [
            fail_check(
                "keyboard:embedded-dependencies",
                f"could not enumerate extension: {error}",
            )
        ]

    for path in paths:
        relative = str(path.relative_to(keyboard_bundle))
        if path.is_symlink():
            symlinks.append(relative)
            continue
        if path.suffix in {".dylib", ".framework"} or "Frameworks" in path.parts:
            unexpected.append(relative)
        if path.is_file() and path != executable:
            try:
                if path.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
                    executable_files.append(relative)
            except OSError as error:
                checks.append(
                    fail_check(
                        "keyboard:embedded-executables",
                        f"could not inspect {relative}: {error}",
                    )
                )

    if unexpected:
        checks.append(
            fail_check(
                "keyboard:embedded-dependencies",
                ", ".join(sorted(set(unexpected))),
            )
        )
    else:
        checks.append(pass_check("keyboard:embedded-dependencies", "none"))

    if symlinks:
        checks.append(fail_check("keyboard:symlinks", ", ".join(symlinks)))
    else:
        checks.append(pass_check("keyboard:symlinks", "none"))

    if executable_files:
        checks.append(
            fail_check(
                "keyboard:embedded-executables",
                ", ".join(executable_files),
            )
        )
    elif not any(check.name == "keyboard:embedded-executables" for check in checks):
        checks.append(pass_check("keyboard:embedded-executables", "none"))
    return checks


def scan_bundle_bytes(
    bundle: Path,
    markers: Sequence[str] = FORBIDDEN_KEYBOARD_MARKERS,
) -> tuple[list[str], list[str]]:
    marker_bytes = [marker.casefold().encode("utf-8") for marker in markers]
    maximum_marker_length = max(len(marker) for marker in marker_bytes)
    matches: set[str] = set()
    errors: list[str] = []

    for path in sorted(bundle.rglob("*")):
        if not path.is_file() or path.is_symlink():
            continue
        carry = b""
        try:
            with path.open("rb") as handle:
                while True:
                    chunk = handle.read(1024 * 1024)
                    if not chunk:
                        break
                    haystack = (carry + chunk).lower()
                    for marker, encoded in zip(markers, marker_bytes):
                        if encoded in haystack:
                            matches.add(marker)
                    carry = haystack[-(maximum_marker_length - 1) :]
        except OSError as error:
            errors.append(f"{path.relative_to(bundle)}: {error}")
    return sorted(matches), errors


def inspect_release_app_markers(app_bundle: Path) -> list[Check]:
    matches, errors = scan_bundle_bytes(
        app_bundle,
        markers=FORBIDDEN_RELEASE_APP_MARKERS,
    )
    if errors:
        return [fail_check("app:internal-ui-markers", "; ".join(errors))]
    if matches:
        return [
            fail_check(
                "app:internal-ui-markers",
                ", ".join(matches),
            )
        ]
    return [pass_check("app:internal-ui-markers", "none")]


def inspect_keyboard_binary(
    keyboard_bundle: Path,
    executable: Path,
    runner: ToolRunner,
) -> list[Check]:
    checks = check_keyboard_embedded_dependencies(keyboard_bundle, executable)

    dependency_result = runner(("otool", "-L", str(executable)))
    if dependency_result.returncode != 0:
        checks.append(
            fail_check(
                "keyboard:dependencies",
                compact_tool_error(dependency_result),
            )
        )
    else:
        dependencies = parse_otool_dependencies(dependency_result.stdout)
        if not dependencies:
            checks.append(fail_check("keyboard:dependencies", "no dependencies reported"))
        else:
            checks.append(
                pass_check(
                    "keyboard:dependencies",
                    f"inspected {len(dependencies)} load entries",
                )
            )
            non_system = [
                dependency
                for dependency in dependencies
                if not dependency.startswith(SYSTEM_DEPENDENCY_PREFIXES)
            ]
            if non_system:
                checks.append(
                    fail_check(
                        "keyboard:dependencies:system-only",
                        ", ".join(sorted(set(non_system))),
                    )
                )
            else:
                checks.append(
                    pass_check(
                        "keyboard:dependencies:system-only",
                        "all load entries are system-owned",
                    )
                )

    symbol_outputs: list[str] = []
    symbol_failed = False
    for mode in (("-gU",), ("-u",)):
        result = runner(("nm", *mode, str(executable)))
        if result.returncode != 0:
            symbol_failed = True
            checks.append(
                fail_check(
                    f"keyboard:symbols:{mode[0]}",
                    compact_tool_error(result),
                )
            )
        else:
            symbol_outputs.append(result.stdout)
    if not symbol_failed:
        matches = matching_markers("\n".join(symbol_outputs))
        if matches:
            checks.append(
                fail_check("keyboard:symbols:forbidden", ", ".join(matches))
            )
        else:
            checks.append(pass_check("keyboard:symbols:forbidden", "none"))

    strings_result = runner(("strings", "-a", str(executable)))
    if strings_result.returncode != 0:
        checks.append(
            fail_check("keyboard:strings", compact_tool_error(strings_result))
        )
    else:
        matches = matching_markers(strings_result.stdout)
        if matches:
            checks.append(
                fail_check("keyboard:strings:forbidden", ", ".join(matches))
            )
        else:
            checks.append(pass_check("keyboard:strings:forbidden", "none"))

    byte_matches, byte_errors = scan_bundle_bytes(keyboard_bundle)
    if byte_errors:
        checks.append(fail_check("keyboard:bytes", "; ".join(byte_errors)))
    elif byte_matches:
        checks.append(
            fail_check("keyboard:bytes:forbidden", ", ".join(byte_matches))
        )
    else:
        checks.append(pass_check("keyboard:bytes:forbidden", "none"))
    return checks


def parse_codesign_metadata(output: str) -> dict[str, str]:
    metadata: dict[str, str] = {}
    for line in output.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        metadata[key.strip()] = value.strip()
    return metadata


def parse_embedded_plist(output: str) -> dict[str, object] | None:
    xml_start = output.find("<?xml")
    plist_end = output.rfind("</plist>")
    if xml_start < 0 or plist_end < xml_start:
        return None
    plist_end += len("</plist>")
    try:
        value = plistlib.loads(output[xml_start:plist_end].encode("utf-8"))
    except plistlib.InvalidFileException:
        return None
    return value if isinstance(value, dict) else None


def inspect_processed_entitlements(
    executable: Path,
    *,
    label: str,
    runner: ToolRunner,
) -> list[Check]:
    """Inspect entitlements when a signature carries them.

    Generic Simulator Release binaries are linker-signed and do not preserve
    the source App Group entitlement. In that case this deliberately emits a
    manual gate instead of claiming that the signed-device boundary passed.
    """

    result = runner(("codesign", "-d", "--entitlements", ":-", str(executable)))
    if result.returncode != 0:
        return [
            fail_check(
                f"{label}:processed-entitlements",
                compact_tool_error(result),
            )
        ]

    entitlements = parse_embedded_plist("\n".join((result.stdout, result.stderr)))
    if not entitlements:
        return [
            manual_check(
                f"{label}:processed-entitlements",
                "generic Simulator signature exposes no processed entitlements; "
                "validate the App Group in a signed physical/archive build",
            )
        ]

    groups = entitlements.get("com.apple.security.application-groups")
    if groups == [SHARED_APP_GROUP] and isinstance(groups, list):
        return [
            pass_check(
                f"{label}:processed-entitlements",
                f"exact App Group {SHARED_APP_GROUP}",
            )
        ]
    return [
        fail_check(
            f"{label}:processed-entitlements",
            f"expected exact App Group [{SHARED_APP_GROUP!r}], got {groups!r}",
        )
    ]


def inspect_signature(
    bundle: Path,
    executable: Path,
    plist: dict[str, object],
    *,
    label: str,
    runner: ToolRunner,
) -> list[Check]:
    checks: list[Check] = []
    result = runner(("codesign", "-d", "--verbose=4", str(executable)))
    if result.returncode != 0:
        return [
            fail_check(
                f"{label}:signature:metadata",
                compact_tool_error(result),
            )
        ]

    output = "\n".join((result.stdout, result.stderr))
    metadata = parse_codesign_metadata(output)
    reported_executable = metadata.get("Executable")
    try:
        executable_matches = (
            reported_executable is not None
            and Path(reported_executable).resolve() == executable.resolve()
        )
    except OSError:
        executable_matches = False
    if executable_matches:
        checks.append(pass_check(f"{label}:signature:executable", str(executable)))
    else:
        checks.append(
            fail_check(
                f"{label}:signature:executable",
                f"expected {executable}, got {reported_executable!r}",
            )
        )

    expected_identifier = str(plist.get("CFBundleIdentifier", ""))
    identifier = metadata.get("Identifier")
    if identifier == expected_identifier:
        checks.append(pass_check(f"{label}:signature:identifier", identifier))
    else:
        checks.append(
            fail_check(
                f"{label}:signature:identifier",
                f"expected {expected_identifier!r}, got {identifier!r}",
            )
        )

    if "CodeDirectory" in output and metadata.get("CDHash"):
        checks.append(
            pass_check(
                f"{label}:signature:code-directory",
                f"CDHash {metadata['CDHash']}",
            )
        )
    else:
        checks.append(
            fail_check(
                f"{label}:signature:code-directory",
                "missing CodeDirectory or CDHash metadata",
            )
        )

    signature_directory = bundle / "_CodeSignature"
    code_resources = signature_directory / "CodeResources"
    if signature_directory.exists() and not code_resources.is_file():
        checks.append(
            fail_check(
                f"{label}:signature:bundle-seal",
                f"incomplete signature directory {signature_directory}",
            )
        )
    elif code_resources.is_file():
        verify_result = runner(
            ("codesign", "--verify", "--strict", "--verbose=2", str(bundle))
        )
        if verify_result.returncode != 0:
            checks.append(
                fail_check(
                    f"{label}:signature:verification",
                    compact_tool_error(verify_result),
                )
            )
        else:
            checks.append(
                pass_check(
                    f"{label}:signature:verification",
                    "sealed bundle signature verifies",
                )
            )
    else:
        checks.append(
            pass_check(
                f"{label}:signature:bundle-seal",
                "no bundle seal in generic Simulator build; linker signature inspected",
            )
        )
    return checks


def check_plist_boundaries(
    app_plist: dict[str, object],
    keyboard_plist: dict[str, object],
) -> list[Check]:
    checks = [
        check_exact(
            app_plist,
            "CFBundleIdentifier",
            APP_BUNDLE_IDENTIFIER,
            "app:bundle-identifier",
        ),
        check_exact(app_plist, "CFBundlePackageType", "APPL", "app:package-type"),
        check_exact(
            app_plist,
            "NSMicrophoneUsageDescription",
            MICROPHONE_PURPOSE,
            "app:microphone-purpose",
        ),
        check_absent(
            app_plist,
            "NSSpeechRecognitionUsageDescription",
            "app:speech-purpose",
        ),
        check_absent(app_plist, "UIBackgroundModes", "app:background-modes"),
        check_exact(
            keyboard_plist,
            "CFBundleIdentifier",
            KEYBOARD_BUNDLE_IDENTIFIER,
            "keyboard:bundle-identifier",
        ),
        check_exact(
            keyboard_plist,
            "CFBundlePackageType",
            "XPC!",
            "keyboard:package-type",
        ),
        check_absent(
            keyboard_plist,
            "NSMicrophoneUsageDescription",
            "keyboard:microphone-purpose",
        ),
        check_absent(
            keyboard_plist,
            "NSSpeechRecognitionUsageDescription",
            "keyboard:speech-purpose",
        ),
        check_absent(
            keyboard_plist,
            "UIBackgroundModes",
            "keyboard:background-modes",
        ),
    ]

    extension = keyboard_plist.get("NSExtension")
    if not isinstance(extension, dict):
        checks.append(
            fail_check("keyboard:extension", f"expected dictionary, got {extension!r}")
        )
    else:
        checks.append(pass_check("keyboard:extension", "present"))
        checks.append(
            check_exact(
                extension,
                "NSExtensionPointIdentifier",
                "com.apple.keyboard-service",
                "keyboard:extension-point",
            )
        )
        checks.append(
            check_exact(
                extension,
                "NSExtensionPrincipalClass",
                "HoldTypeKeyboard.KeyboardViewController",
                "keyboard:principal-class",
            )
        )
        attributes = extension.get("NSExtensionAttributes")
        if not isinstance(attributes, dict):
            checks.append(
                fail_check(
                    "keyboard:extension-attributes",
                    f"expected dictionary, got {attributes!r}",
                )
            )
        else:
            checks.append(pass_check("keyboard:extension-attributes", "present"))
            checks.append(
                check_exact(
                    attributes,
                    "RequestsOpenAccess",
                    False,
                    "keyboard:open-access",
                )
            )

    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        app_value = app_plist.get(key)
        keyboard_value = keyboard_plist.get(key)
        name = f"bundle-version:{key}"
        if isinstance(app_value, str) and app_value and keyboard_value == app_value:
            checks.append(pass_check(name, app_value))
        else:
            checks.append(
                fail_check(
                    name,
                    f"app {app_value!r}, keyboard {keyboard_value!r}",
                )
            )
    return checks


def collect_checks(app_path: Path, runner: ToolRunner = run_command) -> list[Check]:
    checks: list[Check] = []
    if app_path.is_symlink():
        return [fail_check("app", f"bundle path must not be a symlink: {app_path}")]
    if not app_path.is_dir() or app_path.suffix != ".app":
        return [fail_check("app", f"missing .app bundle at {app_path}")]
    checks.append(pass_check("app", str(app_path)))

    keyboard_bundle = app_path / "PlugIns" / KEYBOARD_EXTENSION_NAME
    if keyboard_bundle.is_symlink():
        checks.append(
            fail_check("keyboard", f"bundle path must not be a symlink: {keyboard_bundle}")
        )
        return checks
    if not keyboard_bundle.is_dir():
        checks.append(fail_check("keyboard", f"missing {keyboard_bundle}"))
        return checks
    checks.append(pass_check("keyboard", str(keyboard_bundle)))

    app_plist, app_plist_checks = load_plist(app_path / "Info.plist", "app:info-plist")
    keyboard_plist, keyboard_plist_checks = load_plist(
        keyboard_bundle / "Info.plist",
        "keyboard:info-plist",
    )
    checks.extend(app_plist_checks)
    checks.extend(keyboard_plist_checks)

    app_privacy, app_privacy_checks = load_plist(
        app_path / "PrivacyInfo.xcprivacy",
        "app:privacy-manifest",
    )
    keyboard_privacy, keyboard_privacy_checks = load_plist(
        keyboard_bundle / "PrivacyInfo.xcprivacy",
        "keyboard:privacy-manifest",
    )
    checks.extend(app_privacy_checks)
    checks.extend(keyboard_privacy_checks)
    if app_privacy is not None:
        checks.append(
            check_exact_privacy_manifest(
                app_privacy,
                APP_PRIVACY_MANIFEST,
                "app:privacy-manifest:contract",
            )
        )
    if keyboard_privacy is not None:
        checks.append(
            check_exact_privacy_manifest(
                keyboard_privacy,
                KEYBOARD_PRIVACY_MANIFEST,
                "keyboard:privacy-manifest:contract",
            )
        )
    checks.append(check_nonempty_file(app_path / "Assets.car", "app:assets-catalog"))
    checks.append(
        check_compiled_rgb_png(
            app_path / "AppIcon60x60@2x.png",
            expected_width=120,
            expected_height=120,
            name="app:icon:iphone",
        )
    )
    checks.append(
        check_compiled_rgb_png(
            app_path / "AppIcon76x76@2x~ipad.png",
            expected_width=152,
            expected_height=152,
            name="app:icon:ipad",
        )
    )

    if app_plist is None or keyboard_plist is None:
        return checks
    checks.extend(check_plist_boundaries(app_plist, keyboard_plist))

    app_executable, app_executable_checks = check_executable(
        app_path,
        app_plist,
        expected_name=APP_EXECUTABLE,
        label="app",
    )
    keyboard_executable, keyboard_executable_checks = check_executable(
        keyboard_bundle,
        keyboard_plist,
        expected_name=KEYBOARD_EXECUTABLE,
        label="keyboard",
    )
    checks.extend(app_executable_checks)
    checks.extend(keyboard_executable_checks)

    if keyboard_executable is not None:
        checks.extend(
            inspect_keyboard_binary(keyboard_bundle, keyboard_executable, runner)
        )
        checks.extend(
            inspect_signature(
                keyboard_bundle,
                keyboard_executable,
                keyboard_plist,
                label="keyboard",
                runner=runner,
            )
        )
        checks.extend(
            inspect_processed_entitlements(
                keyboard_executable,
                label="keyboard",
                runner=runner,
            )
        )
    if app_executable is not None:
        checks.extend(inspect_release_app_markers(app_path))
        checks.extend(
            inspect_signature(
                app_path,
                app_executable,
                app_plist,
                label="app",
                runner=runner,
            )
        )
        checks.extend(
            inspect_processed_entitlements(
                app_executable,
                label="app",
                runner=runner,
            )
        )
    return checks


def print_checks(checks: list[Check], *, json_output: bool) -> None:
    if json_output:
        print(json.dumps([asdict(check) for check in checks], indent=2, sort_keys=True))
        return
    for check in checks:
        print(f"[{check.status}] {check.name}: {check.message}")


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than zero")
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Path to HoldType-iOS.app")
    parser.add_argument(
        "--tool-timeout",
        type=positive_float,
        default=DEFAULT_TOOL_TIMEOUT_SECONDS,
        help="Maximum seconds for each local inspection tool (default: 10)",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable checks")
    parser.add_argument(
        "--allow-manual",
        action="store_true",
        help="Return success when checks explicitly remain manual",
    )
    arguments = parser.parse_args()

    runner = lambda command: run_command(command, timeout=arguments.tool_timeout)
    checks = collect_checks(arguments.app, runner=runner)
    print_checks(checks, json_output=arguments.json)
    if any(check.status == "fail" for check in checks):
        return 1
    if not arguments.allow_manual and any(
        check.status == "manual" for check in checks
    ):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
