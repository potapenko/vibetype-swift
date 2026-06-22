# Transcript Recovery History

## Goal

Keep recent successful dictations recoverable during the current app session so
users do not need to re-dictate long text when active-app insertion fails or the
target input changes.

## Decision

Transcript recovery history is in the MVP as a session-only local feature. It
is enabled by default because entries are kept in app memory only, are never
written to disk for this slice, and are cleared when the app quits.

Users can disable recovery history in Settings. Disabling it clears current
recovery entries and stops future history writes until it is enabled again.

The always-visible Last Transcript surface remains current-session state and
does not require recovery history to be enabled.

## Scope

This spec covers:

- session-only storage of accepted transcript text
- default history setting
- retention limit and clear behavior
- history panel behavior
- history row recovery actions
- privacy and logging boundaries
- relationship to Last Transcript and VibeType Clipboard actions

## Non-goals

- durable disk-backed transcript persistence
- raw audio retention
- retry from audio
- cloud sync, accounts, sharing, or telemetry
- full search, semantic notes, tags, folders, or review workflows
- SQLite or another database requirement for the MVP
- storing failed, empty, cancelled, discarded, or partial transcription attempts

## User-visible behavior

- Transcript recovery history is on by default for the current app session.
- Settings exposes a Keep Transcript Recovery History toggle.
- Turning recovery history off immediately clears current history entries and
  stops future history writes.
- Turning recovery history back on affects future successful dictations. It
  does not restore entries cleared earlier.
- When recovery history is on, each accepted non-empty transcript is added to
  recovery history after transcription succeeds and before active-app output
  handoff can fail.
- A failed automatic insertion or VibeType Clipboard paste must not discard the
  current Last Transcript or the recovery history row created for the accepted
  transcript.
- Recovery history keeps at most the 20 most recent accepted transcripts.
  Older entries are removed automatically when the limit is exceeded.
- The menu bar exposes a Transcript History window.
- The Transcript History window lists entries newest-first and may group them
  by day.
- Each history row shows the entry time and transcript text.
- Each history row can save only that row's text to the VibeType Clipboard when
  the app clipboard setting is enabled.
- Each history row can insert only that row's text into the active app through
  the same Accessibility-gated active-app insertion boundary used by normal
  output delivery.
- The history window provides a Clear History action.
- Clearing history removes only current recovery history entries. It does not
  delete Keychain secrets, settings, raw audio cleanup state, or Last
  Transcript current-session state.
- Quitting the app clears current recovery history entries.
- Save Last Transcript saves the current Last Transcript to the VibeType
  Clipboard, not necessarily the newest recovery history row.

## Stored fields

Each recovery history entry should store only:

- stable local id
- creation date
- transcript text
- transcription model
- language setting used for the request
- optional audio duration, if already known from the completed session

History must not store raw audio, provider responses, authorization headers,
API keys, prompt text, custom dictionary entries, or debug payloads.

## Privacy and storage

- Recovery history is local-only and session-only for this MVP slice.
- Recovery history entries must not be persisted to UserDefaults, local JSON,
  SQLite, or another disk-backed store.
- No history entry may be sent to a server except when the user later uses a
  separate feature that explicitly sends text and has its own spec.
- Default logs must not include transcript text or history entry contents.
- Durable persistent transcript history requires a future spec update before
  implementation.

## Edge cases and failure policy

- Empty or whitespace-only transcriptions must not create history entries.
- Cancelled recordings must not create history entries.
- If a history append fails, the app should keep the current Last Transcript
  visible and continue output delivery where practical.
- If Accessibility permission is missing, history row insertion must not
  simulate text insertion and must not fall back to the macOS system clipboard.
- If the app terminates normally, recovery history is cleared during shutdown.

## Verification mapping

- Settings tests should prove recovery history is enabled by default,
  disabling it clears current entries, and the setting persists.
- History tests should cover append, max-20 retention, clear, disabled-no-write
  behavior, and exclusion of failed or empty transcripts.
- Controller tests should prove output failure does not erase accepted recovery
  history.
- Log review should confirm transcript history contents are not emitted in
  default logs.
