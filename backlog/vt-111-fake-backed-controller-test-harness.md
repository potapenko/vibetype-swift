---
id: VT-111
title: Fake Backed Controller Test Harness
status: backlog
priority: P2
lane: testing
parent: VT-110
dependencies:
  - VT-121
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-111-fake-backed-controller-test-harness.md
---

# VT-111 - Fake Backed Controller Test Harness

Status: backlog

## Goal

Extend the fake-backed test harness for dictation controller state changes.

## Scope

- Use the controller boundary from VT-121.
- Use fake services instead of microphone, network, Keychain, clipboard, or
  paste side effects.
- Cover one additional controller transition not already covered by VT-121 to
  VT-124.
- Keep real OpenAI and real microphone access out of tests.

## Acceptance

- A deterministic test extends controller transition coverage.
- Test code can be extended by later recording, transcription, and paste tasks.
- No normal test requires system permissions or live credentials.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
