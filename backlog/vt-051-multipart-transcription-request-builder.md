---
id: VT-051
title: Multipart Transcription Request Builder
status: done
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-001
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-051-multipart-transcription-request-builder.md
---

# VT-051 - Multipart Transcription Request Builder

Status: done

## Goal

Create a testable builder for the OpenAI audio transcription multipart request.

## Scope

- Build request body and headers without performing network I/O.
- Include model, optional language, optional prompt, and audio file.
- Avoid logging secrets or audio payloads.

## Acceptance

- Unit tests can inspect the request shape.
- Missing file or unsupported input is a controlled error.
- No live OpenAI request is sent.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
