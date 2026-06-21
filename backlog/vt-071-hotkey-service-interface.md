---
id: VT-071
title: Hotkey Service Interface
status: blocked
priority: P2
lane: hotkey
parent: VT-070
dependencies:
  - VT-000
  - VT-002
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-071-hotkey-service-interface.md
---

# VT-071 - Hotkey Service Interface

Status: blocked

## Goal

Add a Swift-native service boundary for global hotkey registration.

## Scope

- Define the hotkey service API and fake implementation.
- Represent the default dictation shortcut display.
- Do not register real global events in this task unless it is already trivial.

## Acceptance

- Controller code can subscribe to a hotkey action through the boundary.
- Tests can trigger the hotkey through a fake.
- The default shortcut is visible as data.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker Evidence

- 2026-06-20: Implemented the service boundary and fake-backed tests, but
  Xcode verification did not complete in this local session.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  blocked in Xcode target-runner materialization/finalization and was
  interrupted after bounded waits.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  hit the same target-runner blocker.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' -derivedDataPath /tmp/vibetype-swift-vt071-derived build`
  also stopped returning progress after build graph creation and was
  interrupted after bounded waits.
- Narrow checks completed: app source `swiftc -typecheck` passed, app module
  `swiftc -emit-module -enable-testing` passed, and `git diff --check` passed.
