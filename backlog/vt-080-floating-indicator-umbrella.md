---
id: VT-080
title: Floating Indicator Umbrella
status: backlog
priority: P3
lane: indicator
dependencies:
  - VT-004
  - VT-081
  - VT-082
allowed_paths:
  - backlog/**
  - docs/specs/features/**
---

# VT-080 - Floating Indicator Umbrella

Status: backlog

## Goal

Close out the MVP floating indicator after the spec and skeleton tasks are
complete.

## Child Tasks

- VT-004 floating indicator spec
- VT-081 indicator state contract
- VT-082 indicator panel skeleton

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
