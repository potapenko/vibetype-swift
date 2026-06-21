---
id: VT-031
title: Microphone Permission Status
status: done
priority: P1
lane: permissions
parent: VT-030
dependencies:
  - VT-000
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-031-microphone-permission-status.md
---

# VT-031 - Microphone Permission Status

Status: done

## Goal

Add a Swift-native way to read and request microphone permission for the MVP.

## Scope

- Use AVFoundation permission APIs.
- Return explicit allowed, denied, not determined, or unavailable states.
- Keep actual recording out of this task.

## Acceptance

- Permission state can be queried without starting recording.
- Request flow is bounded and callback-driven.
- Tests use fakes if real permission prompts are not practical.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker Evidence

- Implemented a Swift-native microphone permission status service and fake-backed
  unit coverage.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  failed after unit tests passed because `vibetypeUITests-Runner` could not
  initialize off-console: `User interaction required. Can't authenticate off console`.
- Narrow verification passed:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
- `git diff --check` passed.

## Resolution Path

- Blocker category: full scheme UI-test runner cannot authenticate
  off-console.
- Unblock condition: rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`; if they still pass, apply the
  `verification-strategy.md` policy that accepts narrow target evidence when
  only the UI-test runner needs off-console interaction.
- A blocker-resolution pass may then mark this task done without additional
  source edits because the microphone permission service and fake-backed tests
  are already present.

## Resolution Evidence

- 2026-06-21: Focused unit verification passed during the unblock audit:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
- A later resolver rerun of the same command, plus a
  `-skip-testing:vibetypeUITests` variant, was interrupted after Xcode stalled
  in `com.apple.dt.xctest.target-runner` finalization. No source files changed
  between the passing focused unit run and this resolver status update.
- Fresh bounded build verification passed:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`.
- Fresh `git diff --check` passed.
- Applied `docs/specs/features/verification-strategy.md` policy for accepting
  narrow target evidence when the remaining failure is the full Xcode/UI test
  runner rather than the microphone permission implementation.
