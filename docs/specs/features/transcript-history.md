# Transcript History

## Goal

Define whether VibeType keeps a persistent local transcript history beyond the
current session's last transcript.

## Decision

Transcript history is in the MVP as an opt-in local-only feature. It is disabled
by default.

The always-visible Last Transcript surface remains current-session state. It
does not require persistent history to be enabled.

## Scope

This spec covers:

- persistent storage of accepted transcript text
- default history setting
- retention limit and clear behavior
- history fields
- privacy and logging boundaries
- relationship to Last Transcript and copy actions

## Non-goals

- raw audio retention
- cloud sync, accounts, sharing, or telemetry
- full search, semantic notes, tags, folders, or review workflows
- SQLite or another database requirement for the MVP
- storing failed, empty, cancelled, or partial transcription attempts

## User-visible behavior

- Transcript history is off by default.
- Settings should expose a Save Transcript History toggle before persistent
  history writes are possible.
- When history is off, successful transcripts may still appear as the current
  Last Transcript, but they must not be written to persistent history.
- When history is on, each accepted non-empty transcript is added to local
  history after transcription succeeds.
- A failed paste or copy handoff must not discard the current Last Transcript.
  If history is enabled, the accepted transcript may still be saved because the
  transcription itself succeeded.
- History keeps at most the 20 most recent accepted transcripts. Older entries
  are removed automatically when the limit is exceeded.
- Settings should provide a Clear Transcript History action once persistent
  history exists.
- Turning history off stops future history writes. Existing saved entries remain
  until the user clears history, and the UI must make that behavior clear.
- Copy Last Transcript copies the current Last Transcript, not necessarily the
  newest persistent history row.
- Future history-row copy actions should copy only the selected row's text.

## Stored fields

Each persistent history entry should store only:

- stable local id
- creation date
- transcript text
- transcription model
- language setting used for the request
- optional audio duration, if already known from the completed session

History must not store raw audio, provider responses, authorization headers,
API keys, prompt text, or debug payloads.

## Privacy and storage

- History is local-only for the MVP.
- No history entry may be sent to a server except when the user later uses a
  separate feature that explicitly sends text and has its own spec.
- Default logs must not include transcript text or history entry contents.
- UserDefaults or a small local JSON file is acceptable for the MVP. SQLite is
  not required unless a future spec adds search or larger retention needs.

## Edge cases and failure policy

- Empty or whitespace-only transcriptions must not create history entries.
- Cancelled recordings must not create history entries.
- If history storage fails, the app should keep the current Last Transcript
  visible and show a recoverable local-storage error.
- Clearing history removes only persistent history entries. It does not delete
  Keychain secrets, settings, or raw audio cleanup state.

## Verification mapping

- Future settings tests should prove history is disabled by default.
- Future history-store tests should cover append, max-20 retention, clear,
  disabled-no-write behavior, and exclusion of failed or empty transcripts.
- Future log review should confirm transcript history contents are not emitted
  in default logs.
