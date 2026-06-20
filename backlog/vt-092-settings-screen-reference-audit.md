---
id: VT-092
title: Settings Screen Reference Audit
status: done
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-092-settings-screen-reference-audit.md
  - backlog/**
---

# VT-092 - Settings Screen Reference Audit

Status: done

## Goal

Audit OpenWhispr settings screens and create missing small tasks for MVP
settings sections.

## Scope

- Inspect `references/openwhispr-main/src/components/SettingsPage.tsx`.
- Focus on API key, model, language, hotkey, microphone, and permissions.
- Treat advanced dictionary, snippets, and analytics behavior as out of scope
  unless the MVP spec already requires it.

## Acceptance

- Missing MVP settings work is represented as small child tasks.
- Unsupported advanced reference features are not added as implementation tasks.
- Docs remain product-level.

## Audit Notes

- Reviewed `references/openwhispr-main/src/components/SettingsPage.tsx`,
  `references/openwhispr-main/src/components/TranscriptionModelPicker.tsx`,
  `references/openwhispr-main/src/components/ui/ApiKeyInput.tsx`, and
  `references/openwhispr-main/src/components/ui/MicrophoneSettings.tsx`.
- Existing VibeType backlog already covers Keychain API-key storage, API-key
  Settings UI, core output toggles, microphone permission status, Accessibility
  status, and permission-blocked menu state.
- Added VT-025 for model, language, custom language, and prompt Settings UI.
- Added VT-026 for read-only hotkey display and activation-mode status.
- Added VT-034 for the Settings privacy/permissions section and OpenAI audio
  disclosure.
- Did not add tasks for OpenWhispr accounts, billing, cloud backup, telemetry,
  local model downloads, self-hosted endpoints, multi-provider tabs, system
  audio capture, microphone device selection, dictionary/snippets, meeting
  transcription, or raw-audio retention because those are outside the current
  MVP specs.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
