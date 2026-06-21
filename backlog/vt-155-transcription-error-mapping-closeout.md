---
id: VT-155
title: Transcription Error Mapping Closeout
status: in-progress
priority: P1
lane: transcription
dependencies:
  - VT-052
  - VT-148
allowed_paths:
  - backlog/vt-053-transcription-error-mapping.md
  - backlog/vt-155-transcription-error-mapping-closeout.md
  - docs/qa/runs/**
verification:
  - python3 scripts/local_tooling_recover.py --apply --json
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests/OpenAITranscriptionServiceTests
  - git diff --check
---

# VT-155 - Transcription Error Mapping Closeout

Status: in-progress
Priority: P1
Lane: transcription
Dependencies: VT-052, VT-148
Expected outputs: VT-053 closeout update, verification result
Verification: local tooling recovery, focused macOS unit tests, git diff --check

## Goal

Close the stale Xcode verification blocker on `VT-053` so transcription error
handling can unblock controller failure-flow work.

## Scope

- Run local tooling recovery before retrying the focused unit-test command.
- Rerun the `VT-053` focused OpenAI transcription service tests from the
  current checkout.
- If focused tests and `git diff --check` pass, update only `VT-053` and this
  task to record completion.
- If tests still fail before execution, keep `VT-053` blocked and append the
  fresh bounded recovery/test evidence.

## Non-goals

- Do not change transcription service behavior, specs, tests, source code, or
  Xcode project settings in this closeout task.
- Do not call the live OpenAI API.
- Do not add retries, provider settings, payload logging, or broad controller
  work.

## Acceptance

- `VT-053` is either marked done with current focused unit-test evidence or
  carries fresh blocker evidence and the next automatic recovery action.
- Verification stays fake-backed and does not expose API keys, prompts, audio,
  transcripts, or full provider payloads in default logs.
- No unrelated backlog or source files are modified.

## Tooling Assumptions

- Use standard `xcodebuild` for the focused macOS unit-test gate.
- Treat local Xcode/build-service/test-runner problems as
  automation-recoverable before recording a remaining blocker.
