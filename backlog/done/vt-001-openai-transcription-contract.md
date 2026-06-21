---
id: VT-001
status: done
priority: P0
lane: specs
dependencies:
allowed_paths:
  - docs/specs/**
verification:
  - git diff --check
---

# OpenAI Transcription Contract Spec

Status: done
Priority: P0
Lane: specs
Dependencies: none
Expected outputs: feature spec update, backlog update if needed, verification result
Verification: git diff --check

## Goal

Create the product-level OpenAI transcription contract before implementing
`OpenAITranscriptionService`.

## Scope

- Define request/response behavior for transcription.
- Define model setting behavior, language setting behavior, prompt/vocabulary
  hint behavior, timeout policy, retry policy, and error mapping.
- Define what happens when the API key is missing, invalid, rate-limited, or
  when the transcription is empty.
- Update `docs/specs/backlog.md` if this removes or changes an open item.

## Non-goals

- Do not implement URLSession upload code.
- Do not call the live OpenAI API.
- Do not add provider abstractions beyond the OpenAI MVP contract.

## Acceptance

- A concise spec exists under `docs/specs/features/`.
- The spec names user-visible errors and timeout behavior.
- The spec keeps API key secrecy and logging constraints explicit.
- Verification command passes.

## Notes

- Read `docs/openwhispr_swiftui_codex_tz.md`.
- Read `docs/specs/features/microphone-text-input.md`.
- Read `docs/specs/features/privacy-and-permissions.md`.
- Read `docs/specs/features/settings-and-secret-storage.md`.
