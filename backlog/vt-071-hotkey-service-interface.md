---
id: VT-071
title: Hotkey Service Interface
status: backlog
priority: P2
lane: hotkey
parent: VT-070
dependencies:
  - VT-000
  - VT-002
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-071-hotkey-service-interface.md
---

# VT-071 - Hotkey Service Interface

Status: backlog

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

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
