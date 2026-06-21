---
id: VT-054
title: Transcript Trim Empty Result
status: in-progress
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-052
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-054-transcript-trim-empty-result.md
---

# VT-054 - Transcript Trim Empty Result

Status: in-progress

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

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
