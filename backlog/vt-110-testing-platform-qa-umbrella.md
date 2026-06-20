---
id: VT-110
title: Testing And Platform QA Umbrella
status: backlog
priority: P2
lane: testing
dependencies:
  - VT-111
  - VT-112
  - VT-113
  - VT-114
  - VT-115
  - VT-116
allowed_paths:
  - backlog/**
  - docs/specs/features/platform-testing-strategy.md
  - docs/qa/**
---

# VT-110 - Testing And Platform QA Umbrella

Status: backlog

## Goal

Close out the platform testing plan after the small QA child tasks are complete.

## Child Tasks

- VT-111 fake-backed controller test harness
- VT-112 macOS menu bar Computer Use smoke checklist
- VT-113 iOS keyboard feasibility spec
- VT-114 iOS simulator baseline
- VT-115 shared SwiftUI screen QA split
- VT-116 QA evidence template

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
