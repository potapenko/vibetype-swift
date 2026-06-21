---
id: VT-081
title: Indicator State Contract
status: in-progress
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

Status: in-progress

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
