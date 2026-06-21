---
id: VT-010
title: Menu Bar MVP Umbrella
status: in-progress
priority: P0
lane: swift-app-shell
dependencies:
  - VT-000
  - VT-015
  - VT-011
  - VT-012
  - VT-013
  - VT-014
allowed_paths:
  - backlog/**
  - docs/specs/features/menu-bar-app-shell.md
---

# VT-010 - Menu Bar MVP Umbrella

Status: in-progress

## Goal

Close out the native menu bar MVP shell after its child tasks are implemented.

## Scope

- Review the completed menu bar child tasks together.
- Confirm the menu matches the MVP product spec.
- Patch only small gaps in docs or backlog discovered during closeout.

## Child Tasks

- VT-000 first visible menu bar item
- VT-015 menu bar identity and tooltip
- VT-011 app state model
- VT-012 start/stop label binding
- VT-013 settings menu opens a window
- VT-014 last transcript menu placeholders

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
