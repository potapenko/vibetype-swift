---
id: VT-144
title: iOS Keyboard Session State Model
status: done
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-113
allowed_paths:
  - vibetype/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - backlog/vt-144-ios-keyboard-session-state-model.md
verification:
  - git diff --check
  - xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype-iOS -destination 'platform=iOS Simulator' test
---

# VT-144 - iOS Keyboard Session State Model

Status: done
Priority: P3
Lane: ios-keyboard
Dependencies: VT-113
Expected outputs: keyboard session state model and fake-backed tests
Verification: git diff --check; iOS test or documented blocker

## Goal

Create a deterministic state model for the keyboard voice-session UI before
building the visual surface.

## Scope

- Model keyboard states for setup needed, idle/start, launching session,
  listening, confirming, transcribing, accepted transcript, error, and compact
  settings.
- Keep transitions pure and fake-backed so tests do not depend on microphone,
  provider network, host app text input, or simulator UI.
- Include decisions for cancel, accept, open containing app, and open inline
  settings.

## Non-goals

- Do not call OpenAI.
- Do not capture microphone audio.
- Do not insert text into a host app.
- Do not build the final keyboard layout.

## Acceptance

- State transitions are represented by small Swift types.
- Tests cover start, cancel, accept, error, settings entry, and unavailable
  paths using fakes.
- No default logs include dictated text.

## Notes

- This model should be reusable by the containing app preview surface and the
  keyboard extension where practical.
- This task is the implementation follow-up for blocked VT-141. It should turn
  the intended keyboard-visible product contract into executable Swift state
  and tests before additional iOS keyboard UI tasks depend on it.

## Completion Notes

- Added a shared pure Swift keyboard session state model for setup-needed,
  idle, launching, listening, transcribing, confirming, accepted transcript,
  error, and compact settings states.
- Added fake-backed macOS unit coverage for start, cancel, accept, error,
  compact settings, and unavailable paths.
- Added a hostless `vibetypeIOSTests` target to the iOS scheme so the same
  model has iOS simulator test-bundle coverage.
- Verification passed:
  - `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator -parse-as-library vibetype/Shared/KeyboardSessionState.swift`
  - `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype-iOS -destination 'generic/platform=iOS Simulator' build-for-testing`
  - `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests/KeyboardSessionStateTests`
- Documented iOS simulator runtime blocker: XcodeBuildMCP discovered the three
  `vibetypeIOSTests` cases, but simulator execution failed before assertions
  because the cloned simulator could not boot; an explicit existing-simulator
  retry timed out in build-for-testing and the hung run-owned `xcodebuild`
  process was terminated.
