---
id: VT-025
title: Transcription Settings Fields UI
status: backlog
priority: P2
lane: settings
parent: VT-020
dependencies:
  - VT-013
  - VT-021
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/openai-transcription.md
  - backlog/vt-025-transcription-settings-fields-ui.md
---

# VT-025 - Transcription Settings Fields UI

Status: backlog

## Goal

Expose the MVP transcription settings in the native Settings window.

## Scope

- Add Settings controls for transcription model, language mode, custom language
  code, and prompt or vocabulary hint.
- Bind controls to the existing non-secret settings model and store.
- Keep the UI OpenAI-file-transcription focused.
- Show validation or fallback behavior for empty model and invalid custom
  language values according to the specs.

## Non-goals

- Do not add live OpenAI calls, remote model-list loading, or provider tests.
- Do not add local model downloads, self-hosted endpoint configuration, or
  multi-provider settings.
- Do not add API key storage or API key UI; those stay in VT-022 and VT-023.
- Do not add recording, transcription upload, or paste behavior.

## Acceptance

- Settings lets the user edit model, language, custom language, and prompt
  values.
- Values persist through the existing settings store.
- OpenAI-only MVP scope is clear; unsupported OpenWhispr provider/local-model
  controls are absent.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
