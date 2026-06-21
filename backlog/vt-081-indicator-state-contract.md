---
id: VT-081
title: Indicator State Contract
status: blocked
priority: P3
lane: indicator
parent: VT-080
dependencies:
  - VT-004
  - VT-011
allowed_paths:
  - docs/specs/features/**
  - backlog/vt-081-indicator-state-contract.md
---

# VT-081 - Indicator State Contract

Status: blocked

## Goal

Specify exactly which app states the floating indicator needs to display.

## Scope

- Map idle, recording, transcribing, success, and error states.
- Decide whether idle indicator is hidden or visible.
- Do not implement UI.

## Acceptance

- Indicator spec has a compact state table.
- Implementation can be split into a separate panel task.
- No behavior depends on chat-only decisions.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Blocker

This task is blocked for the implementer automation because its selected scope
is documentation-only, its allowed paths exclude app or test code, and its
scope explicitly says not to implement UI. Completing it as `done` would not
produce the required product delta for this automation.

## Resolution Path

- Blocker category: no product delta possible from selected scope.
- Follow-up: VT-082 (`backlog/vt-082-indicator-panel-skeleton.md`).
- Current follow-up state: VT-082 is now `done`; it added the first native
  indicator presentation/panel skeleton and executable state mapping.
- Unblock condition: a blocker-resolution closeout may confirm VT-082 remains
  done, rerun `python3 scripts/backlog_next.py --json` and `git diff --check`,
  and close this documentation contract without Swift edits.
- Current-run limit: this groomer can refine task metadata, but it must not
  mark tasks done and cannot add Swift app or test code under VT-081's allowed
  paths.
