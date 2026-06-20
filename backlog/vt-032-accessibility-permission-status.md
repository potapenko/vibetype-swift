---
id: VT-032
title: Accessibility Permission Status
status: done
priority: P1
lane: permissions
parent: VT-030
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-032-accessibility-permission-status.md
---

# VT-032 - Accessibility Permission Status

Status: done

## Goal

Add a Swift-native accessibility permission status helper for paste automation.

## Scope

- Use macOS accessibility trust APIs.
- Provide a non-destructive status check.
- Add an action or helper to open the relevant system settings if feasible.

## Acceptance

- App can distinguish trusted and not trusted states.
- The helper does not trigger repeated noisy prompts by default.
- Status is available to menu/settings UI.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
