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
- automatic insertion, app clipboard, recording, and indicator toggles
- transcript history toggle and clear action
- prompt and custom dictionary settings

## Non-goals

- account management
- cloud sync
- team policy management
- full hotkey customization UI
- provider marketplaces, local model downloads, self-hosted transcription
  endpoints, or multi-provider settings beyond the OpenAI MVP
- microphone input device selection
- usage analytics, telemetry, billing, or cloud-backup controls
- persistent raw-audio retention settings
- secure enclave or enterprise secrets management
- cloud dictionary sync
- automatic learning from corrections in other apps

## User-visible behavior

- Before concrete settings fields exist, Settings may open a native placeholder
  window titled for VibeType settings. The placeholder must not show fake or
  nonfunctional form controls.
- The Settings window should use sidebar navigation once it contains multiple
  settings groups. The sidebar should provide stable entries for General,
  OpenAI, Transcription, Shortcut, Behavior, and Privacy, with the selected
  entry shown in the detail pane.
- The Settings window should include OpenAI API Key.
- The OpenAI API key should be saved locally in macOS Keychain.
- Saving an API key should clear the entry field and show only saved, missing,
  or error state. The full saved key must not be echoed back in Settings.
- A saved API key may be replaced by entering a new key, and the user may
  remove the saved key from Settings.
- The Settings window should include transcription model.
- The Settings window should include language setting: Auto, English, Russian,
  or Custom.
- Transcription model, language, and prompt settings apply to the OpenAI
  file-transcription MVP only. Settings should not expose local model
  downloads, provider tabs, self-hosted endpoints, or account-backed
  transcription modes unless a future spec changes scope.
- The Settings window should include hotkey display.
- The hotkey row is read-only for MVP and shows the active shortcut,
  activation mode, and unavailable/fallback status when known.
- The Settings window should include an Insert transcripts automatically
  toggle.
- Insert transcripts automatically controls whether accepted transcripts are
  inserted into the active app after transcription succeeds.
- The Settings window should include a Save to VibeType Clipboard toggle.
- Save to VibeType Clipboard controls the app-owned clipboard used by
  `Control+Command+V`. It must not copy transcripts to the macOS system
  clipboard and must not disable automatic insertion.
- The Settings window should include toggles for short dictation start/stop
  sounds and the floating recording indicator.
- Dictation sounds should be short, non-verbal cues. The start cue should make
  recording start noticeable without requiring the user to watch the screen.
- The Settings window should include a Save Transcript History toggle and a
  Clear Transcript History action once persistent history is implemented.
- The Settings window should include an optional prompt field for transcription
  guidance.
- The Settings window should include a dedicated Dictionary section where the
  user can manually add and remove local words or phrases that should be
  recognized with exact spelling when spoken.
- Missing API key should be reported as a user-visible blocked state before
  transcription is attempted.
- Settings should include a privacy and permissions section that shows
  microphone and Accessibility status, provides the next action for blocked
  permissions, and states that audio is sent to OpenAI for transcription.

## Default settings

The MVP non-secret settings default to:

- transcription model: `gpt-4o-transcribe`
- language: Auto
- custom language code: empty
- prompt: empty
- custom dictionary: empty
- insert transcripts automatically: on
- save to VibeType Clipboard: on
- dictation start/stop sounds: on
- floating recording indicator: on
- save transcript history: off

The OpenAI API key has no UserDefaults value or default. It is Keychain-only.

## Invariants

- API key must not be stored in UserDefaults.
- API key must not be logged.
- Prompt text and custom dictionary entries must not be logged by default.
- Settings should be local-only for the MVP.
- No account, subscription, analytics, or telemetry setting should appear in the
  MVP.
- Settings changes should not require a manual external setup step after the app
  is built and launched.
- Unsupported reference settings such as accounts, analytics, cloud backup,
  system audio capture, local model management, and raw-audio retention should
  not appear in the MVP settings surface.

## Edge cases and failure policy

- If Keychain save fails, the app should show a visible error and not pretend
  the key was saved.
- If Keychain read fails during transcription, the app should show missing or
  inaccessible API key instead of making an unauthenticated request.
- If the Custom language field is empty, the app should fall back to Auto. If
  the field is non-empty and not a two- or three-letter language code, Settings
  should show a clear validation error.
- If model is empty, the app should use the configured default model or show a
  setup-needed state.
- Custom dictionary entries should trim surrounding whitespace, ignore empty
  entries, and remove duplicates case-insensitively while preserving the first
  spelling the user entered.

## Route / state / data implications

UserDefaults may store:

- selected model
- language
- automaticallyInsertTranscripts
- saveTranscriptsToAppClipboard
- soundEnabled
- showFloatingIndicator
- saveTranscriptHistory
- prompt
- custom dictionary entries

Keychain stores:

- OpenAI API key

Transcript history retention and clearing behavior is governed by
`transcript-history.md`.

The selected Settings sidebar entry is window-local UI state. Changing the
selected entry must not start, stop, cancel, or otherwise affect dictation.

## Verification mapping

- Add tests or manual QA for saving/loading settings, saving/loading/deleting
  API key, missing key errors, and ensuring logs do not contain the API key when
  implementation exists.

## Unknowns requiring confirmation

- Whether settings need import/export.
- Whether the language Custom field is free text or a constrained code.
