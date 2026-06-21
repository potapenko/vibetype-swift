---
id: VT-010
title: Menu Bar MVP Umbrella
status: blocked
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

Status: blocked

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

## Result

- 2026-06-22: Blocked by the implementer product-first rule. This umbrella
  closeout is limited to backlog/spec paths, so the selected scope cannot
  produce app behavior, Swift source, executable tests, build/runtime
  configuration, or a verified product bug fix in the current run.
- Archived completed child tasks `VT-015` and `VT-150` before claim so the
  active selector sees only current queue work.

## Resolution Path

- Blocker category: no product delta possible from selected scope.
- Follow-up: `VT-158` in `backlog/vt-158-menu-bar-mvp-runtime-closeout.md`.
- Unblock condition: run `VT-158` to produce a concrete product delta for the
  menu bar MVP closeout, either by adding executable menu-surface coverage or
  by completing bounded runtime verification/repair against the built macOS
  app, then update this umbrella with the resulting evidence.
- Current run could not finish this directly because `VT-010` explicitly limits
  allowed paths to backlog/spec closeout files and does not authorize Swift,
  test, QA evidence, or app-run artifact changes.
