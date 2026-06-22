---
id: VT-162
status: in-progress
priority: P1
lane: app
dependencies:
  - VT-001
  - VT-023
  - VT-025
allowed_paths:
  - docs/specs/features/openai-transcription.md
  - docs/specs/features/settings-and-secret-storage.md
  - vibetype/Models/AppSettings.swift
  - vibetype/Services/OpenAITranscriptionRequestBuilder.swift
  - vibetype/Services/OpenAITranscriptionService.swift
  - vibetype/Settings/TranscriptionSettingsSection.swift
  - vibetypeTests/AppSettingsTests.swift
  - vibetypeTests/OpenAITranscriptionRequestBuilderTests.swift
  - vibetypeTests/OpenAITranscriptionServiceTests.swift
  - backlog/vt-162-manual-custom-dictionary.md
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# Manual Custom Dictionary

Status: in-progress
Priority: P1
Lane: app
Dependencies: VT-001, VT-023, VT-025
Expected outputs: spec update, settings model/UI update, request tests, echo guard
Verification: xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test; git diff --check

## Goal

Add the first native VibeType version of the OpenWhispr custom dictionary: a
manual local list of words or phrases that is sent to OpenAI as transcription
context.

## Scope

- Preserve behavior in transcription and settings specs.
- Store a local, non-secret custom dictionary in UserDefaults-backed settings.
- Let users add and remove words or phrases from the Transcription settings
  pane.
- Combine the manual dictionary with the existing optional prompt when building
  the OpenAI transcription request.
- Reject dictionary-echo transcripts so the dictionary itself is not accepted as
  dictated text.

## Non-goals

- Auto-learning corrections from edits in other apps.
- Snippets or text expansion.
- OpenWhispr cloud sync, SQLite tombstones, accounts, billing, telemetry, or
  local model behavior.
- Live OpenAI verification.

## Acceptance

- Empty dictionary keeps the current prompt behavior.
- Dictionary entries are trimmed, empty entries are ignored, and duplicates are
  removed case-insensitively while preserving the first spelling.
- The multipart request includes a dictionary hint in the `prompt` field when
  entries exist.
- Unit tests cover settings persistence, prompt composition, and echo detection.
