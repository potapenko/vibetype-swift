---
id: VT-165
title: Contextual Transcription Prompt
status: in-progress
priority: P0
lane: transcription
dependencies:
  - VT-052
  - VT-121
  - VT-123
  - VT-162
allowed_paths:
  - backlog/vt-165-contextual-transcription-prompt.md
  - docs/specs/features/openai-transcription.md
  - docs/specs/features/privacy-and-permissions.md
  - docs/specs/features/settings-and-secret-storage.md
  - vibetype/Models/AppSettings.swift
  - vibetype/Services/ActiveTextContextService.swift
  - vibetype/Services/DictationSessionController.swift
  - vibetype/Services/OpenAITranscriptionRequestBuilder.swift
  - vibetype/Services/OpenAITranscriptionService.swift
  - vibetype/Settings/TranscriptionSettingsSection.swift
  - vibetypeTests/AppSettingsTests.swift
  - vibetypeTests/ActiveTextContextServiceTests.swift
  - vibetypeTests/DictationSessionControllerTests.swift
  - vibetypeTests/OpenAITranscriptionRequestBuilderTests.swift
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# VT-165 - Contextual Transcription Prompt

Status: in-progress
Priority: P0
Lane: transcription
Dependencies: VT-052, VT-121, VT-123, VT-162
Expected outputs: spec update, contextual prompt service, request/controller wiring, fake-backed tests
Verification: xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test; git diff --check

## Goal

Improve transcription quality for continued writing by sending bounded nearby
text as ephemeral transcription prompt context when the user enables it.

## Scope

- Update transcription, settings, and privacy specs for active-text context.
- Add a native macOS Accessibility-backed context reader with safe fallback.
- Compose manual prompt, custom dictionary, and nearby text context into the
  OpenAI transcription `prompt` field.
- Wire the dictation controller so each stopped recording can use a fresh
  context snapshot.
- Add fake-backed unit tests; do not call live OpenAI.

## Non-goals

- Persistent transcript history changes.
- Automatic dictionary learning from target-app edits.
- Realtime or streaming transcription.
- Reading secure text fields.
- Logging prompt/context/transcript contents.
- UI runtime smoke beyond unit/build verification.

## Acceptance

- The feature is off by default.
- When enabled and Accessibility/context reading succeeds, only a bounded text
  excerpt near the cursor is added to the OpenAI prompt.
- If context is unavailable, denied, unsupported, empty, or secure, transcription
  proceeds with the existing prompt/dictionary behavior.
- Context text is not stored in history and is not logged.
- Tests cover prompt composition, disabled fallback, context trimming, and
  controller wiring.
