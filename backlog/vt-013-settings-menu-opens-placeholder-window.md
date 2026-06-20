---
id: VT-013
title: Settings Menu Opens Placeholder Window
status: done
priority: P1
lane: settings
parent: VT-010
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-013-settings-menu-opens-placeholder-window.md
---

# VT-013 - Settings Menu Opens Placeholder Window

Status: done

## Goal

Add a Settings menu item that opens a native SwiftUI settings window or panel.

## Scope

- Add the menu entry.
- Add a minimal settings view shell.
- Do not add real fields, Keychain, or persistence in this task.

## Acceptance

- Menu has a Settings item.
- Activating Settings opens a native window or settings scene.
- The window has VibeType settings branding or title text.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
