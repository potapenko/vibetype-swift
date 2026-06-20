---
id: VT-100
title: Backlog Grooming Automation Umbrella
status: in-progress
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

Status: in-progress

## Goal

Close out the backlog grooming automation workflow after the first groomer
contract is in place.

## Child Tasks

- VT-101 backlog groomer prompt dry-run check

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
