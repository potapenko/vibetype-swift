---
id: VT-117
title: iOS Containing App Target Skeleton
status: blocked
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

Status: blocked

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
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`

## Implementation Notes

- Added a minimal native SwiftUI `vibetype-iOS` containing-app target and
  shared scheme.
- Added a small iOS setup/status surface that identifies VibeType and states
  keyboard setup, recording, transcription, and text insertion are not enabled
  yet.
- Kept macOS target behavior unchanged and did not add keyboard-extension,
  microphone, OpenAI, paste, shared-container, Open Access, or persistence
  behavior.
- Updated the iOS feasibility spec to preserve the skeleton target's limited
  visible contract.

## Blocker Evidence

- `xcodebuild -list -project vibetype.xcodeproj` lists targets
  `vibetype`, `vibetype-iOS`, `vibetypeTests`, and `vibetypeUITests`; schemes
  `vibetype` and `vibetype-iOS`.
- `xmllint --noout
  vibetype.xcodeproj/xcshareddata/xcschemes/vibetype-iOS.xcscheme`
  passed.
- `xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library -target
  arm64-apple-ios17.0-simulator vibetypeIOS/VibeTypeIOSApp.swift`
  passed.
- XcodeBuildMCP `list_sims` failed without returning available simulators.
- XcodeBuildMCP `build_sim` reached Xcode but failed because no concrete
  installed simulator matched the requested destination; Xcode reports only the
  generic `Any iOS Simulator Device` placeholder for the iOS scheme.
- Direct `xcodebuild -project vibetype.xcodeproj -scheme vibetype-iOS
  -destination 'generic/platform=iOS Simulator' -derivedDataPath
  /tmp/vibetype-swift-vt117-direct-derived build` was interrupted after a
  bounded wait while stuck in Xcode build-service external-tool probing.
- Required macOS build `xcodebuild -project vibetype.xcodeproj -scheme
  vibetype -destination 'platform=macOS' build` was also interrupted after a
  bounded wait while stuck in the same Xcode build-service external-tool
  probing phase.
- `git diff --check` passed.
- 2026-06-22 11:37 CEST: blocker-resolution sweep reran
  `/opt/homebrew/bin/timeout 120 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  build -quiet`; the concrete iPhone 17 Pro simulator build completed
  successfully.
- 2026-06-22 11:37 CEST: the macOS build gate
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build -quiet` completed
  successfully.
- XcodeBuildMCP was available enough to report empty session defaults, but
  then `list_sims` and a follow-up `session_show_defaults` failed with
  `Transport closed` before `session_set_defaults` or `build_run_sim` could be
  run.

## Resolution Path

Blocker category: Build iOS Apps / XcodeBuildMCP transport failure.

Current local Xcode evidence shows the target, scheme, concrete simulator, iOS
simulator build, and macOS build are present and passing. The remaining blocker
is the required Build iOS Apps/XcodeBuildMCP flow: rerun the MCP session setup
and `build_run_sim` when the MCP transport is healthy. No repository follow-up
task was created because the remaining failure is tool transport, not missing
project source.
