---
id: VT-091
title: Tray Menu Reference Audit
status: done
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-091-tray-menu-reference-audit.md
  - backlog/**
---

# VT-091 - Tray Menu Reference Audit

Status: done

## Goal

Audit OpenWhispr tray and app menu behavior and create any missing small
VibeType menu tasks.

## Scope

- Inspect `references/openwhispr-main/src/helpers/tray.js`.
- Inspect `references/openwhispr-main/src/helpers/menuManager.js`.
- Add or refine backlog tasks only.
- Do not implement Swift code.

## Acceptance

- Menu behavior gaps are either covered by existing tasks or new small tasks.
- Any new tasks reference Swift-native implementation boundaries.
- No Electron behavior is copied as a dependency.

## Audit Notes

- `references/openwhispr-main/src/helpers/tray.js` maps to existing VibeType
  tasks for opening settings, quitting, and keeping the menu state current.
- OpenWhispr's show/hide dictation panel does not directly apply because
  VibeType's MVP uses a menu bar menu plus the separate floating-indicator
  contract, not an Electron dictation panel.
- `references/openwhispr-main/src/helpers/menuManager.js` reinforces the
  existing Settings entry and keyboard shortcut work; VibeType should keep this
  native rather than copying Electron application-menu roles.
- The uncovered native menu gap is the status item identity/tooltip/icon
  decision. Added `VT-015 - Menu Bar Identity And Tooltip` for that small
  Swift-native follow-up.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
