---
id: VT-060
title: Text Output Umbrella
status: in-progress
priority: P1
lane: text-output
dependencies:
  - VT-061
  - VT-062
  - VT-063
  - VT-064
allowed_paths:
  - backlog/**
  - docs/specs/features/text-output-workflow.md
---

# VT-060 - Text Output Umbrella

Status: in-progress

## Goal

Close out copy and auto-paste behavior after child tasks land.

## Child Tasks

- VT-061 clipboard snapshot and copy
- VT-062 accessibility-gated paste event
- VT-063 clipboard restore after paste
- VT-064 last transcript menu integration

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
