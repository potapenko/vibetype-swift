---
id: VT-050
title: OpenAI Transcription Umbrella
status: backlog
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

Status: backlog

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
