---
id: VT-054
title: Transcript Trim Empty Result
status: backlog
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-052
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-054-transcript-trim-empty-result.md
---

# VT-054 - Transcript Trim Empty Result

Status: backlog

## Goal

Normalize transcription output before it reaches clipboard or paste workflows.

## Scope

- Trim whitespace.
- Treat empty output as a controlled no-text result.
- Store only the normalized last transcript.

## Acceptance

- Empty transcript does not overwrite useful clipboard content.
- Last transcript stores normalized text.
- Tests cover whitespace-only output.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
