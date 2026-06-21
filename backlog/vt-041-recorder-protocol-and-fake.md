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

## Resolution Path

- Blocker category: full scheme UI-test runner cannot authenticate
  off-console.
- Unblock condition: rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`; if they still pass, apply the
  `verification-strategy.md` policy that accepts narrow target evidence when
  only the UI-test runner needs off-console interaction.
- A blocker-resolution pass may then mark this task done without additional
  source edits because the recorder protocol, fake recorder, and focused unit
  coverage are already present.
