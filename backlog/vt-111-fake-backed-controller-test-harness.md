---
id: VT-111
title: Fake Backed Controller Test Harness
status: backlog
priority: P2
lane: testing
parent: VT-110
dependencies:
  - VT-011
  - VT-041
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-111-fake-backed-controller-test-harness.md
---

# VT-111 - Fake Backed Controller Test Harness

Status: backlog

## Goal

Add the first fake-backed test harness for dictation controller state changes.

## Scope

- Use fake services instead of microphone, network, Keychain, clipboard, or
  paste side effects.
- Cover a small idle-to-recording or recording-to-transcribing transition.
- Keep real OpenAI and real microphone access out of tests.

## Acceptance

- A deterministic test covers one controller state transition.
- Test code can be extended by later recording, transcription, and paste tasks.
- No normal test requires system permissions or live credentials.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
