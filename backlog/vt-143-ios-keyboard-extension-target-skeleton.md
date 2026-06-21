---
id: VT-143
title: iOS Keyboard Extension Target Skeleton
status: backlog
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-117
  - VT-141
allowed_paths:
  - vibetype/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/platform-testing-strategy.md
  - docs/qa/**
  - backlog/vt-143-ios-keyboard-extension-target-skeleton.md
verification:
  - git diff --check
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype-iOS -destination 'platform=iOS Simulator' build
---

# VT-143 - iOS Keyboard Extension Target Skeleton

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-117, VT-141
Expected outputs: keyboard extension target skeleton, verification result
Verification: git diff --check; iOS simulator build or documented blocker

## Goal

Add the first minimal iOS keyboard extension target after the containing-app
target and product contract are accepted.

## Scope

- Add a keyboard extension target to the existing Xcode project.
- Render a minimal native keyboard extension surface with required
  next-keyboard control and unavailable/setup-needed state.
- Keep the extension free of microphone capture, OpenAI networking, API key
  storage, transcript persistence, and Open Access-dependent reads.
- Add only the minimum entitlement or Info.plist configuration needed for the
  skeleton.

## Non-goals

- Do not implement voice recording or transcription.
- Do not implement shared container state.
- Do not add real settings fields inside the keyboard yet.

## Acceptance

- Xcode exposes a buildable keyboard extension target or scheme.
- The extension has a visible setup-needed surface and a next-keyboard control.
- Simulator build evidence or a bounded blocker note is recorded.

## Notes

- Follow `ios-keyboard-feasibility.md` for secure-field, next-keyboard, Open
  Access, microphone, and network constraints.
