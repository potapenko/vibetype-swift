---
id: VT-041
title: Recorder Protocol And Fake
status: blocked
priority: P1
lane: recording
parent: VT-040
dependencies:
  - VT-000
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-041-recorder-protocol-and-fake.md
---

# VT-041 - Recorder Protocol And Fake

Status: blocked

## Goal

Create the recorder service boundary before adding AVFoundation details.

## Scope

- Define the recorder protocol or interface.
- Add a fake implementation suitable for tests and controller work.
- Model start, stop, cancel, and current status.

## Acceptance

- App/controller code can depend on the protocol.
- Fake recorder can simulate success and failure.
- No real microphone capture is added.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker Evidence

- Implemented the recorder protocol, status model, reusable fake recorder, and
  fake-backed unit coverage for success, failure, cancellation, and protocol
  consumption.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  failed after unit tests passed because `vibetypeUITests-Runner` cannot
  initialize off-console: `User interaction required. Can't authenticate off
  console`.
- Narrow evidence passed:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`.
- Resolver retry on 2026-06-21:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  timed out with `** BUILD INTERRUPTED **` before test execution.
- `git diff --check` passed after the timeout.
- Resolver status check on 2026-06-21 19:03 CEST found the local Xcode
  build-service blocker still present: `SWBBuildService` had been running for
  `16:05:34` with a child `clang -v -E -dM ... /dev/null` probe running for
  `04:57:43`. No bounded `xcodebuild` retry was run because the operator-only
  unblock condition was not met.
- Resolver status check on 2026-06-21 20:02 CEST found the same local Xcode
  build-service blocker still present: `SWBBuildService` had been running for
  `17:04:37` with a child `clang -v -E -dM ... /dev/null` probe running for
  `05:56:46`. No bounded `xcodebuild` retry was run because the operator-only
  unblock condition was still not met.

## Resolution Path

- Blocker category: local Xcode build-service timeout before unit-test
  execution, after the earlier full scheme UI-test runner off-console blocker.
- Existing follow-up evidence: `VT-148` records the same bounded Xcode
  build-service timeout and concludes that blocked verification tasks are not
  safe to retry until the local Xcode build service can complete a bounded
  macOS build or unit-test command.
- Operator-only status check:
  `ps -axo pid,ppid,etime,command | egrep 'SWBBuildService|clang -v -E -dM|xcodebuild|xctest'`.
  If stale Xcode build-service or toolchain-probe processes remain, clear them
  through the user-owned Xcode/Activity Monitor session or reboot, then rerun
  the bounded unit-test command.
- Unblock condition: after local Xcode build-service health is restored, rerun
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`. If both pass, apply the `verification-strategy.md`
  policy that accepts narrow target evidence when only the full UI-test runner
  needs off-console interaction, then mark this task done without additional
  source edits.
