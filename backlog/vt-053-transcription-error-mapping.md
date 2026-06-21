---
id: VT-053
title: Transcription Error Mapping
status: in-progress
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-052
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-053-transcription-error-mapping.md
---

# VT-053 - Transcription Error Mapping

Status: in-progress

## Goal

Map common transcription failures to compact app states and operator-readable
messages.

## Scope

- Handle missing API key, invalid API key, rate limit, network timeout, empty
  audio, and server error.
- Keep logs short and avoid payload dumps.
- Do not add retry loops in this task.

## Acceptance

- Each common failure has a stable enum or error case.
- Menu/settings UI can display a compact message.
- Tests cover at least the error mapping table.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
