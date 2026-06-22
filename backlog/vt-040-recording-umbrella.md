---
id: VT-040
title: Recording Umbrella
status: in-progress
priority: P1
lane: recording
dependencies:
  - VT-041
  - VT-042
  - VT-043
  - VT-044
  - VT-045
allowed_paths:
  - backlog/**
  - docs/specs/features/microphone-text-input.md
---

# VT-040 - Recording Umbrella

Status: in-progress

## Goal

Close out MVP microphone recording once the small service slices are complete.

## Child Tasks

- VT-041 recorder protocol and fake
- VT-042 start recording to a temporary file
- VT-043 stop recording and return an audio artifact
- VT-044 cancel and cleanup current recording
- VT-045 recording timeout guard

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
