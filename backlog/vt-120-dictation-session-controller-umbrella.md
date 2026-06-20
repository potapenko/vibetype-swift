---
id: VT-120
title: Dictation Session Controller Umbrella
status: backlog
priority: P2
lane: controller
dependencies:
  - VT-121
  - VT-122
  - VT-123
  - VT-124
allowed_paths:
  - backlog/**
  - docs/specs/features/microphone-text-input.md
  - docs/specs/features/openai-transcription.md
  - docs/specs/features/text-output-workflow.md
---

# VT-120 - Dictation Session Controller Umbrella

Status: backlog

## Goal

Close out the fake-backed MVP session controller after recording,
transcription, and text output boundaries exist.

## Child Tasks

- VT-121 controller service boundary
- VT-122 controller start and stop recording flow
- VT-123 controller successful transcription output flow
- VT-124 controller failure and cancel state flow

## Source Evidence

- `docs/openwhispr_swiftui_codex_tz.md`
- `references/openwhispr-main/src/hooks/useAudioRecording.js`
- `references/openwhispr-main/src/utils/permissions.ts`

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
