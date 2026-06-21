---
id: VT-030
title: Permissions Umbrella
status: in-progress
priority: P1
lane: permissions
dependencies:
  - VT-031
  - VT-032
  - VT-033
  - VT-034
allowed_paths:
  - backlog/**
  - docs/specs/features/privacy-and-permissions.md
---

# VT-030 - Permissions Umbrella

Status: in-progress

## Goal

Close out the MVP permission behavior after microphone and accessibility child
tasks land.

## Child Tasks

- VT-031 microphone permission status
- VT-032 accessibility permission status
- VT-033 permission blocked menu state
- VT-034 Settings permissions and privacy section

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
