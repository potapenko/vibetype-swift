---
id: VT-082
title: Indicator Panel Skeleton
status: in-progress
priority: P3
lane: indicator
parent: VT-080
dependencies:
  - VT-004
  - VT-011
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-082-indicator-panel-skeleton.md
---

# VT-082 - Indicator Panel Skeleton

Status: in-progress

## Goal

Add the first native floating indicator panel skeleton.

## Scope

- Add a small state-to-indicator presentation model for idle, recording,
  transcribing, success, and failure.
- Use SwiftUI/AppKit as appropriate for a lightweight floating panel.
- Bind only to existing app state and the `showFloatingIndicator` setting.
- Do not add recording, transcription, or paste behavior.
- Keep animation and polish out of this task.

## Acceptance

- Idle maps to hidden, recording/transcribing map to visible working states,
  and success/failure map to brief visible completion states.
- The `showFloatingIndicator` setting can suppress every visible indicator
  state without disabling app status.
- Indicator can be shown and hidden through state.
- It does not steal focus from the active app.
- It builds without external UI dependencies.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
- `git diff --check`
