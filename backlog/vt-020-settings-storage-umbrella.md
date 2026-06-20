---
id: VT-020
title: Settings And Secret Storage Umbrella
status: backlog
priority: P1
lane: settings
dependencies:
  - VT-021
  - VT-022
  - VT-023
  - VT-024
allowed_paths:
  - backlog/**
  - docs/specs/features/settings-and-secret-storage.md
---

# VT-020 - Settings And Secret Storage Umbrella

Status: backlog

## Goal

Close out the MVP settings and secret-storage behavior after child tasks land.

## Child Tasks

- VT-021 settings defaults model
- VT-022 Keychain API key storage
- VT-023 API key settings UI
- VT-024 MVP settings toggles

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
