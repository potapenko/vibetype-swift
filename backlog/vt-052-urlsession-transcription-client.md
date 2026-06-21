---
id: VT-052
title: URLSession Transcription Client
status: in-progress
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-022
  - VT-051
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-052-urlsession-transcription-client.md
---

# VT-052 - URLSession Transcription Client

Status: in-progress

## Goal

Add the OpenAI transcription client with an injectable URL loading boundary.

## Scope

- Use `URLSession` or a testable wrapper.
- Read the API key through the secret-storage boundary.
- Apply explicit request timeout behavior.
- Tests must use a fake client, not the live OpenAI API.

## Acceptance

- Success response returns transcript text.
- Network timeout is bounded and mapped to a user-visible error.
- API key is not logged.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
