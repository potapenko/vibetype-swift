---
id: VT-090
title: OpenWhispr Reference Audit Umbrella
status: in-progress
priority: P2
lane: reference-audit
dependencies:
  - VT-006
  - VT-091
  - VT-092
  - VT-093
  - VT-094
allowed_paths:
  - backlog/**
  - docs/specs/**
---

# VT-090 - OpenWhispr Reference Audit Umbrella

Status: in-progress

## Goal

Close out reference-driven task discovery for the MVP after small audit slices
are complete.

## Child Tasks

- VT-006 initial reference audit
- VT-091 tray and app menu audit
- VT-092 settings screen audit
- VT-093 recording flow audit
- VT-094 clipboard and paste audit

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
