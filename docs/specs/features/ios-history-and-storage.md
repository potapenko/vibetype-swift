# iOS History And Storage

## Goal

Keep completed iOS dictations and recoverable provider failures available after
process eviction or relaunch without turning HoldType into a cloud archive.

Protect a completed recording before provider work begins, while keeping
accepted history, failed-attempt recovery, and the optional recording cache as
three explicit data lifecycles.

## Decision

- Accepted history is local, durable, enabled by default, and capped at the 20
  newest entries.
- Failed history is local, durable, and capped at the five newest recoverable
  attempts.
- Turning history off immediately clears accepted and failed entries plus
  failed-attempt retry audio. It does not clear the normal recording cache or an
  attempt that is currently in flight.
- Every completed recording gets a minimal atomic `PendingRecording` journal
  before the first provider request, regardless of the history setting.
- Recording cache remains off by default. When enabled it defaults to keeping
  the last 10 recordings; unlimited retention requires an explicit choice.
- No history, recordings, or settings sync through iCloud or another service.

## Scope

- accepted transcript history
- recoverable failed attempts and retry audio
- pending-recording crash recovery
- recording cache retention and local playback
- Copy, Share, Save to Files, Delete, Clear, and Retry actions
- protected local storage, backup exclusion, and reconciliation

## Non-goals

- cloud sync, accounts, shared history, or collaboration
- semantic search, tags, folders, notes, or transcript editing
- hidden or unlimited raw-audio retention by default
- automatic provider retry after relaunch
- storing provider payloads, prompts, API keys, or surrounding host-field text

## User-visible behavior

- History is a first-class app destination and lists entries newest-first.
- Before the first retained attempt, HoldType explains that History is on and
  stored on this device, keeps at most 20 accepted and five failed entries, and
  can be disabled or cleared from Settings. Showing this disclosure does not
  start recording or provider work.
- Accepted rows show accepted text, time, dictation language, model, and known
  duration. They may offer Copy, Share, Delete, and Play.
- Copy writes only the selected accepted text to the system clipboard after the
  user taps Copy. It does not modify the keyboard bridge or trigger insertion.
- Share uses the system share sheet. HoldType does not choose a recipient or
  upload a transcript automatically.
- Play is available only while the linked app-owned recording still exists.
  Playback is local and never retranscribes or changes accepted text.
- Failed rows show `Not transcribed`, a compact reason, time, retry count, and
  known model/language/duration metadata. They may offer Retry and the relevant
  Settings destination.
- Retry is always explicit and uses the current API key and safe current
  transcription configuration. It never reuses a stored key, prompt, provider
  payload, or nearby text context.
- Retry preserves the failed row's output intent. A failed Translation attempt
  retries as Translation with the current valid translation configuration; it
  never accepts or publishes the intermediate transcription as a successful
  translated result. If current configuration cannot run that intent, Retry
  routes to its owning Settings section.
- Retry success replaces the failed row with an accepted row and publishes a
  new latest result. It does not automatically insert into an arbitrary host
  field.
- Retry failure preserves the row and audio when the failure remains
  recoverable, updates the compact reason and count, and leaves the last
  accepted result unchanged.
- Individual Delete removes only that history row. Deleting a failed row also
  removes its retry-only audio. Deleting an accepted row does not implicitly
  remove an independently retained recording-cache file.
- Clear History removes accepted rows, failed rows, and retry-only audio. It
  does not remove the API key, settings, usage estimates, or normal recording
  cache.
- Turning history off performs the same immediate clear and prevents new
  accepted/failed history writes until the user enables it again.
- After relaunch, an unresolved `PendingRecording` journal produces one clear
  recovery surface. The user may Retry, keep/export the audio when allowed, or
  discard that attempt.
- Relaunch recovery never uploads automatically and never silently accepts or
  inserts text.
- Recording Cache shows its item count and size, supports local playback and
  Share/Save to Files, and provides per-item Delete and Clear Cache.
- Choosing unlimited recording retention shows that storage can grow until the
  user clears it or changes the policy.

## Voice-Session Concurrency

- History `Play` and `Retry` are disabled while the canonical voice controller
  is `arming`, `ready`, `listening`, `finalizing`, or `processing`, or while an
  unresolved pending attempt already owns the provider chain. The row explains
  that the current voice work must finish, be cancelled, or be discarded first.
- When otherwise idle, History playback temporarily owns the app audio session.
  An explicit new Voice start stops playback and deactivates its playback
  session before recording preflight begins; it never mixes playback into a
  capture.
- Only one History playback and one provider retry may run at a time. Starting a
  second is unavailable until the first reaches a terminal state.
- Delete/Clear for the currently playing or retrying item is disabled until that
  operation stops. Copy and non-audio Share of unrelated accepted text remain
  available and do not mutate the active voice chain.

## Stored fields

An accepted entry may store:

- stable local ID and creation date
- final accepted text
- transcription model and language code
- optional duration
- optional relative identifier for a separately retained cache recording
- output intent used to produce the accepted result

A failed entry may store:

- stable local ID and creation date
- compact failure category and retry count
- model and language metadata
- output intent and the failed pipeline stage
- optional duration
- relative identifier for protected retry-only audio

The pending journal stores only the attempt/session ID, relative audio
identifier, creation/update dates, processing phase, output intent, optional
current audio-transcription idempotency UUID, and compact configuration
identifiers needed to explain recovery. The UUID is committed before provider
dispatch and reused only when replaying that same request/handoff; every
genuinely new provider request, including Retry, replaces it with a new UUID.
Provider retry resolves fresh settings and credentials.

History and journal records never store API keys, authorization headers,
provider responses, prompts, dictionary contents, surrounding text, analytics,
or ordinary keystrokes.

Usage bookkeeping is independent of History ownership. Once a non-empty audio
transcription response is accepted, its idempotent local usage handoff remains
valid even if later translation, accepted-History append, or output delivery
fails. Clearing History never clears usage, and a History write failure never
repeats provider work or creates a second usage event.

## Journal And Audio Ownership Transitions

Every transition is a staged, idempotent handoff, not a claim that file and
metadata operations are one filesystem transaction. Pending audio remains at a
stable attempt-scoped relative path until its destination is durable. The
destination record and relative identifier commit before the prior journal or
source file is removed. A crash between steps is reconciled from stable attempt
identity without deleting the only valid artifact.

- On success, HoldType first commits the mandatory protected accepted-output
  delivery record. When History is on, it then attempts the accepted History
  row before publishing output. If that append fails, the delivery record keeps
  a bounded `historyWritePending` marker, output continues with a visible
  non-blocking History error, and a later app lifecycle retries only that local
  append. With Recording Cache off, accepted text is sufficient recovery and
  the app then removes the journal/audio; with cache on, it transfers the file
  to the independent cache, links a successfully written accepted row by
  relative identifier when useful, applies retention, and then removes the
  journal.
- A cache transfer uses `copy to cache temporary path -> atomic cache rename ->
  cache metadata commit -> pending source/journal delete`. The journal remains
  until the copy/rename and destination metadata commit, so restart can finish
  cleanup without recreating or losing audio.
- On a recoverable failure with History on, HoldType creates or updates one
  failed row, transfers ownership of the relative audio identifier to that
  row's retry-only audio at the same stable path, and then removes the journal.
  If both records survive a crash, the committed failed row is canonical and
  reconciliation removes only the redundant journal metadata.
- On a recoverable failure with History off, the journal and protected audio
  remain as the one pending recovery attempt until explicit Retry or Discard.
  They do not become hidden durable History and block a second unresolved
  attempt.
- `Cancel Processing` cancels the network task and preserves the journal/audio
  in that same explicit Retry-or-Discard recovery state. A late response cannot
  consume or replace it.
- An explicit Discard removes the pending journal and its retry-only audio.
  It does not remove an independently completed cache item or user-exported
  file.
- A terminal non-retryable provider or validation failure keeps the visible
  outcome until acknowledged, then removes the journal and audio when cache is
  off. When cache is on, a valid completed recording may transfer to cache
  before journal removal; an invalid audio artifact is never cached.
- Maximum-duration, empty, too-short, corrupt, and cancelled-capture artifacts
  fail before provider dispatch. They do not create accepted/failed History;
  any incomplete artifact and journal created during finalization are removed.

## Invariants

- A completed recording is journaled before the first provider request.
- Accepted text is committed to app-private recovery before output handoff can
  fail.
- History append failure cannot lose or block a result whose mandatory delivery
  record committed, and cannot trigger duplicate provider work.
- Accepted history, failed history, pending recovery, and recording cache have
  separate deletion and retention rules.
- App Group storage never contains history metadata or raw audio.
- Local files use iOS Data Protection and are excluded from device backup.
- Default logs never include transcript text, file paths, or audio contents.
- Process eviction or force quit must not turn a completed journaled recording
  into an invisible orphan.
- Cancelled capture and pre-capture setup failures do not create history rows.
- Retention pruning removes only HoldType-owned records and files selected by
  the applicable policy.

## Edge cases and failure policy

- Corrupt history metadata produces a local recovery error and must not be
  treated as an empty successful history load.
- A missing linked audio file removes Play/Retry availability and leaves enough
  metadata to explain that the recording is unavailable.
- Orphaned app-owned audio discovered during reconciliation is either attached
  to its valid pending journal or removed by a bounded HoldType-only cleanup.
- If metadata persistence fails after recording completes, HoldType keeps the
  protected audio and shows a local storage failure instead of contacting the
  provider.
- If the device is low on space, new capture fails before pretending to record;
  existing history remains readable where possible.
- If Share or Save to Files fails, the original app-owned data remains intact.

## Route / state / data implications

- History and Storage & Recovery are app routes, not keyboard-extension UI.
- The app is the only writer of history, pending journals, and audio files.
- History enabled state and recording retention policy are versioned settings.
- Relative identifiers are resolved through the current app container; durable
  records do not persist absolute sandbox URLs.
- The latest accepted result and short-lived keyboard insertion snapshot are
  separate from durable history.

## Verification mapping

- Test default-on history, max-20 accepted retention, max-five failed retention,
  ordering, deletion, Clear History, disable-immediate-clear, and re-enable.
- Test pending journal creation before provider dispatch, relaunch recovery,
  explicit retry, discard, corrupt metadata, and missing audio.
- Test every journal ownership transition, including crashes between
  destination commit and journal removal, Translation intent preservation,
  History on/off, processing cancellation, and cache on/off.
- Test cache-off cleanup, keep-last-10 pruning, unlimited retention, size/count,
  playback availability, Share/Save failure, and cache clear isolation.
- Test Play/Retry gating in every voice phase, playback-to-recording handoff,
  single retry ownership, and destructive-action gating for an active item.
- Test relative identifier resolution, file protection configuration, backup
  exclusion, and HoldType-only reconciliation.
- Test that logs, bridge files, and exports omit forbidden data.

## Unknowns requiring confirmation

- None for the first iOS implementation. Search, editing, cloud sync, and larger
  retention policies require later product contracts.
