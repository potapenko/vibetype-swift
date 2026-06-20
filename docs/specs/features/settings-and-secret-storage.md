# Settings And Secret Storage

## Goal

Define the first settings and secret-storage contract for VibeType.

The app needs simple local settings for dictation behavior while keeping the
OpenAI API key out of plain text settings and logs.

## Scope

This spec covers:

- settings visible in the Settings window
- UserDefaults-backed non-secret settings
- Keychain-backed OpenAI API key
- copy, paste, recording, and indicator toggles
- transcript history toggle and clear action
- prompt or vocabulary hint setting

## Non-goals

- account management
- cloud sync
- team policy management
- full hotkey customization UI
- secure enclave or enterprise secrets management

## User-visible behavior

- Before concrete settings fields exist, Settings may open a native placeholder
  window titled for VibeType settings. The placeholder must not show fake or
  nonfunctional form controls.
- The Settings window should include OpenAI API Key.
- The OpenAI API key should be saved locally in macOS Keychain.
- The Settings window should include transcription model.
- The Settings window should include language setting: Auto, English, Russian,
  or Custom.
- The Settings window should include hotkey display.
- The Settings window should include toggles for auto-paste, copy to clipboard,
  restoring the previous clipboard, sound on start/stop, and floating recording
  indicator.
- The Settings window should include a Save Transcript History toggle and a
  Clear Transcript History action once persistent history is implemented.
- The Settings window should include an optional prompt or vocabulary hint
  field.
- Missing API key should be reported as a user-visible blocked state before
  transcription is attempted.

## Default settings

The MVP non-secret settings default to:

- transcription model: `gpt-4o-transcribe`
- language: Auto
- custom language code: empty
- prompt or vocabulary hint: empty
- auto-paste: on
- copy to clipboard: on
- restore previous clipboard: on
- sound on start/stop: on
- floating recording indicator: on
- save transcript history: off

The OpenAI API key has no UserDefaults value or default. It is Keychain-only.

## Invariants

- API key must not be stored in UserDefaults.
- API key must not be logged.
- Settings should be local-only for the MVP.
- No account, subscription, analytics, or telemetry setting should appear in the
  MVP.
- Settings changes should not require a manual external setup step after the app
  is built and launched.

## Edge cases and failure policy

- If Keychain save fails, the app should show a visible error and not pretend
  the key was saved.
- If Keychain read fails during transcription, the app should show missing or
  inaccessible API key instead of making an unauthenticated request.
- If a custom language field is empty or invalid, the app should fall back to
  Auto or show a clear validation error.
- If model is empty, the app should use the configured default model or show a
  setup-needed state.

## Route / state / data implications

UserDefaults may store:

- selected model
- language
- autoPaste
- copyToClipboard
- restoreClipboard
- soundEnabled
- showFloatingIndicator
- saveTranscriptHistory
- prompt or vocabulary hint

Keychain stores:

- OpenAI API key

Transcript history retention and clearing behavior is governed by
`transcript-history.md`.

## Verification mapping

- Add tests or manual QA for saving/loading settings, saving/loading/deleting
  API key, missing key errors, and ensuring logs do not contain the API key when
  implementation exists.

## Unknowns requiring confirmation

- Whether settings need import/export.
- Whether the language Custom field is free text or a constrained code.
