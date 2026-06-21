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
- 2026-06-22: `VT-158` produced a concrete product delta by adding executable
  menu-surface state coverage (`MenuBarPresentation` and
  `MenuBarPresentationTests`) for identity, permission copy, recording action
  labels/enabled states, transcript display/copy state, Settings, and Quit.
  The umbrella remains blocked because required Xcode build/test verification
  timed out before compiler output or unit-test execution, and runtime menu QA
  could not run without a fresh build product and a macOS menu interaction
  tool.

## Resolution Path

- Blocker category: local Xcode build/test tooling timeout before compiler or
  unit-test execution; runtime menu QA also requires a build product and a
  macOS UI interaction surface that can operate the menu bar extra.
- Follow-up: `VT-158` in `backlog/vt-158-menu-bar-mvp-runtime-closeout.md`
  now owns the executable closeout evidence and current blocker details.
- Existing infrastructure evidence: `VT-148`
  (`backlog/done/vt-148-xcode-build-service-health.md`) records the same
  automation-recoverable Xcode build-service timeout class.
- Unblock condition: rerun local tooling recovery, then rerun the VT-158 build
  and focused unit-test gates until Xcode reaches compiler output and executes
  `vibetypeTests`; perform bounded menu runtime QA if a macOS UI interaction
  tool is available.
- Current run could not mark this umbrella done because the new executable
  menu coverage could not be verified through the required Xcode gates.
