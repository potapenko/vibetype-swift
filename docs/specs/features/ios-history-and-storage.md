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
- In the completed History implementation, turning History off immediately
  clears accepted and failed entries plus failed-attempt retry audio. It does
  not clear the normal recording cache or an attempt that is currently in
  flight. The accepted-only foundation does not expose this UI action early.
- The canonical History enabled state and policy generation live in the
  dedicated strict app-private `HoldType/ios-history-policy.json` record. Clear,
  disable, and re-enable each advance its generation before cleanup so stale
  delivery markers or outbox entries cannot resurrect removed rows.
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
- Retry success replaces the failed row with an accepted row and creates the
  same protected pending delivery result as a new accepted attempt. With Keep
  Latest Result on, that result may remain as the new latest result after its
  delivery decision; with the preference off, it has no post-session latest
  retention. Retry does not automatically insert into an arbitrary host field.
- Retry failure preserves the row and audio when the failure remains
  recoverable, updates the compact reason and count, and leaves the last
  accepted result unchanged.
- Individual Delete removes only that history row. Deleting a failed row also
  removes its retry-only audio. Deleting an accepted row does not implicitly
  remove an independently retained recording-cache file.
- Clear History removes accepted rows, failed rows, and retry-only audio. It
  does not remove the API key, settings, usage estimates, or normal recording
  cache. This action becomes user-visible only after failed History and
  retry-audio cleanup join the same policy cutover.
- Turning history off performs the same immediate clear and prevents new
  accepted/failed history writes until the user enables it again. The toggle is
  not wired by the accepted-only foundation.
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

## Runtime Accepted-History Handoff

`AcceptedTranscriptHistoryRequest` is the transient P1 input to the current
accepted-History adapter. It contains exactly one already validated
`AcceptedTranscript`, one resolved non-empty transcription model, one optional
resolved language code, optional audio duration, one optional transient
app-local cached-audio URL, and the captured History-enabled preference.

The initializer resolves model and language from one
`TranscriptionConfiguration` and captures History/cache intent from one
`RetentionConfiguration`; it uses but does not retain either configuration.
Blank model fallback and fixed/custom language normalization remain unchanged.
The cached-audio URL is retained only when the captured recording-cache policy
keeps recordings. The History adapter performs a no-op when the captured
History preference is off. This Boolean is macOS/P1 compatibility intent only;
it is never authoritative iOS policy, generation, delivery-marker, or
persistence permission. Durable iOS acceptance obtains an opaque capture from
the accepted-History coordinator.

The request is `Equatable`, `Sendable`, and non-Codable. It has no raw-text
validation path, stable ID, date, output intent, stage, failure/retry data,
credential, provider payload, persistence, logging, App Group, or keyboard
semantics. Its absolute URL is compatibility-only runtime state and is not the
stable relative audio identity required by the iOS repository.

The macOS controller constructs the request only after final text has become an
`AcceptedTranscript`, using the same captured settings snapshot and audio
metadata already owned by that attempt. `TranscriptRecoveryHistoryRecording`
receives only this request; neither raw text nor full `AppSettings` crosses the
boundary. The current in-memory/session-only `TranscriptHistoryEntry`, its
legacy persistence shape, and all P2 versioned repository, migration, output-
intent, delivery-record, and atomic-journal contracts remain unchanged.

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

The pending journal stores only the attempt ID, relative audio
identifier, creation/update dates, processing phase, output intent, optional
current audio-transcription idempotency UUID, and compact configuration
identifiers needed to explain recovery, plus immutable duration and byte-count
consistency fields. They bound and cross-check the protected artifact but never
replace the mandatory media/container validation below. The UUID is committed
before provider dispatch and reused only as the identity of that same live
in-process handoff; re-entry does not authorize a second dispatch. Every
genuinely new provider request, including Retry, replaces it with a new UUID.
Provider retry resolves fresh settings and credentials.

The runtime-only `VoiceAttemptStage` is not the journal `processing phase` or
the failed row's durable `pipeline stage`. P2 defines versioned persistence
values and explicit mappings for those records; persistence never encodes a
debug description, enum ordinal, or inferred case order. Runtime stage alone
never makes a failure recoverable. Recovery also requires matching attempt
identity, a valid protected artifact, an eligible failure category, output
intent, and the applicable History or pending-owner policy. The P1 macOS
compatibility projection continues to create failed recovery only for
transcription attribution; it does not pre-decide iOS Translation recovery.

History and journal records never store API keys, authorization headers,
provider responses, prompts, dictionary contents, surrounding text, analytics,
or ordinary keystrokes.

### PendingRecording v1 Foundation

The first P2 storage checkpoint owns one app-private protected recording and
one strict journal. Its canonical locations under the containing app's
Application Support directory are:

- `HoldType/ios-pending-recording.json` for the journal;
- `HoldType/Recordings/Pending/` for protected audio;
- `Recordings/Pending/recording-v1-<lowercase canonical attempt UUID>.m4a` or
  `.wav` as the only durable relative audio identifier.

The filename UUID must equal the journal attempt ID. Absolute sandbox URLs are
runtime-only. These paths never enter App Group storage and are unrelated to
the provider multipart scratch namespace.

The public runtime record is `Equatable`, `Sendable`, and non-Codable. It has
exactly the attempt ID, relative audio identifier, creation and update dates,
durable phase, output intent, optional transcription ID, resolved non-empty
transcription model, optional resolved language code, integer duration in
milliseconds, and byte count. The strict JSON v1 object contains
exactly `schemaVersion`, `attemptID`, `audioRelativeIdentifier`, `createdAt`,
`updatedAt`, `phase`, `outputIntent`, `transcriptionID`,
`transcriptionModel`, `transcriptionLanguageCode`, `durationMilliseconds`, and
`byteCount`. Optional values are present as JSON `null`, UUIDs use lowercase
canonical spelling, and timestamps use canonical UTC milliseconds. The journal
is at most 64 KiB. Unknown, missing, duplicate, wrongly typed, non-canonical,
or unsupported-version data is an error and is preserved byte-for-byte. A
valid, corrupt, or future-version slot is never interpreted as empty. Valid v1
data can use the v1 recovery actions below. Corrupt and future-version bytes
remain blocked and preserved for later opaque recovery tooling; this checkpoint
does not claim that expected-attempt Discard can decode or remove them.

Durable phases have these exact versioned values and transitions:

- `readyForTranscription` is the initial committed state and requires a null
  transcription ID;
- `awaitingRecovery` requires a null transcription ID and an explicit user
  Retry or Discard before provider work;
- `transcribing` requires a committed transcription ID;
- `postProcessing` follows `transcribing` and preserves that ID;
- `outputDelivery` follows `postProcessing` and preserves that ID.

Normal Done prepares `readyForTranscription`. A valid partial retained after an
interruption, Quick Session expiry, or Stop Voice Session prepares directly as
`awaitingRecovery` and never starts provider work automatically. Explicit
processing cancellation or an eligible pre-delivery failure first retires the
dispatch authorization and cancels a registered provider task, then moves
`transcribing` or `postProcessing` to `awaitingRecovery`, clears the active
transcription ID durably, and only then completes cancellation. If the journal
mutation fails, the old authorization remains retired and cannot start or
restart provider work; the unresolved live owner continues to block Retry and
Discard until the local transition is reconciled. Explicit Retry
moves `awaitingRecovery` to `transcribing` with a fresh ID and current compact
configuration identifiers. Same-phase calls are idempotent only when all
identity-bearing inputs match. Other skips, backwards transitions, and a
phase/ID mismatch fail without rewriting the journal. The runtime-only
`VoiceAttemptStage` and its declaration order never define these values.

After process loss, a valid `transcribing`, `postProcessing`, or unresolved
`outputDelivery` record moves to `awaitingRecovery` only after the containing
app proves that no matching live owner and no canonical destination record
exists. That local transition clears the old transcription ID before Retry is
presented. It never resumes or repeats provider work automatically. A
`readyForTranscription` record also remains explicit after relaunch; its name
does not authorize automatic dispatch.

Every mutating callback must present the expected attempt ID, transcription ID
when one exists, and current phase. A cancelled, superseded, or late callback
cannot advance, discard, publish, or transfer a different durable owner.

The containing-app attempt owner allocates one local transcription UUID and the
store atomically commits it while moving `readyForTranscription` to
`transcribing`, then returns the validated audio handoff. Provider and transport
internals never generate this durable identity. Re-entering that same begun
handoff with the same proposed UUID may return the already-live handoff but
never authorizes a second network dispatch. After process loss, the old UUID
cannot dispatch again; the process-loss transition must first clear it and only
an explicit Retry may commit a fresh UUID for new provider work. An explicit
eligible Retry from `awaitingRecovery` allocates and commits that new UUID,
updates the compact model/language identifiers from current settings, preserves
the attempt ID, audio identity, creation date, duration, byte count, and output
intent, and returns only after the new `transcribing` record is durable. This
UUID is the local usage/replay identity, not an OpenAI idempotency header.

Only that successful commit may create one process-local, one-shot dispatch
authorization containing the validated runtime audio artifact. The
authorization never returns a detached provider-capable dispatch and never
passes it to an arbitrary closure with a generic result. Instead, one
concurrent caller may invoke the fixed containing-app transcription-executor
contract. The handoff supplies its internal recording and audio artifact to
that registered executor only inside the one cancellable task, and its public
result is transcript text rather than a provider capability. The task is held
behind a launch permit until cancellation is registered atomically.
Cancellation may retire an available or reserved authorization before launch,
in which case the executor is never invoked. If launch wins, cancellation sees
and cancels the registered task. A result or error is returned only when that
task still owns the authorization at completion; cancellation wins every late
completion race. Re-entry, operation failure, cancellation, and completion
never make the authorization reusable. `load`, observations, and a persisted
`transcribing` record never expose a provider-capable URL or reconstruct
dispatch authority. If the process loses the authorization, the attempt must
use process-loss recovery and explicit Retry with a fresh UUID.

Preparing a pending attempt follows this order:

1. reject a valid, corrupt, or future journal and perform a bounded read-only
   check that the dedicated audio namespace contains no staging, final, marked,
   malformed, or otherwise unresolved entry;
2. validate and copy one completed runtime artifact to an exclusive protected
   temporary file;
3. durably publish the protected audio without replacing an existing path;
4. atomically commit the initial journal;
5. return the runtime record; only then may the caller remove its source file.

The source must be an owned, no-follow, single-link regular `.m4a` or `.wav`
whose positive byte count exactly matches the runtime artifact and is strictly
less than 25,000,000 bytes. Duration is canonicalized to the nearest whole
millisecond using `toNearestOrAwayFromZero` and must fall in `1..<300000`.
Copying is streaming and bounded to
64-KiB chunks; recording audio is never loaded into one `Data` value. The copy
has one ten-second monotonic deadline, checks it before every syscall and EINTR
retry, and permits at most eight consecutive EINTR retries per operation. The
dedicated namespace is owned by the effective user, is not a symlink, and has
exact mode `0700`. The destination has exact mode `0600`, one
link, and the descriptor-bound xattr
`com.holdtype.ios.pending-recording-audio` with exact bytes `v1`. It receives
Complete Data Protection and backup exclusion on the descriptor before its
first byte, and both properties are read back exactly. The creator lock is held
through exclusive no-overwrite publication, audio and directory
synchronization, and journal commit. Descriptor and relative-path identity are
revalidated before and after every commit point. Journal replacement uses the
same descriptor-bound protection/backup verification, exact owner/mode/link
checks, no-follow path checks, and a required directory synchronization. A
rename is not a confirmed durable commit until every post-rename check and the
directory synchronization succeed. If any of them fails, the repository
reports a typed commit-uncertain local error, preserves the visible new journal
without rollback or cleanup, and never returns a revision or provider dispatch
authorization. The caller must inspect and reconcile the surviving journal;
it must not infer that either the old or new bytes are crash-durable and must
not automatically repeat provider work. Every same-phase idempotent call must
rewrite and synchronize those same bytes before it reports success or permits
downstream side effects, including when a different Store actor observed the
uncertain commit. A later durable transition may supersede the ambiguity only
after its own confirmed directory synchronization. The repository never edits
or removes the source artifact; any later source cleanup must revalidate the
originally captured identity and remains outside this checkpoint.

Journal duration and byte count are consistency fields, not proof that a media
container is playable. Before audio publication, the protected copy must pass
bounded media/container validation with a two-second deadline. Every provider
handoff repeats that bounded validation while the protected file is pinned and
then repeats descriptor/path identity checks. A malformed, unreadable, or
duration-inconsistent `.m4a`/`.wav` remains a typed local failure and never
authorizes provider work. The validated media duration must itself fall in
`1..<300000` milliseconds and differ from the journal value by no more than 250
milliseconds.

If protected-audio publication fails, only the owned temporary file may be
cleaned up. If journal commit fails after audio publication, the protected
audio is preserved, provider work is forbidden, and the failure remains a
local recovery condition. The checkpoint does not automatically upload,
repair, migrate, or delete orphaned audio at launch.

Only one containing-app repository actor may own this namespace in a process.
An unresolved valid journal blocks another attempt. Load and provider handoff
revalidate the exact relative identifier, regular-file identity, ownership,
single-link count, owner-only mode, byte count, protection, and backup policy.
A missing or invalid linked artifact is a typed local error; journal bytes and
remaining audio are preserved. Device-lock/Data-Protection unavailability is a
temporary typed condition, never proof that a file is absent or corrupt.

Explicit Discard requires the expected attempt ID and removes the protected
audio before the journal. A crash between those steps therefore leaves a
visible journal with missing audio instead of hidden retained audio. Repeating
Discard for that same journal is idempotent. Journal removal is permitted only
after audio removal or already-absent state is successfully verified. Any audio
validation/removal error preserves the journal and returns a typed local
failure. A missing journal never authorizes deletion of an orphan by filename
alone. Reconciliation, History transfer, recording-cache transfer, delivery
records, relaunch UI, and automatic source cleanup remain later checkpoints.

Future app-only reconciliation is non-recursive and recognizes only the exact
filename grammar plus descriptor-bound v1 marker. Its frozen per-pass caps are
256 inspected entries, 32 removals, 512 MiB of logical bytes, and one second of
monotonic elapsed time. It may age-remove only clearly incomplete marked
staging files; valid final audio without metadata requires an explicit
Keep/Export/Discard decision and is never silently age-deleted.

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
  a structured History-write object containing the normal `pending` state,
  captured policy generation, and the accepted row's model, language, and
  duration metadata. Only proof-bound atomic replacement may store-mint
  `pendingReplacement`, and only after the old pending payload is outbox-owned;
  that marker lets relaunch recovery replay the new delivery's idempotent row
  decision. Callers cannot mint it. A successful row decision retains the
  metadata and moves either unresolved state to `committed`; invalidated policy
  moves it to `cancelled`.
  Output continues with a visible non-blocking History error, and a later app
  lifecycle retries only that local row decision. Clear History or a later
  disabled policy generation must not resurrect an old row. Before
  delivery-record
  replacement, explicit clear, or Keep Latest cleanup could lose outstanding
  pending work, it moves to the bounded History outbox defined by
  `ios-accepted-history-foundation.md`; until that durable transfer exists,
  removal fails closed. An active, non-expired terminal History marker remains
  protected as well while an exact matching outbox membership exists, because
  it can be the only durable proof of a not-retained row decision. Terminal
  replacement or cleanup therefore requires FIFO retirement or the exact
  outbox absence capability bound to the paired stores' expected production
  root gate and its active lease; exact delivery expiry is the bounded
  abandonment exception, and uncertainty keeps the local result
  recoverable. With
  Recording Cache off, accepted text is sufficient
  recovery and the app then removes the journal/audio; with cache on, it
  transfers the file to the independent cache, links a successfully written
  accepted row by relative identifier when useful, applies retention, and then
  removes the journal.
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
- Orphaned app-owned audio discovered during reconciliation is attached to its
  valid pending journal when identity proves that ownership. A valid final
  recording without metadata is quarantined for explicit Keep/Export/Discard
  and is never age-deleted. Only exact incomplete marked staging files may be
  removed by bounded HoldType-only cleanup.
- If metadata persistence fails after recording completes, HoldType keeps the
  protected audio and shows a local storage failure instead of contacting the
  provider.
- If the device is low on space, new capture fails before pretending to record;
  existing history remains readable where possible.
- If Share or Save to Files fails, the original app-owned data remains intact.

## Route / state / data implications

- History and Storage & Recovery are app routes, not keyboard-extension UI.
- The app is the only writer of history, pending journals, and audio files.
- History enabled state and generation come only from the dedicated strict
  History policy record. Recording Cache policy is a separate deferred
  versioned contract.
- Relative identifiers are resolved through the current app container; durable
  records do not persist absolute sandbox URLs.
- The latest accepted result and short-lived keyboard insertion snapshot are
  separate from durable history.

## Verification mapping

- Test default-on history, max-20 accepted retention, max-five failed retention,
  ordering, deletion, Clear History, disable-immediate-clear, and re-enable.
- Test pending journal creation before provider dispatch, relaunch recovery,
  explicit retry, discard, corrupt metadata, and missing audio.
- Test the exact v1 paths and wire shape, 64-KiB journal bound, canonical
  UUID/date/relative identifiers, phase/ID invariants, legal transitions,
  same-handoff UUID reuse, and fresh UUID creation for explicit Retry.
- Test no-follow source validation, byte/duration/provider limits, 64-KiB
  streaming, partial/EINTR I/O, Complete protection before first write, backup
  exclusion, no-overwrite publication, source preservation, journal failure
  after audio publication, bounded media validation and duration consistency,
  orphan detection, process-loss recovery, and audio-first idempotent Discard.
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
