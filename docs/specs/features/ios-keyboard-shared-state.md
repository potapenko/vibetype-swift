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

Static keyboard preferences use the separate app-owned record governed by
`ios-keyboard-settings-snapshot.md`. They never share a read-modify-write file
with voice delivery state.

## Snapshot Contract

The JSON snapshot contains only:

- schema version;
- monotonically increasing revision;
- optional voice-session ID;
- phase: idle, listening, transcribing, transcript ready, or failed;
- optional source `documentIdentifier` for later insertion safety;
- update and expiry timestamps;
- optional accepted transcript ID, normalized text, and creation timestamp.
- optional `automaticInsertionAuthorized`, which defaults false and is true
  only for a result produced under the current canonical preference after its
  settings-publication gate has passed.

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

When M0C introduces extension writes, production shared state splits into
directionally owned records:

- app-owned `VoiceSessionSnapshot` with compact phase and accepted result;
- extension-owned command envelopes for an already active Quick Session;
- extension-owned insertion acknowledgements;
- extension-owned `KeyboardReadinessHeartbeat` written only while the
  extension has Full Access.

No process performs a shared read-modify-write cycle across writer domains.
Every writer serializes its own strictly increasing revision. A session ID,
transcript ID, revision, and source document ID together prevent late or
duplicate results.

Production command envelopes expire no later than the active Quick Session
deadline. An accepted-result snapshot expires 10 minutes after it becomes
ready. Expiry disables automatic delivery; longer-lived recovery remains in the
containing app.

A `startListening` command identifies the active Quick Session, its own command
ID/revision, creation/expiry timestamps, the requested output intent, and the
optional non-empty `sourceDocumentIdentifier` observed by the extension at the
explicit mic tap. The containing app validates the session before recording and
copies that exact identifier into the matching app-owned result snapshot. The
other named command kinds are `finishUtterance`, `cancelUtterance`,
`stopVoiceSession`, and `cancelProcessing`; each identifies the matching
session/attempt and is accepted only in the phase defined by
`ios-voice-session-and-audio.md`. No command adds host/field content or carries
transcript text.

The first `KeyboardReadinessHeartbeat` contains only:

- schema version and writer-domain monotonic revision;
- `generatedAt` and `expiresAt` timestamps;
- `keyboardPresented: true`;
- `hasFullAccess: true`.

Its first production TTL is five minutes. The extension replaces it atomically
when it is presented or its text-input context changes while live
`hasFullAccess` is true. It contains no transcript, command, host, field,
keystroke, locale, or user-content data. Because revoking Full Access can also
remove the extension's ability to update the App Group, absence or expiry means
only `not currently verified`; it never proves `disabled`. The containing app
may report `recently verified enabled` only while a supported heartbeat is
fresh.

Each writer physically removes or replaces only its own expired envelopes at
its next available lifecycle opportunity. The containing app clears accepted
text after successful acknowledgement, explicit delivery cancellation, session
replacement, or its first maintenance pass after expiry, and removes its own
temporary atomic-write files. The extension similarly cleans its commands,
acknowledgements, heartbeat, and temporary files when it next runs with the
required access. A reader never deletes another writer's mutable pathname after
a stale read. All transient App Group records use complete file protection and
are excluded from device backup after every atomic creation or replacement.
The Phase-0 probe's until-first-authentication file policy is not a production
contract and must be replaced before P6 bridge hardening.

TTL validation is unconditional even when neither process is running: an
expired record is never eligible for display, command handling, or insertion.
iOS cannot guarantee immediate physical deletion while the owning process is
not scheduled, so a protected excluded-from-backup file may remain until that
writer's next lifecycle opportunity.

That change requires an updated spec and a justified Full Access disclosure.
Without Full Access the extension remains read-only; with explicit Full Access,
only an already-active, bounded Quick Session may accept the phase-valid named
voice actions and acknowledgement commands. The heartbeat is readiness
evidence, not a command channel and not proof that the extension is still
running.

Automatic insertion also follows `ios-output-actions.md`; document identity is
a conservative guard, not proof of a host app or cursor.

## Failure Behavior

- Missing App Group entitlement or container: setup unavailable.
- Missing file: no transcript available.
- Expired snapshot: no transcript available.
- Expired heartbeat: readiness is `not currently verified`; ordinary typing
  and app-owned settings remain unchanged.
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
- Logical expiry always blocks use. Physical cleanup is owner-only and runs at
  the writer's next lifecycle opportunity; no contract claims iOS can schedule
  immediate deletion while that process is absent.
