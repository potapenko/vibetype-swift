---
id: VT-148
title: Xcode Build Service Health Check
status: done
priority: P3
lane: testing
parent: VT-110
dependencies:
allowed_paths:
  - docs/qa/**
  - backlog/vt-148-xcode-build-service-health.md
---

# VT-148 - Xcode Build Service Health Check

Status: done
Priority: P3
Lane: testing
Dependencies: none
Expected outputs: QA report or fresh blocker evidence
Verification: bounded Xcode command, git diff --check

## Goal

Establish whether the local Xcode build/test service is healthy enough for
blocked Swift model/service tasks to finish their normal verification gates.

## Scope

- Run a bounded macOS unit-test health command:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
- Include blocked task `VT-023` in the retry assessment when deciding which
  tasks can safely complete after Xcode build/test health returns.
- Run `python3 scripts/local_tooling_recover.py --apply --json` before the
  health command so stale local Xcode tooling is repaired automatically.
- Record a concise QA report under `docs/qa/runs/` with the exact command,
  result, timeout or failure point, and whether blocked tasks can be retried.
- Do not change app source, tests, product specs, Xcode project settings, or
  unrelated Xcode/Simulator state.

## Acceptance

- The report names whether Xcode reached test execution.
- If the command passes, the report names the blocked task ids that are safe to
  retry for completion verification, including `VT-023` when macOS app build
  verification is healthy.
- If the command times out before compiler diagnostics or test execution, the
  report records the recovery JSON summary, fresh bounded timeout, and next
  automatic recovery action.

## Verification

- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
- `git diff --check`

## Result

Completed on 2026-06-21 with fresh bounded health evidence in
`docs/qa/runs/xcode-build-service-health-2026-06-21.md`.

The macOS unit-test health command timed out after reaching early Xcode
build-service external-tool probing and did not reach compiler diagnostics,
test discovery, or test execution. This result is now classified as an
automation-recoverable local tooling blocker. Blocked verification tasks that
cite this health check, including `VT-023`, should first run
`python3 scripts/local_tooling_recover.py --apply --json`, then retry the
bounded macOS build or unit-test command.
