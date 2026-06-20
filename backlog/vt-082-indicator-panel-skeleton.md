---
id: VT-082
title: Indicator Panel Skeleton
status: backlog
priority: P3
lane: indicator
parent: VT-080
dependencies:
  - VT-081
allowed_paths:
  - vibetype/vibetype/**
  - docs/specs/features/**
  - backlog/vt-082-indicator-panel-skeleton.md
---

# VT-082 - Indicator Panel Skeleton

Status: backlog

## Goal

Add the first native floating indicator panel skeleton.

## Scope

- Use SwiftUI/AppKit as appropriate for a lightweight floating panel.
- Bind only to existing app state.
- Keep animation and polish out of this task.

## Acceptance

- Indicator can be shown and hidden through state.
- It does not steal focus from the active app.
- It builds without external UI dependencies.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
