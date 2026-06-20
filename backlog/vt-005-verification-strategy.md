---
id: VT-005
status: in-progress
priority: P1
lane: testing
dependencies:
  - VT-001
  - VT-002
allowed_paths:
  - docs/specs/**
  - docs/**
  - backlog/**
verification:
  - git diff --check
---

# Verification Strategy Spec

Status: in-progress
Priority: P1
Lane: testing
Dependencies: VT-001, VT-002
Expected outputs: verification strategy document or spec update, verification result
Verification: git diff --check

## Goal

Define the first testable seams and manual QA boundaries for microphone,
transcription, permissions, timeout behavior, and text handoff.

## Scope

- Identify which behavior should use unit tests, fakes, UI tests, or manual QA.
- Define bounded timeout expectations for tests.
- Define what must never hit live OpenAI or uncontrolled platform prompts in
  normal automated tests.
- Add follow-up implementation tasks if needed.

## Non-goals

- Do not implement test infrastructure in this task unless the selected scope
  is explicitly expanded.
- Do not call live external services.

## Acceptance

- Verification strategy is durable in docs/specs or docs.
- The strategy maps MVP services to test seams.
- Verification command passes.

## Notes

- Depends on the OpenAI and hotkey product contracts because they shape the
  first test seams.
