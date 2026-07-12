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
- In the completed History implementation, turning History off first durably
  commits a new disabled policy generation. Accepted and failed entries then
  disappear from History immediately and cannot be restored; app-private
  physical cleanup of their metadata and failed-attempt retry audio may finish
  during bounded lifecycle reconciliation. It does not clear the normal
  recording cache or an attempt that is currently in flight. The accepted-only
  foundation does not expose this UI action early.
- The canonical History enabled state and policy generation live in the
  dedicated strict app-private `HoldType/ios-history-policy.json` record. Clear,
  disable, and re-enable each advance its generation before cleanup so stale
  delivery markers or outbox entries cannot resurrect removed rows.
- Every completed recording gets a minimal atomic `PendingRecording` journal
  before the first provider request, regardless of the history setting.
- Recording cache remains off by default. When enabled it defaults to keeping
  the last 10 recordings; unlimited retention requires an explicit choice.
- No history, recordings, or settings sync through iCloud or another service.

### P4 App-Only Pending Ownership

- P4 uses the existing protected `PendingRecording` contract without enabling
  the P5 History product. It does not create or mutate History policy, accepted
  rows, failed rows, outbox entries, retry-audio ownership, recording-cache
  metadata, or first-use History disclosure state. The History destination
  remains unavailable for P4 attempts.
- Failed-History Retry remains unavailable throughout P4 unless its provider
  adapter has adopted both the neutral bounded-reader request and the current
  provider-consent dispatch/result gate. The existence of an internal legacy
  Retry implementation does not make that action eligible for presentation.
- P4 app-only acceptance is a named Persistence-owned mode, not a caller-supplied
  optional History bypass. It creates the mandatory accepted-output record with
  `historyWrite: null` without reading, disabling, or otherwise changing the
  canonical History policy. P5 does not retroactively backfill these results.
- Normal completion follows this order: protected audio and initial journal
  commit; fresh transcription ID commit; one-shot provider execution;
  `postProcessing`; exact `outputDelivery` transition; mandatory accepted-output
  commit with `historyWrite: null`; exact destination verification; protected
  audio removal with canonical absence evidence; then journal retirement with
  separate canonical absence evidence. `resultReady` is unavailable until both
  evidence values are confirmed.
- In P4, accepted text is the durable destination because History and Recording
  Cache integration are absent. Audio is removed before journal retirement.
  Failure or uncertainty preserves the journal and blocks Clear or replacement
  from deleting the only accepted-destination proof.
- A recoverable provider, timeout, cancellation, or eligible pre-delivery
  failure first retires or cancels dispatch authority, then durably moves the
  exact attempt to `awaitingRecovery` with a null transcription ID. Only after
  that commit may Voice offer Retry or Discard.
- Any unresolved app-only acceptance checkpoint—delivery commit or replacement,
  destination confirmation, Pending-audio removal, or journal retirement—keeps
  the exact owner in `outputDelivery` and offers idempotent `Retry Saving Result`
  from the last confirmed checkpoint with the same accepted bytes and
  identities. A named P4 recovery operation may move `outputDelivery` to
  `awaitingRecovery` in the current process only after the canonical delivery
  store proves that the intended destination and every related reservation are
  absent and no commit uncertainty remains. It retires the accepted-delivery
  intent, clears the transcription ID durably, and never repeats provider work
  automatically. A matching destination, later retirement failure, or ambiguous
  store keeps `Saving Result` blocked on local completion instead.
- Retry is explicit. It preserves attempt ID, protected audio, creation time,
  duration, byte count, and output intent; resolves current Settings, Library,
  consent, and credential again; commits a fresh transcription ID; and creates
  one new one-shot provider authorization. Relaunch never uploads automatically.
- Discard requires the current attempt and phase expectation, removes protected
  audio before the journal, and reports success only after root-bound,
  directory-durable absence of both is proved.
  Failure preserves the journal and recovery surface. It never deletes an
  unrelated accepted result.
- One unresolved Pending attempt blocks another recording or provider chain
  until it succeeds, is explicitly discarded, or is safely reconciled.

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
- Clear History first commits a new policy generation while preserving whether
  History is enabled. Older accepted and failed rows immediately disappear and
  cannot be retried or restored; their metadata and retry-only audio are then
  removed by bounded lifecycle reconciliation. It does not remove the API key,
  settings, usage estimates, or normal recording cache. This action becomes
  user-visible only after failed History and retry-audio cleanup join the same
  policy cutover.
- Turning History off commits a new disabled generation, produces the same
  immediate logical clear, and prevents new accepted/failed History writes
  until the user enables it again. Re-enabling starts another generation and
  never restores old rows. The toggle is not wired by the accepted-only
  foundation.
- Clear or a state-changing toggle is successful only after its intended policy
  value is durably confirmed. Until then, History shows a local unavailable
  state rather than old rows or an optimistic empty result. A later physical
  cleanup failure does not roll policy back: History stays empty or filtered to
  the confirmed generation, and Storage & Recovery may show a redacted,
  non-blocking cleanup-pending status while lifecycle reconciliation retries.
  Retrying cleanup never creates another policy generation.
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

Every accepted and failed row belongs to the exact enabled policy generation
captured and revalidated for its durable write. Reads expose only that
generation while History is enabled and expose no rows while it is disabled.
The exact failed-row, retry-only audio, tombstone, and policy-cutover contract
lives in `ios-failed-history-and-retry-audio.md`. It binds audio to durable row
ownership so cleanup never guesses a filename or deletes an in-flight pending
attempt. A disabled policy never creates a failed row; an eligible recoverable
failure remains under the explicit pending-recording recovery contract instead.

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
the failed row's durable `pipeline stage`. The failed-History spec defines the
versioned persistence values and explicit mappings; persistence never encodes a
debug description, enum ordinal, or inferred case order. Runtime stage alone
never makes a failure recoverable. Recovery also requires matching attempt
identity, a valid protected artifact, an eligible failure category, output
intent, and the applicable History or pending-owner policy. The P1 macOS
compatibility projection continues to create failed recovery only for
transcription attribution; it does not pre-decide iOS Translation recovery.

The containing-app failed-History boundary returns either the at-most-five
current rows or a redacted local-recovery-pending state. Row IDs are opaque and
non-Codable. The UI receives only compact category/stage, retry count, intent,
model, language, dates, duration, and coarse audio availability; it never
receives an audio path, stored byte count, policy generation, retry operation,
receipt, or mutation capability. Delete is a payload-free complete-or-pending
command. Retry is owned by a process-scoped service that resolves current
settings, Library content, and credentials afresh before durable reservation.
The read model never authorizes either command and never treats uncertain or
unavailable storage as an empty History.

After Clear or a policy toggle has crossed its durable logical boundary, a
matching retained cutover may expose an empty failed-History list while
old-generation physical cleanup remains pending. This exception requires a
valid failed journal, no unresolved row ownership, no current-generation row,
and agreement between the retained cutover receipt's owner/logical state and
the freshly confirmed current policy.
It does not make any old audio available and does not apply to pre-boundary,
corrupt, future, conflicted, or ambiguous state.

One process-owned lifecycle scheduler performs a launch-only strict standalone
failed-Retry cold scan when no History-policy cutover is retained. A retained
cutover bypasses that standalone preflight so its own cleanup owner can resume.
Before either ordinary or retained generic History cleanup may expire accepted
output, launch checks for an exact non-discarded ordinary destination of a
process-lost `PendingRecording.outputDelivery` and retires only that exact
Pending audio and journal. Canonical provider-free History cleanup then owns or
resumes any retained cutover and performs its embedded strict cold Retry scan
before later History recovery. A launch opportunity may finally convert one
remaining process-lost PendingRecording provider phase to explicit recovery; a
normal foreground opportunity may not. No lifecycle pass automatically invokes
Retry, drains multiple cleanup heads, reads Keychain, requests permission, or
contacts a provider.

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
trimmed transcription model of at most 256 bytes in UTF-8 using the accepted
output metadata character contract, optional resolved language code, integer
duration in milliseconds, and byte count. The strict JSON v1 object contains
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
Discard until the local transition is reconciled. Explicit Retry moves either
`readyForTranscription` or `awaitingRecovery`, each with a null transcription
ID, to `transcribing` with a fresh ID and current compact configuration
identifiers. Same-phase calls are idempotent only when all identity-bearing
inputs match. P4 has one additional store-authorized current-
process transition from `outputDelivery` to `awaitingRecovery`: the app-only
delivery coordinator must first retire the exact accepted-delivery intent and
prove through the canonical delivery store that no matching destination,
reservation, commit uncertainty, or live output mutation remains. It then
clears the transcription ID durably and returns the exact updated Pending owner.
No caller assertion or generic phase API may request this exception. Other
skips, backwards transitions, and a phase/ID mismatch fail without rewriting
the journal. The runtime-only
`VoiceAttemptStage` and its declaration order never define these values.

After process loss, a valid `transcribing`, `postProcessing`, or unresolved
`outputDelivery` record moves to `awaitingRecovery` only after the containing
app proves that no matching live owner exists and proves directory-durable
absence of the canonical destination record under the expected physical root.
An ordinary missing-path lookup is insufficient. That local transition clears
the old transcription ID before Retry is
presented. It never resumes or repeats provider work automatically. A
`readyForTranscription` record also remains explicit after relaunch; its name
does not authorize automatic dispatch. Passive process-launch or foreground
reconciliation leaves that record unchanged and does not load Settings or
Library, inspect consent, resolve a credential, request microphone permission,
or create provider authority. Its user-visible actions are the same explicit
Retry or confirmed Discard offered for `awaitingRecovery`.

After the strict failed-Retry cold scan proves no work and before generic
accepted-output expiry or policy cleanup, the process-launch lifecycle path
completes an `outputDelivery` Pending record when the app-private accepted-
output journal already contains its exact ordinary destination. Exact means the
same attempt ID, a transcript
ID equal to the Pending transcription ID, no failed-Retry provenance, the same
output intent, and matching model/language/duration metadata whenever a History
write is present. Under the shared physical-root operation gate, completion
removes the exact Pending audio if present, confirms the same destination
again, and then retires the exact Pending journal. Launch uses the same
evidence-producing retirement path as live completion and confirms separate
directory-durable absence of audio and journal before clearing ownership or
publishing ready state. Removal is idempotent so a crash after audio removal but
before journal retirement resumes safely. A
partial identity match, failed-Retry delivery, metadata mismatch, corrupt or
unavailable destination, invalid audio identity, or canonical destination for
`transcribing` or `postProcessing` fails closed and preserves the journal. This
completion never republishes accepted text or repeats provider work.

Process-loss audio retirement pins the exact physical source identity before
unlink. If unlink may have succeeded but directory synchronization is
uncertain, retry reconciles only absence or that pinned original identity. It
never opens or deletes a new file created at the same relative pathname, even
when filename, marker, format, and byte count match. Identity mismatch preserves
the new object and keeps local recovery pending.

Every mutating callback must present the expected attempt ID, transcription ID
when one exists, and current phase. A cancelled, superseded, or late callback
cannot advance, discard, publish, or transfer a different durable owner.

The containing-app attempt owner allocates one local transcription UUID and the
store atomically commits it while moving `readyForTranscription` to
`transcribing`, then returns the validated audio handoff. This same-process
initial path uses the exact frozen Settings snapshot that created the Pending
record and fails before mutation if compact model/language no longer match.
Provider and transport internals never generate this durable identity.
Re-entering that same begun handoff with the same proposed UUID may return the
already-live handoff but never authorizes a second network dispatch. After
process loss, the old UUID cannot dispatch again; the process-loss transition
must first clear it and only an explicit Retry may commit a fresh UUID for new
provider work.

An explicit eligible Retry accepts either `readyForTranscription` with a null
transcription ID or `awaitingRecovery` with a null transcription ID. It
allocates and atomically commits a fresh UUID, updates compact model/language
identifiers from the current Settings snapshot, preserves attempt ID, audio
identity, creation date, duration, byte count, and output intent, and returns
only after the new `transcribing` record is durable. Invalid current
configuration, stale CAS, unavailable consent or credential, or cancelled
preflight leaves the Pending journal phase unchanged and creates no handoff. This UUID
is the local usage/replay identity, not an OpenAI idempotency header.

Only that successful commit may create one process-local, one-shot dispatch
authorization containing a validated descriptor-backed audio source. The
authorization never returns a detached provider-capable dispatch and never
passes it to an arbitrary closure with a generic result. Instead, one
concurrent caller may invoke the fixed containing-app transcription-executor
contract. The handoff supplies its internal recording and a bounded audio
reader to that registered executor only inside the one cancellable task, and
its public result is transcript text rather than a provider capability. The
reader exposes format, duration, byte count, and offset-based reads of at most
64 KiB; it exposes no URL, path, `FileHandle`, or raw descriptor and reads the
already pinned file with `pread`. The containing-app provider adapter must
consume that reader directly and must not convert it back into a path-based
artifact. The task is held behind a launch permit until cancellation is
registered atomically.
Cancellation may retire an available or reserved authorization before launch,
in which case the executor is never invoked. If launch wins, cancellation sees
and cancels the registered task. A result or error is returned only when that
task still owns the authorization at completion; cancellation wins every late
completion race. Success, failure, cancellation, retirement, handoff release,
and process-local recovery invalidate the reader and close its lease after any
already-running bounded read returns. An executor-retained reader then fails
closed and cannot start new reads. Re-entry never makes the authorization
reusable. `load`, observations, and a persisted `transcribing` record never
expose a provider-capable URL or reconstruct dispatch authority. If the process
loses the authorization, the attempt must use process-loss recovery and
explicit Retry with a fresh UUID.

The same process-owned Pending transaction owner that commits the transcription
ID must remain the owner for the corresponding same-process
`markPostProcessing`, `markOutputDelivery`, cancellation-to-`awaitingRecovery`,
and app-only acceptance handoffs. A scene or provider adapter cannot substitute
another Pending store or reconstruct that live transition authority. Process
loss ends this lifetime and uses the existing recovery-plus-fresh-Retry contract
instead.

Persistence supplies that lifetime to the containing app as one narrow,
process-owned foreground transaction facade created from the canonical physical-
root context. The facade returns the exact committed `transcribing` owner with
its one-shot handoff and owns every later Pending and app-only acceptance
transition. It does not expose a replaceable Pending store or allow independently
constructed path-based components to be combined into a live attempt.

If a facade mutation throws after bytes may have become visible, reconciliation
loads only the same attempt and transcription identity. A visible
`postProcessing`, `outputDelivery`, or `awaitingRecovery` destination is adopted
only after the corresponding idempotent same-phase operation confirms directory
durability. Any absent, mismatched, or unconfirmed observation preserves the
provider-free local checkpoint. App-only acceptance reconciliation additionally
requires Persistence-owned equality of accepted bytes, output intent, app-only
mode, and immutable identities; a one-way `keepLatestResult` revocation from on
to off remains valid and is never reversed by replay.

### P4D Foreground Capture-Source Ownership

P4D does not pass an ordinary recorder URL into the path-based Pending prepare
API. Persistence owns one app-private foreground capture-source namespace at
`HoldType/Recordings/Capture`. The namespace is owner-only, no-follow, mode
`0700`, Complete-protected, excluded from backup, and marked with
`com.holdtype.ios.capture-source-namespace` exact ASCII bytes `v1`. The
containing app may receive one transient source URL only through an opaque
Persistence-issued recording lease for `AVAudioRecorder`; no provider, scene
state, log, App Group, or keyboard surface receives it.

#### Capture creation and wire format

One production source uses
`capture-v1-<attempt UUID>.m4a`; the UUID is lowercase canonical spelling and
equals the durable attempt ID. Test fixtures may use the corresponding `.wav`
grammar. Production capture is mono MPEG-4 AAC at 44.1 kHz with high encoder
quality.

Persistence holds the namespace creator lock and writes
`com.holdtype.ios.capture-source-creation-intent` on the pinned directory
before creating any file. Its exact 27-byte value is schema byte `1`, attempt
UUID, output-intent byte, format byte, and UInt64 UTC creation milliseconds.
The directory is synchronized before file creation. Persistence then:

1. exclusively creates
   `.capture-source-creating-v1-<attempt UUID>.<m4a|wav>`;
2. pins the regular file and verifies effective owner, mode `0600`, one link,
   stable device/inode/generation, Complete protection, and backup exclusion;
3. writes the source marker, identity manifest, and `active-v1` phase, then
   synchronizes the descriptor;
4. publishes the final source name with a no-overwrite rename, synchronizes the
   directory, and revalidates descriptor/path identity; and
5. removes the matching creation intent, synchronizes the directory, and only
   then exposes the final recording URL.

A crash before URL exposure is bounded by that intent. Launch may clear an
exact intent with directory-durable absence of both names, remove its exact
hidden creation file regardless of partial marker setup, or clear the intent
while retaining one fully valid published `active-v1` source. Each mutation
pins identity and synchronizes the directory. A competing name, unexpected
hard link or byte in the hidden creation file, intent/source mismatch, identity
change, or absence uncertainty is preserved. An unmarked file without the
exact durable creation intent is never inferred to be app-created.

Capture-source xattrs use one strict v1 wire. Integers are unsigned big-endian
unless `Int64` is named; signed values use big-endian two's-complement bytes.
UUIDs use their 16 RFC 4122 bytes. No value has padding, trailing bytes,
alternate encoding, or optional fields:

- `com.holdtype.ios.capture-source-audio` is exact ASCII `v1`;
- `com.holdtype.ios.capture-source-identity` is exactly 47 bytes: schema byte
  `1`, attempt UUID, output intent (`1` Standard, `2` Translate), format
  (`1` m4a, `2` wav), creation time as UInt64 UTC milliseconds, device as
  UInt64, inode as UInt64, and generation as UInt32;
- `com.holdtype.ios.capture-source-completion` is exactly 25 bytes: schema byte
  `1`, duration milliseconds as UInt32, byte count as UInt64, modification
  seconds as Int64, and modification nanoseconds as UInt32; and
- `com.holdtype.ios.capture-source-phase` is exactly one of `active-v1`,
  `finalizing-v1`, `completed-v1`, `preparing-pending-v1`, `transferred-v1`,
  or `discarding-v1`.

`active-v1` has no completion value. `finalizing-v1` permits no completion
or one exact completion value; completed, preparing, and transferred require
one; discarding permits either shape inherited from its validated source. A
missing phase-required key, wrong length, reserved value, future schema,
overflow, creation time outside `0...253402300799999`, nanoseconds outside
`0..<1000000000`, filename/attempt mismatch, or stat/manifest mismatch is
unknown state and is preserved without implicit repair or removal.

The source marker and identity are written before `active-v1`. Every phase
replacement and completion value is descriptor-synchronized before the work it
guards. Any recorder-side truncate that preserves the inode is allowed;
replacement, rename, link-count change, symlink, owner/mode change, or
path/descriptor disagreement fails closed. The manifests contain no prompt,
Library content, credential, consent value, provider data, transcript, scene
identity, or external-app context.

#### Capture finalization and active recovery

Done or another recoverable stop writes and synchronizes `finalizing-v1`
before asking the recorder to close. Cancel first writes and synchronizes
`discarding-v1`, then stops and identity-pinned removes only that exact source.
The action never exposes cancelled bytes through Recover Recording; a crash or
uncertain unlink leaves discarding state for bounded cleanup. After close,
Persistence validates the descriptor-bound media,
canonical duration, byte count, stable modification time, and the P4 range
`300..<300000` milliseconds. It writes and synchronizes the completion value,
then writes and synchronizes `completed-v1`. A crash at any point retains
either finalizing state or a finalizing-plus-completion residue; it never
becomes completed automatically.

Recover Recording for finalizing state acquires the creator lock, CAS-validates
phase plus immutable identity, and revalidates descriptor/path media and stable
content metadata. Without a completion value it writes and synchronizes the one
canonical value; with an exact value it confirms those same bytes and metadata.
It then writes and synchronizes `completed-v1` before entering the completed-to-
preparing handoff. A mismatch remains blocked; a typed invalid result enters
discarding cleanup and never becomes provider work.

Interruption or media-service loss may close the recorder before finalizing can
be written. An unlocked positive-byte `active-v1` source is therefore never
age-deleted. Explicit Recover Recording revalidates identity and media: a valid
partial in `300..<300000` advances through finalizing and completed, while an
exact empty, too-short, maximum-duration, or invalid/corrupt partial follows its
typed non-provider cleanup. Any validation or removal uncertainty preserves
blocked local recovery.

Only an exact unlocked zero-byte `active-v1` source may use the abandoned
rule. Both its identity creation time and descriptor modification time must be
at least 3,600,000 milliseconds before a trustworthy current wall clock. A
future time, subtraction overflow, clock rollback, generation mismatch, or
either younger timestamp preserves it and offers confirmed Discard. A proven
abandoned source enters synchronized `discarding-v1` before unlink. Finalizing,
completed, and positive-byte active sources are never age-deleted.

#### Descriptor-bound Pending handoff

P4D adds a capability-only prepare/recover operation under the same canonical
repository-root operation gate as the existing Pending store. The legacy
path-based prepare API remains for existing fixtures and older internal flows,
but the production Voice controller cannot receive or call it. Both paths
serialize against the same protected-audio inventory and single Pending slot.

Recover Recording for an exact completed source first acquires the operation
gate and creator lock, CAS-validates phase plus immutable identity, revalidates
the whole Pending inventory, writes and synchronizes
`preparing-pending-v1`, and only then creates or adopts Pending audio. A
repeated action resumes the same attempt and cannot mint another destination.
The same transition is part of normal same-process Done.

The P4D copy uses exact staging grammar
`.capture-transfer-v1-<attempt UUID>.<m4a|wav>` and the normal final Pending
name `recording-v1-<attempt UUID>.<m4a|wav>`. Its staging descriptor receives
Complete protection, backup exclusion, the existing
`com.holdtype.ios.pending-recording-audio = v1` marker, and
`com.holdtype.ios.capture-source-transfer` before its first audio byte. The
transfer value is exactly 51 bytes: schema byte `1`, source attempt UUID,
source device UInt64, source inode UInt64, source generation UInt32, output
intent byte, format byte, duration milliseconds UInt32, and byte count UInt64.
Both application xattrs are descriptor-synchronized and revalidated together
with protection and backup exclusion before the first audio byte. The transfer
binding survives the no-overwrite rename. Unknown, legacy, malformed, or
mismatched staging/final files never become P4D recovery authority.

The copy streams from the already-open source descriptor and never reopens the
source pathname. Source and Pending descriptor/path identity are revalidated
before and after every await and commit point. Explicit recovery from preparing
state handles every later crash window under the operation gate and starts no
provider:

- empty Pending inventory starts the bound descriptor-to-staging copy;
- one exact zero-byte P4D staging name with an allowed application-marker prefix
  is a pre-byte residue authorized by the durable preparing source. It may contain
  neither application marker, the expected Pending marker only, or the exact
  matching transfer binding only. It must have no unexpected application-owned
  marker and any binding must match the source. Recover identity-pins and
  removes it, then restarts the copy. When both expected values are present, the
  non-overlapping transfer-bound staging case below applies;
- one exact transfer-bound staging file is validated; a complete media-valid
  copy is published, while an incomplete or invalid but exact owned staging file
  may be identity-pinned, removed, and recopied only by explicit Recover;
- one exact transfer-bound final audio without a journal is validated and
  adopted by committing the matching `awaitingRecovery` journal;
- a matching journal with directory-durably absent final audio may recreate that
  exact transfer-bound audio from the source and then confirm the same journal
  phase durably; and
- a corrupt or foreign journal, invalid existing final audio, unbound nonempty
  or legacy staging, multiple inventory entries, source mismatch, uncertain
  absence, or any other ambiguity is preserved and blocks Recover, Discard, and
  new capture.

Normal same-process Done creates `readyForTranscription` with its frozen
Settings snapshot. Explicit relaunch recovery creates `awaitingRecovery` with
current compact transcription settings. Both use the capture identity's
canonical creation time as Pending `createdAt`. Neither transition launches a
provider. After the exact Pending audio and journal are revalidated and
same-phase journal durability is confirmed, the source advances to
`transferred-v1` and synchronizes. Source retirement then uses
identity-pinned `unlinkat` plus directory synchronization.

Provider launch requires the durable Pending commit and either confirmed source
removal or durable `transferred-v1`. Cancellation after Pending commit finishes
this local checkpoint and never repeats prepare or provider work. Separate
identity-pinned cleanup first writes and synchronizes `discarding-v1` for an
exact active or finalizing source after Cancel or a typed
empty/too-short/maximum/invalid result. Confirmed Discard of an exact completed
or preparing source may write discarding only after proving that no matching or
ambiguous Pending destination owns it. Discarding state is never recoverable;
uncertain validation or removal preserves it for bounded cleanup.

Confirmed Discard for a source-only active, finalizing, completed, or eligible
preparing phase is one CAS operation under the operation gate and creator lock.
It requires expected attempt, phase, descriptor identity, and canonical Pending-
inventory proof; preparing is eligible only with no matching or ambiguous
destination. It writes and synchronizes `discarding-v1`, stops the recorder if
needed, then uses identity-pinned unlink plus directory synchronization. A
repeat may confirm directory-durable absence of that original identity but can
never unlink a recreated path. Discarding state is cleanup-only after relaunch.

#### Relaunch reconciliation

Passive process launch classifies capture source before a new recording and
performs no provider, Settings, Library, consent, credential, microphone, or
audio-session work:

- exact creation-intent residues use only the pre-exposure rules above;
- exact `discarding-v1` is identity-pinned cleanup-only and never presents
  Recover Recording;
- exact `transferred-v1` is removable after acquiring its lock;
- exact preparing state with a matching, media-valid Pending audio and matching
  journal advances to transferred only after same-phase journal durability
  confirmation, then the redundant source is removable;
- exact preparing state with a matching journal but directory-durably absent
  final audio presents Recover Recording, not Retry or Discard;
- exact preparing state without a matching Pending owner presents Recover
  Recording; confirmed Discard is available only after the Pending inventory
  proves no matching or ambiguous destination;
- exact completed, finalizing, or positive-byte active state presents Recover
  Recording or confirmed Discard and is never age-deleted;
- exact unlocked zero-byte active state uses the one-hour rule above; and
- unknown, malformed, unmarked, linked, replaced, locked, unavailable, or
  mismatched state is preserved and blocks mutation.

Launch never adopts an orphan, recopies audio, creates or repairs a journal, or
uploads. Its only automatic mutations are the exact pre-exposure cleanup,
discarding cleanup, zero-byte abandoned cleanup, transferred cleanup, and
redundant preparing-plus-fully-valid-Pending retirement defined above.

The bounded launch scavenger examines at most 128 entries, removes at most 16
confirmed artifacts and 200,000,000 logical bytes, stops before 500 monotonic
milliseconds, and permits no more than eight consecutive `EINTR` retries. A
missing namespace is a no-op; maintenance never creates or repairs it. Default
logs contain one compact action/result plus aggregate counts. Paths, filenames,
UUIDs, physical identities, audio bytes, and payloads remain behind opt-in debug
logging and redacted diagnostic values. The keyboard never links or runs this
owner.

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
then repeats descriptor/path identity checks. Media validation parses the same
open descriptor through read-only AudioToolbox callbacks and bounded `pread`;
it never reopens the absolute path. A timed-out worker retains and closes only
its duplicate descriptor, and one physical-root process context shares the
worker gate across all of its Store replicas so another validation does not
accumulate behind a still-running timed-out worker. A malformed, unreadable,
wrong-format, or duration-inconsistent `.m4a`/`.wav` remains a typed local
failure and never authorizes provider work. The validated media duration must
itself fall in `1..<300000` milliseconds and differ from the journal value by no
more than 250 milliseconds.

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
after root-bound, directory-durable audio absence is successfully proved;
journal completion likewise requires its own canonical-absence evidence. Any audio
validation/removal error preserves the journal and returns a typed local
failure. A missing journal never authorizes deletion of an orphan by filename
alone. History transfer, recording-cache transfer, orphan reconciliation, and
automatic source cleanup remain later checkpoints; P4 app-only relaunch
recovery and accepted-delivery reconciliation are already part of this
contract.

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

For every audio unlink that can outlive its initiating process, the removal
intent retains the pinned physical file identity. A retry after ambiguous
directory synchronization may prove the original absent or reconcile the same
identity, but must not unlink a recreated pathname. The required race test is:
unlink, uncertain directory barrier, create a new file at the same path, retry;
the recreated file survives and recovery remains pending.

The durable intent is the content-free, descriptor-bound extended attribute
`com.holdtype.ios.pending-audio-removal` on the exact current Pending journal
inode. Its canonical payload is exactly 50 big-endian bytes: schema `1`,
purpose `1` for accepted output or `2` for Discard, then the audio device,
inode, byte count, modification seconds/nanoseconds, and status-change
seconds/nanoseconds. Reading or writing it must pin the journal descriptor,
path revision, repository root, and current Pending value before and after the
operation. Ordinary journal replacement or removal is forbidden while this
intent remains. The journal file and its directory are synchronized before
the audio unlink, so a fresh filesystem instance can resume the same intent
without trusting process memory.

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
- On a recoverable failure with History on, HoldType commits one failed row as
  `pendingJournalRetirement`, transfers ownership of the relative audio
  identifier to that row's retry-only audio at the same stable path, and then
  removes the journal. Recovery may reconcile that exact row but never performs
  a generic row update or appends a second row. If both records survive a
  crash, the committed failed row is canonical and reconciliation removes only
  the redundant journal metadata.
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
- Missing canonical files never count as retired until the expected physical
  root and containing directory have produced durable absence evidence.
- Retry after ambiguous unlink never deletes a newly created object at the same
  relative pathname.
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
- History policy, generation, rows, retry-audio ownership, and cleanup status
  remain app-private and never enter App Group storage or a keyboard settings
  snapshot.

## Verification mapping

- Test default-on history, max-20 accepted retention, max-five failed retention,
  ordering, deletion, confirmed-cutover Clear History, disable-immediate logical
  clear, re-enable without restoration, confirmed no-op toggles, and cleanup
  retry without another generation.
- Test failure and process loss before policy commit, after commit before each
  cleanup owner, CAS supersession, relaunch derivation from confirmed policy,
  current-generation preservation, one-head FIFO outbox cleanup, unresolved-only
  delivery-marker cancellation, and redacted `complete`/
  `pendingLocalRecovery` cleanup results.
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
