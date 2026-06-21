---
id: VT-100
title: Backlog Grooming Automation Umbrella
status: blocked
priority: P2
lane: workflow
dependencies:
  - VT-101
allowed_paths:
  - backlog/**
  - docs/specs/features/backlog-grooming-automation.md
  - BACKLOG_DEVELOPMENT.md
---

# VT-100 - Backlog Grooming Automation Umbrella

Status: blocked

## Goal

Close out the backlog grooming automation workflow after the first groomer
contract is in place.

## Child Tasks

- VT-101 backlog groomer prompt dry-run check

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Blocker Evidence

2026-06-20:

- Blocked by the implementer automation product-first runbook: this selected
  umbrella can only change backlog, workflow, or backlog-grooming spec files,
  so no app behavior, Swift source, executable test, build/runtime capability,
  or verified product bug fix can be delivered from the selected scope.
- Reason: `no product delta possible from selected scope`.
- Exact next product change refined for the queue:
  `VT-073 - Hold To Record Activation Mode Slice`.

## Resolution Path

- Blocker category: no product delta possible from selected scope.
- Prior follow-up state: VT-073 is now `done`.
- Current unblock condition: do not requeue VT-100 for implementer product
  work. A blocker-resolution closeout may close this workflow umbrella only if
  repository policy allows metadata-only closeout of workflow tasks.
- Current product queue blocker: the selector has no dependency-ready product
  task while verification-gated Swift tasks remain blocked by local Xcode
  build/test service health.
