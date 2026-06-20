---
id: VT-000
title: First Menu Bar Item Shell
status: done
priority: P0
lane: swift-app-shell
dependencies:
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetype.xcodeproj/**
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-000-first-menu-bar-item-shell.md
---

# VT-000 - First Menu Bar Item Shell

Status: done

## Goal

Make the first implementation checkpoint visible by turning the default SwiftUI
template into a native macOS menu bar surface with at least one VibeType menu
item.

## Scope

- Add the minimal native menu bar entry for VibeType.
- Add a visible menu item for starting dictation, even if it is still a
  placeholder action.
- Keep the default app launch stable.
- Do not implement microphone recording, OpenAI calls, hotkeys, or settings
  persistence in this task.

## Acceptance

- The app builds.
- A native menu bar surface exists.
- The menu contains a VibeType dictation entry such as `Start Recording`.
- Placeholder actions are clearly bounded and do not pretend recording works.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
