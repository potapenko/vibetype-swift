---
id: VT-012
title: Start Stop Menu Label Binding
status: in-progress
priority: P0
lane: swift-app-shell
parent: VT-010
dependencies:
  - VT-011
allowed_paths:
  - vibetype/**
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-012-start-stop-menu-label-binding.md
---

# VT-012 - Start Stop Menu Label Binding

Status: in-progress

## Goal

Bind the menu's primary dictation action label to app state so the menu can
show `Start Recording` or `Stop Recording` at the right time.

## Scope

- Update the menu item label from the state model.
- Add a placeholder state toggle only if needed for local verification.
- Keep service behavior out of scope.

## Acceptance

- Idle state shows a start action.
- Recording state shows a stop action.
- Transcribing or blocked states cannot start parallel work.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
