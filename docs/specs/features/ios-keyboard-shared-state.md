# iOS Keyboard Shared State

## Goal

Define the smallest privacy-preserving record shared by the iOS containing app
and keyboard extension.

## Ownership

The containing app is the single writer during the Phase 0 feasibility spike.
The keyboard extension is read-only and refreshes when it appears or its host
text context changes.

The App Group file is a snapshot, not an event bus and not a way to wake a
suspended app.

## Snapshot Contract

The JSON snapshot contains only:

- schema version;
- monotonically increasing revision;
- optional voice-session ID;
- phase: idle, listening, transcribing, transcript ready, or failed;
- optional source `documentIdentifier` for later insertion safety;
- update and expiry timestamps;
- optional accepted transcript ID, normalized text, and creation timestamp.

The current schema version is `1`.

Raw audio, API keys, prompts, ordinary keystrokes, surrounding field text,
host-app identity, provider responses, and analytics are forbidden.

## Validation

- Accepted transcript text is trimmed and must not be empty.
- A transcript is insertable only when the schema is supported, the record has
  not expired, the phase is `transcriptReady`, and accepted text is present.
- Corrupt or incompatible data produces an unavailable state, never insertion.
- Writes replace the complete file atomically.
- The containing app controls expiry; the Phase 0 sample expires after a short
  bounded interval.

## Future Session Contract

When device validation introduces extension writes, the schema must add an
idempotent request/acknowledgement contract before automatic insertion is
enabled. A session ID, transcript ID, revision, and source document ID together
prevent late or duplicate results.

That change requires an updated spec and a justified Full Access disclosure.
Without Full Access the extension remains read-only; with explicit Full Access,
only an already-active, bounded Quick Session may accept start/stop and
acknowledgement commands.

## Failure Behavior

- Missing App Group entitlement or container: setup unavailable.
- Missing file: no transcript available.
- Expired snapshot: no transcript available.
- Decode or schema failure: recoverable shared-state error without logging raw
  text.
- Write failure in the containing app: keep the prior successful snapshot and
  show a bounded error.

## Invariants

- The extension does not receive secrets or raw audio.
- The snapshot never contains surrounding host-field content.
- Default logs never include transcript text.
- Phase 0 does not require Full Access or extension writes.
- Shared state does not imply that the containing app is running.
