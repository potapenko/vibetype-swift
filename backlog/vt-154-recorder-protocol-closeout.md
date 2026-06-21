---
id: VT-154
title: Recorder Protocol Blocker Closeout
status: blocked
priority: P1
lane: recording
dependencies:
  - VT-000
  - VT-148
allowed_paths:
  - backlog/vt-041-recorder-protocol-and-fake.md
  - backlog/vt-154-recorder-protocol-closeout.md
  - docs/qa/runs/**
verification:
  - python3 scripts/local_tooling_recover.py --apply --json
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests
  - git diff --check
---

# VT-154 - Recorder Protocol Blocker Closeout

Status: blocked
Priority: P1
Lane: recording
Dependencies: VT-000, VT-148
Expected outputs: VT-041 closeout update, verification result
Verification: local tooling recovery, focused macOS unit tests, git diff --check

## Goal

Close the stale Xcode verification blocker on `VT-041` so recording adapter
work can become dependency-ready.

## Scope

- Run local tooling recovery before retrying the focused unit-test command.
- Rerun the `VT-041` narrow macOS unit-test gate from the current checkout.
- If focused tests and `git diff --check` pass, update only `VT-041` and this
  task to record completion under the verification strategy that accepts
  narrow unit evidence when the full UI-test runner needs off-console access.
- If tests still fail before execution, keep `VT-041` blocked and append the
  fresh bounded recovery/test evidence.

## Non-goals

- Do not add AVFoundation recording, microphone capture, controller wiring,
  source code, specs, or Xcode project settings in this closeout task.
- Do not run live microphone checks.

## Acceptance

- `VT-041` is either marked done with current focused unit-test evidence or
  carries fresh blocker evidence and the next automatic recovery action.
- The task preserves the recorder protocol/fake boundary without widening into
  real capture behavior.
- No unrelated backlog or source files are modified.

## Tooling Assumptions

- Use standard `xcodebuild` for the focused macOS unit-test gate.
- Treat local Xcode/build-service/test-runner problems as
  automation-recoverable before recording a remaining blocker.

## Blocker Evidence

- Local tooling recovery ran on 2026-06-21 23:08 CEST:
  `python3 scripts/local_tooling_recover.py --apply --json`.
- Recovery returned `ok: true`, removed project-scoped DerivedData at
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-cgljxvuvdfxmqbeiqfwkdshvjovc`,
  and found no stale allowlisted Xcode processes to terminate.
- The bounded focused unit-test retry
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode's `clang -v -E -dM ... /dev/null` external-tool probe, did not
  reach compiler diagnostics, test discovery, or test execution, and ended
  with `** BUILD INTERRUPTED **` / exit code 143 after the timeout.
- `git diff --check` passed before status updates.

## Resolution Path

- Blocker category: local Xcode build/test tooling timeout before the focused
  macOS unit target can execute.
- Recovery attempted: `python3 scripts/local_tooling_recover.py --apply --json`
  removed generated project DerivedData and found no stale allowlisted
  processes.
- Fresh bounded retry result: the focused `vibetypeTests` command still timed
  out before test execution.
- Unblock condition: rerun local tooling recovery, then rerun
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
  If it reaches and passes `vibetypeTests`, mark `VT-041` and this closeout
  done using the verification-strategy policy for narrow target evidence when
  only the full UI-test runner requires off-console access. If it still times
  out before execution, continue automatic local Xcode tooling repair and
  append fresh recovery/retry evidence.
