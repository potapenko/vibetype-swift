---
id: VT-117
title: iOS Containing App Target Skeleton
status: in-progress
priority: P2
lane: ios
parent: VT-110
dependencies:
  - VT-113
allowed_paths:
  - vibetype/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/platform-testing-strategy.md
  - docs/qa/**
  - backlog/vt-117-ios-containing-app-target-skeleton.md
---

# VT-117 - iOS Containing App Target Skeleton

Status: in-progress

## Goal

Add the first minimal iOS containing-app target so simulator verification has a
real app surface to build.

## Scope

- Add an iOS app target to the existing Xcode project.
- Keep the target minimal: a native SwiftUI containing app with a small
  VibeType setup/status surface is enough.
- Keep macOS target behavior unchanged.
- Do not add a keyboard extension, Open Access, shared container, microphone
  capture, OpenAI networking, paste handoff, or transcript persistence in this
  task.
- Update the iOS feasibility or platform testing specs only if the target
  introduces a user-visible platform contract not already covered there.

## Acceptance

- Xcode exposes a buildable iOS app target or scheme.
- The iOS app launches or builds in an iOS Simulator through XcodeBuildMCP or
  the Build iOS Apps flow.
- Any screenshot or UI snapshot evidence is saved under `docs/qa/` only when
  it is useful durable evidence.
- The macOS app target remains buildable.

## Verification

- XcodeBuildMCP or Build iOS Apps simulator build/run for the new iOS target.
- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
