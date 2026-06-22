---
id: VT-050
title: OpenAI Transcription Umbrella
status: blocked
priority: P1
lane: transcription
dependencies:
  - VT-001
  - VT-051
  - VT-052
  - VT-053
  - VT-054
allowed_paths:
  - backlog/**
  - docs/specs/features/**
---

# VT-050 - OpenAI Transcription Umbrella

Status: blocked

## Goal

Close out the MVP OpenAI transcription path after contract and implementation
children land.

## Child Tasks

- VT-001 transcription contract spec
- VT-051 multipart request builder
- VT-052 URLSession transcription client
- VT-053 transcription error mapping
- VT-054 transcript trimming and empty-result handling

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Blocker

Reason: no product delta possible from selected scope.

This umbrella closeout can only edit backlog and spec files, so the implementer
automation cannot produce app behavior, Swift source, executable tests,
build/runtime capability, or a product bug fix in this selected scope. The
OpenAI transcription service children are complete, but closing this task as
done would be a paperwork-only completion.

## Resolution Path

- Blocker category: no product delta possible from selected scope.
- Follow-up: VT-121 (`backlog/vt-121-controller-service-boundary.md`).
- Unblock condition: implement VT-121 so the app has a Swift-native dictation
  controller boundary with injected recording, transcription, settings, and
  output dependencies.
- Why this run could not finish it directly: VT-050 allows only backlog and
  spec paths; VT-121 is the existing concrete implementation task that can
  produce the smallest safe product delta by making completed transcription
  service behavior consumable by menu and future hotkey flows.
