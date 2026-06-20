---
id: VT-093
title: Recording Flow Reference Audit
status: backlog
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-093-recording-flow-reference-audit.md
  - backlog/**
---

# VT-093 - Recording Flow Reference Audit

Status: backlog

## Goal

Audit OpenWhispr recording flow locks and completion behavior and translate
missing behavior into small Swift tasks.

## Scope

- Inspect `references/openwhispr-main/src/hooks/useAudioRecording.js`.
- Focus on start guards, stop guards, processing state, empty audio, and
  completion handoff.
- Do not add implementation code.

## Acceptance

- Parallel recording and processing guards are covered by tasks or specs.
- Empty-audio and completion handoff behavior is represented.
- New tasks are Swift-native and verifiable.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
