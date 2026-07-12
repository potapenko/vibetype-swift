# iOS Failed History And Retry Audio

## Goal

Keep a small, local queue of provider failures that a person can retry after
relaunch, without losing the only protected recording, replaying provider work
automatically, or letting Clear History resurrect or strand old audio.

This spec is the target contract for failed History rows, their retry-only
audio, transfer from `PendingRecording`, explicit Retry, deletion and
retention cleanup, and participation in the existing History policy cutover.
Accepted rows remain governed by
`ios-accepted-history-foundation.md`; the general user experience remains in
`ios-history-and-storage.md`.

## Decision

- Failed History is containing-app-only, local, durable, and limited to the
  five newest recoverable attempts.
- A failed row owns its recording at the existing protected
  `HoldType/Recordings/Pending/recording-v1-<attempt>.<m4a|wav>` path. Transfer
  changes durable ownership; it does not copy or move the audio again.
- At most five audio-cleanup tombstones may coexist with the five visible
  failed rows. No row is evicted unless exact audio cleanup ownership is first
  committed.
- Retry is always a user action. Relaunch and lifecycle recovery perform local
  reconciliation only and never contact the provider.
- A Retry success must first commit the normal protected accepted-output
  delivery. Only that exact durable proof may retire the failed row and queue
  its audio for cleanup.
- Failed rows use the same app-private History enabled value and policy
  generation as accepted rows. Clear, Disable, and Enable never expose an old
  failed row or leave its retry audio outside bounded cleanup ownership.
- Failed History and retry audio never enter App Group storage, the keyboard
  extension, iCloud, logs, or analytics.

## Scope

- strict failed-History v1 values, journal, repository, and resource bounds
- recoverable failure classification for Transcription and Translation
- exact `PendingRecording` journal-to-row ownership transfer
- retention, individual Delete, and audio-cleanup tombstones
- participation in History policy cutover and provider-free lifecycle recovery
- durable one-retry ownership and accepted-output success handoff
- corruption, cancellation, process-loss, and storage-unavailable behavior

The History screen, first-use disclosure, settings controls, and Voice screen
presentation consume this contract in the containing-app UI milestone. This
checkpoint must make those future controls truthful but does not expose a
partial UI early.

## Non-goals

- automatic provider retry, background retry, or retry scheduling
- more than one provider retry at a time
- retry of capture, recording-finalization, text-correction, or output-delivery
  failures
- storing accepted text, raw provider responses, raw errors, status codes,
  prompts, credentials, dictionary content, or translation content in a failed
  row
- moving retry audio into a second failed-recordings directory
- Recording Cache retention or accepted-row playback ownership
- App Group publication, keyboard commands, cloud sync, or migration from the
  macOS session-only failure store

## User-Visible Contract

- A recoverable failed row shows `Not transcribed`, a compact reason, the
  original time, retry count, and known model, language, and duration.
- Retry is available only when the row still owns valid audio, History remains
  enabled for that row's current generation, no Voice/provider chain is
  active, one audio-cleanup tombstone slot is free, and current settings and
  credentials can run its output intent.
- When all five audio-cleanup slots are occupied, Retry remains unavailable
  until bounded provider-free cleanup retires the canonical head. That local
  cleanup does not change the failed row, its retry count, or its original
  failure.
- Missing or invalid current setup routes to the owning Settings section
  without changing the row or retry count.
- Retry preserves `.standard` or `.translate`. Translation retries use the
  current valid translation configuration and never publish the intermediate
  transcription as the requested result. Both intents use one fresh frozen
  prompt/correction/local-processing snapshot; Retry never reuses Nearby Text
  or any prompt captured by the failed attempt.
- Automatic insertion is off for every failed-row Retry. A successful result
  is recovered through the normal accepted-output surface, from which the user
  may Insert, Copy, Share, or use an eligible later keyboard handoff.
- A Retry failure that is still recoverable keeps the row and audio, advances
  the retry count once, and updates its compact category and failed pipeline
  stage. It does not change the last accepted result.
- Cancelling an active Retry cancels its provider task and keeps the failed row
  and audio. A late provider response has no authority to accept output or
  delete the row.
- Individual Delete makes only the selected failed row unavailable, then
  removes its exact retry audio during bounded local cleanup. If cleanup is
  interrupted, the row stays deleted and Storage & Recovery may show a
  redacted cleanup-pending status.
- Clear History or turning History off immediately filters all older failed
  generations after the policy commit. Re-enabling never restores them.
- A storage failure before the row or deletion boundary preserves the prior
  visible state. A failure after a confirmed boundary never rolls that boundary
  back and is retried locally.

## Recoverable Failure Eligibility

A durable failed row may represent only one of these pipeline stages:

- `transcription`
- `translation`

The stable failure categories are:

- `credentialRejected`
- `networkUnavailable`
- `networkFailure`
- `timedOut`
- `rateLimited`
- `providerUnavailable`
- `providerRejected`
- `invalidResponse`
- `emptyResult`
- `echoRejected`

These are product categories, not serialized provider errors. Credential
missing, unavailable, or rejected maps to `credentialRejected`; dictionary or
nearby-context-only output maps to `echoRejected`; provider status codes are
not retained. A mapper may narrow a current runtime error into this list but
must never persist `localizedDescription`, debug output, or an unknown enum
case.

The Retry provider adapter normalizes terminal Transcription and Translation
outcomes before they reach the failed Store. This durable mapping is total and
payload-free:

- missing, unavailable, or rejected credentials map to
  `credentialRejected`;
- network-unavailable, other network failure, timeout, rate limit, and
  provider-unavailable outcomes map to their same-named stable categories;
- an HTTP bad-request response or other provider rejection maps to
  `providerRejected`, with every status code discarded;
- unreadable provider output maps to `invalidResponse`;
- empty or whitespace-only Transcription or Translation output maps to
  `emptyResult`;
- dictionary-only or nearby-context-only Transcription output maps to
  `echoRejected`.

A local invalid recording, unsafe request construction, oversized multipart
metadata, invalid Translation route, provider-reported cancellation without a
mapped failure, or unknown runtime outcome is not mapped to a new durable
category. It clears only the exact Retry operation while preserving the row's
previous category and stage. Remote Text Correction is never an input to this
durable mapper: every correction provider error, timeout, empty/unsafe output,
or provider-reported cancellation fails open to the accepted transcription.
Only outer user/task cancellation uses the exact C4.4A cancellation authority.

Capture cancellation, invalid/corrupt audio, maximum-duration and too-short
recordings, request construction that cannot safely use the artifact,
text-correction failure, output-delivery failure, and unknown failures do not
create a failed row. The existing pending/accepted/cache contracts retain or
dispose of those outcomes according to their own rules.

## Failed History V1 Record

The sole metadata record is
`Application Support/HoldType/ios-failed-history.json`. It is an app-private,
backup-excluded, atomic strict record with Complete file protection, a maximum
source size of 1 MiB, and the exact marker
`com.holdtype.ios.failed-history = v1`.

The root contains exactly:

- `schemaVersion`
- `revision`
- `entries`
- `audioCleanup`

`schemaVersion` is `1`. `revision` starts at `1` on the first mutation and
advances exactly once for each confirmed root mutation. Missing storage means
empty only when absence is proven. Malformed, duplicate-member, oversized,
future-version, incorrectly protected, or unavailable storage is never treated
as an empty successful load and is preserved for diagnosis or later recovery.

Each of at most five failed entries contains exactly:

- `attemptID`
- `createdAt`
- `updatedAt`
- `policyGeneration`
- `failureCategory`
- `pipelineStage`
- `retryCount`
- `outputIntent`
- `transcriptionModel`
- `transcriptionLanguageCode`
- `durationMilliseconds`
- `byteCount`
- `audioRelativeIdentifier`
- `ownershipState`
- `retryOperation`

The optional language and retry operation use explicit JSON `null`. Timestamps
are canonical integral Unix milliseconds. IDs are lowercase canonical UUIDs.
Model and language bounds match the protected pending-recording and accepted
output contracts; the model is at most 256 bytes in UTF-8.
Duration, byte count, attempt ID, format, and relative identifier must match
the exact validated protected artifact. An entry never contains an absolute
URL. `policyGeneration` is positive, `createdAt <= updatedAt`, and retry count
is a nonnegative signed 32-bit value. Timestamp, revision, generation, or retry
count overflow fails before mutation rather than wrapping or pruning data.

`ownershipState` is either:

- `pendingJournalRetirement` — the row is durable and canonical, but the old
  `PendingRecording` metadata has not yet been proved absent; its retry count
  is zero and it has no retry operation;
- `ready` — the failed row is the sole durable metadata owner of its audio.

A strict v1 envelope permits at most one `pendingJournalRetirement` row. More
than one is invalid storage, not a queue that recovery may reorder or guess
through.

Rows are presented newest-first by `createdAt`, then canonical `attemptID` for
a stable tie break. Retry updates do not change `createdAt` or retention order.
Attempt IDs and audio identifiers are unique across entries and cleanup
tombstones.

Each of at most five `audioCleanup` tombstones contains exactly:

- `attemptID`
- `policyGeneration`
- `queuedAt`
- `audioRelativeIdentifier`
- `byteCount`

A tombstone contains no failure category, model, language, retry operation, or
accepted text. It is the sole authority to remove that exact attempt-scoped
audio after a row becomes unavailable. Tombstones are stored oldest `queuedAt`
first, then by canonical `attemptID`, so every cleanup pass selects the same
head.

There is no automatic import from the macOS failure store, legacy absolute
paths, UserDefaults, external files, or App Group records. Any future migration
or explicit reset requires its own contract.

## PendingRecording Ownership Transfer

A recoverable provider failure first returns its exact pending record to
`awaitingRecovery`. Failed-row transfer then runs under the same expected
production-root gate as the policy, failed repository, and pending store. The
gate, store identities, live-owner state, and transfer state are scoped to the
canonical physical root, so equal UUIDs in different roots cannot authorize or
block one another. A caller cannot mint a transfer from identifiers, paths,
rows, policy generations, file lists, or a generic process-loss claim.

The transfer is one coordinator-owned, provider-free transaction:

1. strictly load the pending observation and validate its protected audio;
2. confirm an enabled History policy and capture its exact generation;
3. seal the complete decoded pending record and its physical journal revision,
   a descriptor-backed validated-audio lease retained across the row commit,
   the store identities, root identity, active root-gate lease, and policy
   receipt;
4. commit the failed row as `pendingJournalRetirement`;
5. use only the store-minted row receipt to remove the matching pending journal
   metadata without removing audio;
6. prove the matching journal metadata durably absent after directory
   synchronization and advance only that row to `ready`.

The failed row preserves the pending record's original `createdAt` and uses the
canonical transfer time clamped to at least `createdAt` for `updatedAt`. Its
initial retry count is zero. Only one `pendingJournalRetirement` transaction may
exist at a time; it must be reconciled before another transfer is admitted.

The durable failed row is canonical as soon as step 4 commits. If both records
survive a crash, provider-free recovery resumes journal retirement; it never
creates a second row, deletes the audio, or calls the provider. If the row did
not commit, the pending journal remains canonical.

A committed row plus an already-absent matching pending journal advances to
`ready` only after durable absence is proved. A different pending record,
partial field mismatch, collision, foreign root, or uncertain failed-root
outcome preserves all bytes and reports local recovery pending. Policy is
checked before row creation. Once the row commits, a later Clear or Disable
cannot interrupt metadata retirement; C4.3 logically filters and cleans the
resulting failed row after transfer reconciliation. Lifecycle recovery performs
no provider work.

Every durable cross-store boundary revalidates the canonical physical root
immediately before and after mutation and again on its error path. A changed
binding permanently conflicts that process context and prohibits a later
boundary. Bracketing checks alone are not authority: the expected physical
device and inode are consumed inside each irreversible journal or audio file
operation, compared with the already-opened Application Support descriptor
before the first create, publish, replace, remove, or cleanup side effect, and
the remaining work is descriptor-relative. Failed-journal staging maintenance
uses the same active root-gate lease and physical-root authorization as row
mutation. A process-local row receipt or lease never survives relaunch:
recovery mints a fresh row-derived metadata-retirement directive only from the
exact durable `pendingJournalRetirement` row under a new active root lease. The
Pending store then either requires an exactly matching journal snapshot before
removing it or proves the canonical journal path durably absent. A present but
mismatching journal is a conflict; absence never invents a prior snapshot.

The same physical-root rule applies before provider dispatch. Media validation
and the process-local provider source retain and read the already opened audio
descriptor; neither may reopen the durable absolute path. A same-path root
replacement observed while creating another store context conflicts both the
old and replacement physical roots, while a retargeted symlink alias may join
an already valid destination context only after the source context is
permanently conflicted.

Pending metadata removal preserves its own exact uncertainty. Recovery compares
the physical source snapshot and intended absence: exact source present means
not committed, exact absence after directory synchronization means committed,
and any other state fails closed. A metadata-only journal observation and
absence-proof path must not invoke the ordinary PendingRecording load behavior
or require the protected-audio namespace to be empty.

### Frozen C4.2B Reconciliation Identity

The relaunch matching predicate is the complete set of fields shared by the
failed row and Pending journal: `attemptID`, `createdAt`,
`audioRelativeIdentifier`, `outputIntent`, `transcriptionModel`,
`transcriptionLanguageCode`, `durationMilliseconds`, and `byteCount`. The
Pending record must also be exactly `awaitingRecovery` with a null
`transcriptionID`. Pending `updatedAt` is not persisted in the failed row and
is not guessed or compared. The audio format is derived from the validated
relative identifier. A mismatch in any compared field is a conflict, even
when the attempt ID and audio path match.

The Pending store is the sole issuer of a process-local metadata-absence
receipt. A `removed` outcome binds the exact observed Pending journal snapshot
and physical file revision. An `alreadyAbsent` outcome, including relaunch
after a completed unlink, instead binds the exact failed-row directive and
canonical journal path without inventing a file revision. Both outcomes prove
the journal absent after directory synchronization and a repeated path check,
and bind the Pending store and directory identity, canonical root, active gate
lease, and exact failed-row receipt or relaunch directive. They authorize only
the matching `pendingJournalRetirement` to `ready` mutation and grant no
provider, audio-removal, generic journal-removal, or cross-row authority. The
same exact receipt may reconcile that one mutation after an uncertain outcome
under the same active lease, but is never reusable for another row, source,
root, lease, or semantic mutation. Relaunch discards all old capabilities and
mints fresh directives or absence receipts from current durable state.

Advancing ownership from `pendingJournalRetirement` to `ready` preserves the
original transfer `updatedAt`; journal-retirement housekeeping does not change
the user-visible failure timestamp. It advances the failed-root revision once
and changes no other row field.

Mutation uncertainty retains only the exact intended source and outcome.
Within one process, retry uses the sealed transfer timestamp and intended row.
After process loss, durable state is the discriminator: proof that the intended
row is absent and that no failed row or tombstone collides by attempt ID or
audio identifier leaves Pending canonical; the exact
`pendingJournalRetirement` row permits a fresh metadata-only directive;
synchronized Pending absence permits a fresh absence receipt and the exact
transition to `ready`; the exact `ready` row plus absent Pending metadata is
terminal. A nonmatching owner is a conflict. Every other observation preserves
all bytes and reports local recovery pending. Transfer never performs a generic
failed-row update and never appends a second row to reconcile an exact existing
`pendingJournalRetirement` row.

History disabled, stale policy generation, failed-row capacity, cleanup
capacity, corrupt state, mismatched roots, live provider ownership, or any
unproven identity keeps the attempt in `PendingRecording` recovery. It must not
be hidden, overwritten, or counted as a failed History row.

The protected-audio namespace is no longer required to be globally empty once
failed rows exist. A new pending recording may be published only after a sealed
failed-store inventory proves the exact set of row- and tombstone-owned final
files under the same root gate. A separate Pending-store capability may prove
the one exact current pending file from its full journal snapshot; the
coordinator combines those sealed capabilities under the same active lease. A
fully matching pending record and its
`pendingJournalRetirement` row intentionally alias one physical file and count
as one owner-transfer artifact; every other duplicate or partial match fails
closed. Callers cannot provide filenames or arrays.

Inventory validation is bounded to the maximum eleven expected final files
(five rows, five tombstones, and one pending recording) plus one overflow
sentinel. Unknown files, staging files, duplicate ownership, missing expected
files, or a foreign inventory fail closed; reconciliation never guesses from a
filename. Namespace validation and publication of a new pending artifact occur
in one exclusive directory operation for cooperating HoldType writers, followed
by bounded inventory and root-identity revalidation before the pending journal
commit. Row and pending files receive full protected-audio and duration
validation. Tombstone cleanup validates exact attempt, path, byte count,
protection, and any observed physical identity without decoding media, because
a tombstone does not retain a trusted duration.

After a failed row commits, ordinary PendingRecording begin, retry, recovery,
prepare, and discard paths cannot regain provider or audio-removal authority
for that attempt. In particular, the normal pending discard path may remove an
audio file only after the failed store proves that no row or tombstone owns it;
it never substitutes for transfer-time journal retirement.

## Retention, Delete, And Audio Cleanup

Logical removal and physical audio removal are separate durable boundaries:

1. atomically remove the selected ready row and append its exact audio-cleanup
   tombstone;
2. remove or confirm absence of only that tombstone's matching protected file;
3. atomically retire the tombstone.

Failure or commit uncertainty retains the exact phase. Cleanup never scans by
age, constructs a path from caller text, bulk-deletes the directory, or removes
a current pending recording. A byte-count or attempt mismatch preserves both
the file and tombstone and reports local recovery pending.

When a sixth eligible failure arrives, the absolute oldest row in the stable
failed-row order, `entries.last`, must be the eviction candidate; the store
never skips it to find another eligible row. For equal `createdAt`, this is the
lexicographically greatest lowercase canonical attempt UUID. That row must be
`ready`, non-retrying, have exact validated audio, and have one free tombstone
slot before it moves to a cleanup tombstone in the same root mutation that
admits the new row. If cleanup proof is unavailable or that exact oldest row is
not safely removable, the new failure remains visible through
`PendingRecording`; HoldType does not silently evict either attempt.

Each ordinary lifecycle pass removes or confirms at most one cleanup audio file
and retires at most its one canonical head tombstone. Explicit Delete may drive
the same exact state machine for only the tombstone minted from that Delete's
exact logical-removal receipt, even when an older unrelated tombstone is still
queued; it never loops into or skips among other cleanup work. Only a
store-minted authorization for that exact canonical tombstone may remove or
confirm absence of its file. The tombstone retires only after a sealed
post-synchronization outcome bound to the same failed-journal snapshot, root,
active lease, directory identity, attempt, path, and byte count. A `removed`
outcome also binds the exact physical identity observed before unlink; an
`alreadyAbsent` outcome has no file identity to invent. An unlink or journal
rewrite whose commit is uncertain is reconciled against the exact intended
snapshot before any unrelated mutation proceeds.

## History Policy Cutover

Failed rows use only the strict policy record defined by
`ios-accepted-history-foundation.md`. Reads expose entries only when History is
enabled and only for the exact current generation. That logical filter applies
immediately after a confirmed Clear, Disable, or state-changing Enable, before
physical failed-row or audio cleanup finishes.

Post-policy reconciliation joins the existing C3 cutover state machine. It
must:

- preserve every current-generation row on a confirmed toggle no-op;
- keep an invalidated `pendingJournalRetirement` row durable but logically
  filtered until its exact row receipt retires the redundant pending journal
  and confirms absence;
- move only invalidated `ready` rows into exact cleanup ownership;
- cancel a process-lost retry operation without dispatching provider work;
- process cleanup in bounded deterministic order;
- retain exact uncertainty and retry without advancing policy generation;
- return `pendingLocalRecovery` until no invalidated failed row, blocked
  journal retirement, stale retry operation, or associated audio tombstone
  remains.

The coordinator order is fixed. After the confirmed policy boundary it first
finishes failed-History work, then resumes the existing C3 order of accepted-row
pruning, one canonical outbox head, and standalone delivery inspection. Within
the failed domain it:

1. resumes only an exact retained failed mutation, transfer, or audio-cleanup
   phase owned by this cutover;
2. reconciles the one `pendingJournalRetirement` row through exact Pending
   metadata absence and advances it to `ready`;
3. locally cancels one invalidated process-lost `reserved` or
   `providerDispatched` retry operation;
4. cleans and retires one already queued canonical audio tombstone head; or,
   when no tombstone is queued, moves the absolute canonical oldest
   invalidated `ready` row into one exact tombstone.

Each policy-cleanup call completes at most one of steps 2 through 4 and then
returns `pendingLocalRecovery`; a later call continues under the already
committed policy. This keeps filesystem work to one canonical head per pass and
prevents a failed cleanup from being skipped by a later row. The canonical
oldest invalidated row is the last matching row in the stable failed-row order.
Current-generation rows survive a confirmed toggle no-op unchanged. A future
row or tombstone generation is preserved and fails closed rather than being
reinterpreted as stale work.

An invalidated `acceptingOutput` retry operation is not generic stale work.
Until the explicit-Retry checkpoint can compare its exact accepted-delivery
identity, policy cleanup preserves the row and delivery relation and returns
`pendingLocalRecovery`. That checkpoint must apply the exact-delivery branch
defined below; C4.3 never clears `acceptingOutput` merely because process-local
provider ownership is absent.

The policy commit stays the logical-success boundary. A failed-root or audio
cleanup error cannot roll back Clear or a toggle. Corrupt, future, unavailable,
rollback-ambiguous, or foreign-root state remains preserved and pending.

The containing-app UI disables Clear, Disable, and per-row Delete while that
row has a live retry or playback owner. Root-gate serialization is still
required: UI gating alone is not storage authority. After process loss there is
no live provider owner, so local cutover recovery may cancel the durable retry
operation and continue.

The failed store owns one canonical retry-owner state for its physical root,
and every coordinator over that store must reuse it. Reservation and durable
`providerDispatched` publication are minted under an active root lease. After
that publication is confirmed, the provider executes outside the root gate so
long network work does not hold filesystem and policy serialization.

The exact live-owner registration is nevertheless stable for the lifetime of
that process context. Ending the lease that minted it does not make the owner
stale and is not process-loss evidence. The registration binds the durable
retry identity, its own monotonic owner epoch, its one-shot provider authority,
and cancellation. A completion may clear or advance only that exact epoch; a
delayed completion from an older lease or older Retry cannot clear a newer
owner, accept its text, or cancel its provider task.

Every conflicting root-gate operation inspects this one canonical registration
after acquiring its lease and before its first durable boundary. A live owner
blocks policy mutation, another accepted-output acceptance, failed-row Delete,
audio ownership changes, and a PendingRecording provider launch. Conversely, a
failed-row Retry cannot reserve while a PendingRecording provider owner or
provider-capable handoff is live. The two provider paths remain mutually
exclusive even though their external requests run outside the root gate.

Relaunch creates a new process context whose retry-owner state is idle. Only
that new idle context, combined with the exact durable `reserved` or
`providerDispatched` row, proves process loss. Recovery atomically moves idle
to one exact cancellation reservation. While reserved, no Retry may become
live. The reservation is consumed only by a store-minted completion after the
exact `retryOperation = null` outcome is durably confirmed; commit uncertainty
retains it. Foreign owner states and stale epochs are rejected.

Every resumed `pendingJournalRetirement` subphase validates the whole current
failed envelope, including all sibling rows and tombstones, against the already
committed policy generation. This validation is repeated for each freshly
inspected or refreshed authority immediately before Pending metadata or failed
root effects. A future-generation sibling therefore preserves failed bytes,
Pending state, audio, and policy rather than letting an older retained transfer
continue through it.

## Explicit Retry State Machine

Retry begins only from a current-generation `ready` row after exact audio
validation and fresh containing-app setup checks. One durable `retryOperation`
preallocates and freezes exactly:

- `retryID`
- `createdAt`
- `transcriptionID`
- `deliveryID`
- `sessionID`
- `transcriptID`
- `keepLatestResult`
- `state`

Its stable states are `reserved`, `providerDispatched`, and
`acceptingOutput`. The operation contains no credential, prompt, accepted text,
translation text, provider payload, or host-field identity. The row's model and
language update to the fresh configuration captured for this retry before
dispatch; Translation-specific current configuration remains transient because
provider work never resumes automatically after process loss. The durable
`keepLatestResult` value is frozen from the same pre-reservation setup snapshot;
after relaunch, a matching accepted delivery must carry that exact value rather
than supplying or reconstructing a newer preference.

The identifiers have two deliberately distinct roles. `transcriptionID` is the
provider-request and Usage identity. `transcriptID` is the final accepted-output
identity. They remain distinct for both Standard and Translation Retry. This is
the sole failed-row Retry exception to the ordinary PendingRecording rule that
an accepted delivery's transcript ID equals its pending transcription ID.

The delivery identity compared by Retry is exactly `deliveryID`, `sessionID`,
the failed row's `attemptID`, and `transcriptID`. `retryID` and
`transcriptionID` are not delivery identities. A partial collision means that
at least one, but not all four, of those delivery identities match. A complete
identity match is accepted only through the exact Retry relation and never by
an ordinary ID lookup.

Before reservation, the coordinator freezes the current valid transcription
configuration, a fresh `TranscriptionPromptComposition`, Text Correction and
local post-processing configuration, any required Translation configuration,
credentials/setup eligibility, and Keep Latest Result preference. The prompt
composition has no Nearby Text and is built once from the current freeform
prompt, emoji commands, and Custom Dictionary. No prompt, dictionary,
replacement rule, correction configuration, or Translation content enters the
failed row. The coordinator also proves that no Pending provider owner is live
and that fewer than five audio-cleanup tombstones exist. A full tombstone queue,
invalid setup, retry-count overflow, stale policy, or failed audio validation
changes no row field and issues no provider authority.

Retry admission also requires the accepted-History outbox to have no durable
head. A retained head is reconciled by the ordinary outbox worker before the
user retries again; Retry never spends a provider request and then waits on an
outbox worker that its own live-owner relation excludes.

The free tombstone slot is a durable reservation, not a point-in-time hint.
While any row has a retry operation, every unrelated failed-row mutation that
could append a tombstone is blocked. A valid envelope therefore always
satisfies `audioCleanup.count + activeRetryCount <= 5`, where
`activeRetryCount` is zero or one. Only exact Retry success may consume that
reserved slot; cancellation or failure releases it by clearing the operation.

The durable transitions are ordered:

1. `nil -> reserved` advances the retry count once, stores the fresh model and
   language, freezes every operation identifier plus Keep Latest Result and
   state, and updates `updatedAt` to the canonical reservation time;
2. `reserved -> providerDispatched` commits before the one-shot provider task
   may launch and preserves the retry count, failure fields, and `updatedAt`;
3. the provider runs outside the root gate while the stable live-owner
   registration excludes conflicting work;
4. provider completion, timeout, or cancellation reacquires the root gate and
   may mutate only from the exact registered operation and owner epoch;
5. `providerDispatched -> acceptingOutput` is permitted only after the final
   requested output validates and the provider completion wins the atomic race
   with cancellation. It also preserves `updatedAt` until a later failure or
   cancellation outcome needs a new user-visible failure time.

The retry count advances exactly once when a valid new operation is durably
reserved. The store then mints one process-local, cancellable provider handoff
for the exact operation. Re-entry cannot obtain a second handoff. Cancellation
retires that authority before the row becomes retryable again and wins over a
late response.

On a recoverable failure, the same root mutation clears `retryOperation`, keeps
the audio, records the mapped category and actual failed stage, and advances
`updatedAt` to the canonical completion time. A setup failure before reservation
changes nothing. Cancellation and a nonrecoverable or unmappable runtime
outcome clear the operation and preserve both the row's previous durable
category and previous durable stage rather than inventing either. Every
same-process terminal clear advances `updatedAt` to its canonical completion
time, including user/task cancellation and an unmappable outcome;
provider-free process-loss cancellation preserves it. Current audio and setup
validation still govern whether another explicit Retry is available; Delete
follows the normal local cleanup contract.

Cancellation and provider completion race only in the stable live-owner state.
Cancellation first retires the exact provider authority, then reacquires the
root gate to clear the durable operation. A noncooperative late response from
that retired epoch has no acceptance or mutation authority. Once
`acceptingOutput` is durable, provider cancellation is no longer available;
remaining work is local accepted-output recovery. Every Transcription, remote
Text Correction, and Translation boundary has an explicit timeout. Timeout
retires the exact stage authority, requests transport cancellation, and waits
only for the provider adapter's bounded completion before its outcome is used.
The adapter must finish independently of a noncooperative loader or local I/O
and ignore any abandoned late completion. A Transcription or Translation
timeout records `timedOut` at the active durable stage; a correction timeout is
fail-open and keeps the accepted transcription.

After non-empty Transcription succeeds, the coordinator immediately makes the
one idempotent Usage attempt before correction or Translation. Optional remote
Text Correction is fail-open for provider failure, timeout, empty output, and
unsafe-length output; then local cleanup, emoji commands, and replacement rules
run exactly once with the frozen post-processing configuration. User/task
cancellation is checked again after every drained boundary and still cancels
the whole Retry. A Translation Retry consumes only that processed transient
transcription. Translation is strict, and only its non-empty result receives
the final optional plain-typography cleanup before acceptance; correction,
emoji commands, and replacement rules do not run again on translated text.

On process loss, lifecycle recovery never resumes `reserved` or
`providerDispatched` work. A new idle process context cancels the durable
operation locally and keeps the row available for a new explicit Retry with new
identities. The ended minting lease alone is never sufficient evidence while
the original stable live-owner registration still exists.

Every newly created production process context starts its shared failed/delivery
interlock in `recoveryScanRequired`, which blocks ordinary PendingRecording,
delivery, and failed work before its first storage effect. Under the root
operation gate, only a strict failed-root inspection may replace that state:
confirmed absence of any retry operation opens ordinary work; `reserved` or
`providerDispatched` enters exact process-loss cancellation ownership; and
`acceptingOutput` installs its exact recovery relation before the delivery slot
is read. Corrupt, future, unavailable, rollback-ambiguous, foreign-root, or
uncertain failed state leaves the barrier closed. Creating a coordinator or
waiting for an ended lease is not recovery evidence. A canonical recovery time
earlier than the failed row's `updatedAt` or retry operation's `createdAt` is
rollback-ambiguous and cannot cancel or complete that operation.

For `acceptingOutput`, recovery classifies the exact accepted-output slot under
the failed/delivery interlock:

- a byte- and identity-matching retry delivery is durable success proof;
- a strictly proved missing slot is absence of the retry delivery;
- a wholly unrelated record that matches none of the retry's preallocated
  identities is the interlock-frozen predecessor and also proves absence of the
  retry delivery;
- any partial identity match, substituted predecessor, corrupt or future
  value, unavailable protection, foreign root, or uncertain observation fails
  closed.

Missing or frozen-predecessor proof clears the interrupted operation and keeps
the failed row and audio. A matching delivery enters only the exact local
success-recovery path below. A caller-provided delivery ID or unrelated-record
assertion is never absence proof.

The frozen predecessor is not copied into failed History and no text-derived
digest is added there. Its durable proof is the combination of the strict
`acceptingOutput` relation and the rule that every compatible delivery mutation
must first prove that relation absent. The transition observes the whole
delivery snapshot under the root lease before publishing `acceptingOutput`;
after that publication, the exact unchanged wholly unrelated snapshot is the
predecessor. After relaunch, a wholly unrelated record is classified as that
predecessor only after both stores are read under the same interlock and no
compatible mutation has crossed the relation. A binary or repository path that
cannot prove this enforcement, including downgrade or foreign-root access,
fails closed rather than treating the record as a predecessor.

Likewise, accepted text is never duplicated into failed History. In the live
process, a matching Retry delivery is byte-compared with the one retained
accepted-output preparation. After process loss, the store-minted durable
relation, all four delivery identities, the exact output intent, automatic
insertion disabled, frozen Keep Latest preference, matching History metadata,
and strict delivery-store lineage together are the replay proof that the
delivery came from that Retry branch. No caller-reconstructed text or
preparation can supply this proof.

After the requested Transcription or Translation produces accepted text, the
coordinator reacquires the root gate and sets `acceptingOutput`. That durable
transition freezes the exact current delivery slot as either missing or one
fully observed predecessor and activates the delivery interlock before the gate
is released. The coordinator then commits the text through an exact Retry branch
of the existing accepted-output/accepted-History coordinator using the
preallocated identities, the row's output intent, automatic insertion disabled,
and the frozen Keep Latest Result preference. Generic acceptance is not allowed
to consume this relation. Delivery commit is the provider-replay boundary.
Accepted-output uncertainty is resumed or confirmed with the same preparation
in process; it never triggers a second provider request.

Slot observation and interlock activation have no await-sized race. While the
delivery actor owns the observation, it mints an opaque freeze reservation and
installs it in the shared interlock before returning the proof. That
reservation blocks ordinary delivery and failed-store mutations even though
the failed row is still `providerDispatched`. The exact accepting authorization
upgrades the same reservation ID to the durable relation before its CAS. A
definitive pre-commit failure releases only that exact reservation; commit
uncertainty or a visible `acceptingOutput` outcome retains it. A raw relation
key cannot mint, refresh, upgrade, or clear either phase.

The raw relation key is identity, not bearer authority. The delivery store
mints a redacted permit bound to the exact accepting receipt, delivery-store
identity, owner, root-gate lease and live interlock. Every permitted mutation
also proves that its target is the exact accepted Retry, the frozen predecessor,
or the predecessor's exact pending-to-cancelled History transition. The permit
cannot replace a substituted wholly unrelated current slot. Absent-row History
replay rechecks the same live permit at the moment of the row decision.

The accepted delivery persists that origin as strict wire version `2` with one
required canonical `failedRetryID` equal to the operation's exact `retryID`.
Ordinary version-1 acceptance always has nil provenance and cannot reconstruct
or adopt the tagged relation, even when all four identities and accepted bytes
match. The tag participates in record and expectation equality, survives
terminal History transitions, and is cleared only when the delivery becomes a
discarded tombstone after relation protection permits it.

All validation that may definitively reject the provider result occurs before
`acceptingOutput`. Once that state is durable, a local preparation, delivery,
History, or repository error retains exact local recovery and never converts
back into provider work. Only the explicit missing/frozen-predecessor recovery
branch may clear an interrupted `acceptingOutput` operation while keeping the
row and audio.

Within the live process, an uncertain accepting transition retains its exact
frozen-slot proof, and an uncertain terminal success retains its exact success
phase. Bounded retries refresh those capabilities under a new root lease and
resume only the same mutation. A definitive pre-boundary failure with no live
relation discards the frozen checkpoint so the already-completed provider
result may safely freeze the slot again; it does not call the provider again.

The failed row remains `acceptingOutput` until the matching delivery's History
marker is terminal: `committed` after an exact retained-or-not-retained row
decision, or `cancelled` by exact newer-policy authority. In particular, an
ordinary `pending` marker may not lose the failed row after process loss. The
combined durable failed-row/delivery relation is store-minted replay provenance
for exactly one matching absent-row History decision; it grants no authority
for an unrelated delivery, row, generation, or caller reconstruction. Existing
`pendingReplacement` recovery keeps its narrower replacement provenance.

An otherwise identity-matching Retry delivery with `pendingReplacement`, a
missing History marker, `discarded` delivery state, automatic insertion
enabled, incompatible output intent or Keep Latest preference, or mismatched
History metadata is not success proof. It is a collision and preserves both
stores for exact recovery or diagnosis.

Only a matching durability-confirmed delivery, terminal History marker, and
the exact failed-row relation may atomically remove the failed row and append
its pre-authorized audio-cleanup tombstone. The reservation-time free-slot proof
guarantees capacity. This mutation never unlinks audio. Commit uncertainty
protects the delivery and resumes only the same row-to-tombstone outcome.

The durable `acceptingOutput` relation protects its frozen slot and any matching
committed delivery until the row-to-tombstone transition finishes. Delivery
acceptance/replacement, explicit clear, expiry removal, Keep Latest cleanup,
History marker mutation, bridge reservation/publication, and any other mutation
that could change, remove, expose, or supersede that slot must first obtain a
store-minted failed-relation disposition under an active root lease. Ordinary
work requires exact relation absence. Only the matching Retry acceptance and
History-recovery paths may consume the positive relation. Caller assertions,
process-local delivery reservations, and an ID lookup are insufficient.

If the failed store is corrupt, unavailable, foreign, future, or uncertain,
the frozen slot and matching delivery remain protected and later accepted
output fails closed rather than losing the only durable success proof. After
process loss, a matching delivery therefore still proves success; confirmed
absence or a wholly unrelated frozen predecessor is safe only because every
compatible mutation enforces this interlock.

While the exact relation is live, the delivery's 24-hour expiry is suspended
only for proof-bound local completion: exact acceptance replay, pending History
authorization, the one absent-row Retry decision, terminal marker CAS,
terminal confirmation, and row-to-tombstone success. It never re-enables
bridge publication, automatic insertion, ordinary reads, replacement, or
removal. Post-expiry History mutation clamps `updatedAt` to the existing
`expiresAt` so the immutable TTL contract remains valid. Once the relation is
retired, normal expiry semantics resume.

A live external provider owner blocks a Clear, Disable, or state-changing
Enable before the policy boundary. Once provider work has ended and
`acceptingOutput` is durable, policy cutover may proceed only through this exact
delivery relation. It first makes a matching unresolved History marker terminal
with the committed newer-policy receipt, or clears the operation from exact
retry-delivery absence. A later bounded pass moves the terminal-success row to
its tombstone. It never applies generic process-lost cancellation to
`acceptingOutput`, repeats provider work, or advances policy generation again.

A release that writes `retryOperation` is no-downgrade to a binary that does
not enforce this delivery protection. Downgrade cannot be used as a cleanup or
recovery path.

Standalone lifecycle recovery may drain one exact `acceptingOutput` relation
through its bounded provider-free delivery, History, and row-to-tombstone
steps in one call. It never processes a second failed row, unlinks audio, or
starts provider work. It returns pending without storage mutation while any
policy-cutover owner is retained; the owning cutover path alone may advance
that phase. A durably confirmed policy no-op releases its cutover ownership
without touching retry bytes, so a later standalone lifecycle pass can recover
the retry under the unchanged generation. Policy cutover keeps its stricter
existing bound: each call performs at most one durable failed-domain action and
a later call continues under the already committed policy generation. Either
entrypoint returns pending whenever exact progress cannot be proved.

A relaunch reservation may be rebound to a new root-gate lease only with the
exact same policy state or a strictly newer policy generation. A different
enabled value at the same generation and every lower generation fail closed.
Before a state-changing Clear, Disable, or Enable commits N+1, the coordinator
strictly validates the failed root against the captured N receipt. A row or
tombstone that already claims N+1 is preserved and rejects the command before
either policy or failed bytes change; it is never reinterpreted as current work
merely because the command would advance to that generation.

Usage bookkeeping remains independent. After successful audio transcription,
the coordinator makes one idempotent recording attempt under the retry's
`transcriptionID`; a duplicate is success. Translation consumes only the
transient transcription and commits only its final translated text. A Usage
storage error is non-authoritative: it cannot change the failed row, turn a
successful provider result into failure, block Translation or accepted output,
or cause provider replay. C4.4 adds no Usage retry queue. Clear History never
clears Usage.

### C4.4 Checkpoint Slices

The explicit Retry checkpoint is split without weakening any intermediate
boundary:

1. **C4.4A — reservation and live ownership:** durable `reserved` and
   `providerDispatched` mutations, free-tombstone admission, stable root-shared
   live-owner epochs, Pending-provider exclusion, one-shot dispatch, and exact
   cancellation;
2. **C4.4B — provider outcomes:** descriptor-backed Transcription, fail-open
   correction plus one local post-processing pass, transient strict
   Translation, timeout and error mapping, retry-count idempotency, late-result
   rejection, and non-authoritative Usage recording;
3. **C4.4C — accepted-output handoff:** `acceptingOutput`, frozen predecessor,
   failed/delivery interlock on every delivery mutation, exact Retry acceptance,
   terminal History provenance, and row-to-tombstone success;
4. **C4.4D — recovery and integration:** process loss in every durable state,
   wholly unrelated predecessor versus partial collision, policy-cutover
   continuation, retained uncertainty, relaunch tests, and full regression
   evidence for the internal recovery boundary. C4.5 repeats the regression
   after lifecycle and public-boundary integration and owns the final C4
   verdict.

### C4.5 Containing-App Boundary

C4.5 exposes one containing-app-only facade over the completed failed-History
store. Its failed-row identifier is opaque and non-Codable. A read returns
either a bounded current-generation list or `pendingLocalRecovery`; it never
turns corrupt, future, unavailable, conflicted, uncertain, or unresolved
logical Retry/policy state into an optimistic empty list. Post-policy physical
cleanup may remain pending while the already committed logical read is empty,
as required by the Clear and Disable contract. That exception requires a
retained post-boundary cutover receipt whose owner and logical state match the
freshly confirmed durable policy, a valid failed journal with no unresolved
row ownership, and no current-generation row; old-generation audio is not
presented as usable while
that exact cleanup continues. Each item contains only its
opaque row ID, compact failure category and pipeline stage, retry count, output
intent, model, optional language, creation and update dates, duration, and a
coarse audio-availability value. A non-empty `available` result is reported
only after the app-private protected-audio namespace passes its bounded
structural check. Outside the proved post-policy logical-empty exception, an
unresolved audio check makes the whole read pending rather than guessing which
file is usable. The model does not prove provider readiness and Retry repeats
the exact descriptor-backed media validation.

Delete accepts only an opaque identifier previously issued by this facade.
Its public result is `complete` or `pendingLocalRecovery`; it exposes no
tombstone, path, receipt, revision, or cleanup capability. `complete` includes
an already unavailable row and the durable row-to-tombstone success boundary.
Post-boundary cleanup trouble remains provider-free pending work and never
resurrects the item.

Explicit Retry is exposed only by a process-owned containing-app service whose
session factory resolves individually durable Settings and Library snapshots
through the exact composition-owned state owners, then resolves the requested
output intent and the app's canonical credential coordinator before the first
durable Retry write. It waits behind an in-flight owner mutation, consumes the
new canonical value only after successful save, and falls back to the previous
durable value after a failed save. It does not claim cross-file atomicity for
the independently durable Settings and Library pair. The action accepts no
caller-provided
`credentialEligible` flag, path, row, configuration snapshot, or provider
capability. A ready session binds one transient resolved credential to a fixed
provider adapter and the validated current configuration; it is non-Codable,
redacted, and cannot be reconstructed from failed-row storage. Standard Retry
passes no Translation configuration. Translation Retry requires a currently
valid Translation route. Both compose the current prompt with no Nearby Text,
freeze current correction and local-processing inputs, and force automatic
insertion off.

Within the failed-History action surface, only row DTOs and redacted
load/Delete/Retry results are ordinary public API. The separate lifecycle
opportunity and complete-or-pending result are also ordinary public,
payload-free values. The configuration, ready session, provider protocol,
request and text outcome, injectable factory seam, and Persistence facade
initializer are restricted to the IOSCore integration SPI and are absent from
the ordinary public symbol graph. IOSCore exposes one fixed process-owned
service; its production constructor is integration SPI rather than an ordinary
view/scene API. App code outside the composition root cannot construct another
service or supply its own readiness flag, configuration, provider, credential
generation, or session.

Transcription Retry creates its one legacy URL-based provider copy only inside
the dedicated `holdtype-ios-failed-history-retry-v1` temporary namespace. The
namespace is owner-only and exactly marked. Before the first non-empty audio
write, the same open file descriptor must prove mode `0600`, Complete file
protection, backup exclusion, the exact retry-audio marker, a single link, and
an exclusive advisory lock. The provider copy stays locked through the request;
normal and cancellation cleanup retain the directory and file descriptors and
remove only when the final descriptor and path identities still match. A
replacement, symlink, hard link, changed mode, marker, protection, size, or
identity fails closed and is preserved. Darwin has no compare-and-unlink
primitive, so the descriptor and path are rechecked immediately before the
descriptor-relative `unlinkat`; no caller receives this narrow cleanup
authority.

Containing-app startup schedules one provider-free, process-once orphan pass;
the keyboard never schedules or links it. The pass does not create or repair a
missing, symlinked, unmarked, or invalid namespace. It inspects at most 128
entries, removes at most 16 files, accounts at most 200 MB, runs for less than
500 ms, and accepts only an exact marked retry filename at least one hour old,
smaller than the provider limit, owner-only, single-linked, unchanged, and not
locked by a live request. Young, active, malformed, unknown, unmarked, linked,
foreign, or raced entries are preserved. It never scans or removes a durable
PendingRecording or failed-History source recording.

The public Retry result is limited to accepted, recoverable failure,
cancelled, setup required with its semantic owning destination, unavailable,
or pending local recovery. It carries no transcript, credential, provider
payload, status code, path, durable identifier, receipt, or capability.
Missing or invalid setup returns before reservation and leaves the row and
retry count unchanged. Cancellation after reservation uses the existing exact
retirement path; late provider output remains unauthorized. Accepted output
enters the normal accepted-output recovery path and is never inserted into an
arbitrary field by this service. Cancellation before any reservation returns
`cancelled` and leaves the row and retry count unchanged. Once exact Retry
success is committed, a later History-policy `cancelled` or `notRequested`
outcome still reports public Retry `accepted`; public `cancelled` is reserved
for user/task cancellation. A credential rejection at Transcription,
Correction, or Translation records only the exact resolved process credential
generation; the next preflight routes to OpenAI setup, while a late rejection
from an older generation cannot poison a replacement key.

The containing app owns one lifecycle-recovery scheduler for the whole
process, not one per scene or view. App construction schedules one launch
opportunity before History, pending-recording, or delivery consumers may
operate. The initial SwiftUI `active` observation is part of that launch and
does not schedule a duplicate pass. A later genuine inactive/background to
active transition schedules at most one foreground opportunity. Concurrent or
multi-scene notifications coalesce while a pass is in flight. A pending launch
opportunity remains classified as launch work on a later lifecycle trigger
until it completes.

Each lifecycle opportunity is bounded and provider-free:

1. on launch with no retained History-policy cutover, run one strict
   standalone failed-Retry cold scan and stop if it performs or retains work;
   a retained cutover bypasses this standalone scan so its owning cleanup can
   resume;
2. on launch only, check whether the one process-lost
   `PendingRecording.outputDelivery` has an exact non-discarded ordinary
   accepted destination, and retire that Pending audio and journal through the
   shared physical-root-bound evidence path before any generic expiry or discard
   can remove the proof; completion requires separate directory-durable absence
   evidence for both artifacts and never treats unlink success or `ENOENT` alone
   as retirement;
3. run one canonical History-policy cleanup pass; that pass owns or resumes
   any retained cutover and performs its embedded strict failed-Retry scan,
   while preserving the existing one-failed-action bound;
4. stop immediately on pending, corruption, unavailable protected data,
   retained ownership, or uncertainty;
5. after History cleanup is complete, run one accepted-output/History recovery
   pass and stop if it remains pending;
6. on a launch opportunity only, observe any remaining PendingRecording slot
   and convert one process-lost provider phase to explicit recovery; ordinary
   foreground opportunities never manufacture process-loss authority.

There is no automatic second pass, timer, polling loop, detached task,
`BGTaskScheduler` job, or promise of background completion. A later ordinary
lifecycle opportunity or explicit user action may try again. Passive recovery
does not read Keychain, request microphone or another permission, construct a
Retry provider session, contact OpenAI, accept new provider output, publish to
App Group, or insert text. Its public result is only `complete` or
`pendingLocalRecovery`; descriptions and reflection reveal no sub-operation or
row state.

## Coordination And Isolation

- Failed transfer, Delete, retention, cleanup, Retry, accepted-output success,
  and policy cutover share one expected production-root operation gate and
  baseline identity with the existing History coordinator. Provider requests
  run outside that gate only after their durable dispatch boundary; every
  surrounding store transition reacquires it.
- A live pending provider handoff, failed-row retry, accepted-output acceptance,
  outbox worker, policy cutover, or audio-ownership transition excludes
  conflicting work. Same-operation uncertainty may resume only its exact
  retained phase. Root-shared Pending and failed-Retry registrations enforce
  provider mutual exclusion across the outside-gate interval.
- Every delivery mutation checks the failed store for the exact
  `acceptingOutput` relation under that lease. Failed-row success cleanup and
  matching delivery proof are one coordinated transaction boundary; neither
  store may be observed and then mutated through an unrelated task.
- Capabilities and receipts are store-minted, root-bound, single-purpose,
  redacted, and non-Codable. Caller-provided rows, file lists, paths,
  generations, or deletion authorizations are never accepted as proof.
- The containing app may receive a bounded read model with the row ID, compact
  category, stage, retry count, intent, model, language, dates, duration, and
  audio availability needed by History UI. It never receives a durable absolute
  path or caller-mintable mutation authority. Mutation and cleanup results are
  payload-free. Default description, debug reflection, errors, and logs expose
  no IDs, paths, row metadata, timestamps, or persisted bytes.
- The keyboard target must retain no `HoldTypePersistence`, History, failed-row,
  audio, provider, or Keychain linkage. App Group storage contains none of this
  state.

## Invariants

- At most one durable metadata owner is canonical for a protected recording:
  pending journal, failed row, or audio-cleanup tombstone.
- Destination ownership commits before source metadata is removed.
- No recoverable audio is removed before exact durable cleanup ownership exists.
- No provider call occurs during load, policy cleanup, transfer reconciliation,
  deletion cleanup, or relaunch recovery.
- A failed-row provider call begins only after durable `providerDispatched`,
  runs outside the root gate under one stable process-local owner epoch, and
  cannot overlap a PendingRecording provider owner.
- No failed row is added while History is disabled or against an unconfirmed
  policy generation.
- Retry never reserves without capacity for its success tombstone, and a failed
  row never leaves `acceptingOutput` before matching History is terminal.
- A failed-row Retry cannot automatically insert text into an arbitrary field.
- Clear and Disable cannot restore, replay, or expose old failed work and do not
  remove settings, credentials, Usage, Latest Result, current pending work, or
  Recording Cache.
- File protection and backup exclusion are verified at every durable metadata
  and audio boundary; protected-data unavailability is not absence.

## Verification Mapping

- Test the exact path, marker, four root members, entry/tombstone shapes,
  explicit nulls, stable wire enums, limits, canonical timestamps/UUIDs,
  ordering, uniqueness, revision rules, strict JSON validation, protection,
  backup exclusion, corruption preservation, and no migration.
- Test all eligible and ineligible failure mappings without retaining status
  codes, localized errors, prompts, credentials, text, or absolute paths.
- Test transfer before and after every durable boundary, duplicate transfer,
  row-first process loss, journal-removal uncertainty, missing/changed audio,
  disabled or changed policy, root mismatch, capacity, cancellation, and a
  second actor. Include root replacement after outer prevalidation but before
  the repository opens its descriptor, and prove that the replacement root
  receives no destination bytes.
- Test sealed namespace inventory with valid row/tombstone files, the optional
  current pending file, unknown/staging/missing/duplicate entries, foreign
  roots, stale leases, and bounded scans.
- Test max-five retention, deterministic oldest selection, tombstone-full
  fallback to PendingRecording, individual Delete, exact one-file cleanup,
  already-absent audio, mismatch, uncertainty, and no cross-owner deletion.
- Extend every C3 Clear/Disable/Enable/no-op/relaunch/uncertainty test with
  failed rows, journal retirement, retry operations, tombstones, current-row
  preservation, and proof that cleanup retry never advances generation.
- Test that `pendingJournalRetirement` stays in the failed root until the
  redundant pending journal is durably absent, including cutover and process
  loss, and that no tombstone is expected to recover journal authority.
- Test Retry setup rejection, tombstone-full rejection, distinct provider/Usage
  and final-transcript identities, reservation, durable dispatch before launch,
  retry-count idempotency, and provider execution outside the root gate.
  Prove that one stable owner survives its minting lease, excludes a Pending
  provider in both directions, and that only a new idle process context permits
  process-loss cancellation.
- Test cancellation before and after launch, cancellation/completion races,
  stale-owner completion against a newer Retry, noncooperative late results,
  bounded timeout, Transcription/correction/Translation success and failure,
  unsafe correction fallback, exactly one local post-processing pass, fresh
  frozen settings and prompt composition without Nearby Text, automatic
  insertion off, preserved category and stage for cancel or unmappable
  outcomes, non-authoritative Usage failure, and no automatic provider call
  after process loss.
- Test Retry scratch protection and exact markers on the first-write file
  descriptor, lock retention, cleanup cancellation and replacement races, and
  bounded startup orphan selection. Preserve fresh, active, malformed,
  unmarked, symlinked, hard-linked, foreign, and final-check-changed entries.
- Test that a matching `acceptingOutput` delivery blocks replacement, Clear
  Latest, expiry, bridge publication, and every other generic delivery mutation
  across process loss. Cover a missing slot, a wholly unrelated frozen
  predecessor, every partial identity collision, and failed-store corruption or
  uncertainty. Prove that ordinary `pending` gains absent-row replay authority
  only from the exact durable failed relation, the failed row survives until a
  terminal History marker, and exact success cleanup releases the interlock.
- Run strict-concurrency package tests, the full macOS suite, iOS simulator
  build/tests, public symbol-graph review, and keyboard binary linkage checks.
  Signed-device QA owns effective Complete protection while locked and actual
  force-quit/process-eviction evidence.

## Unknowns Requiring Confirmation

None for the bounded failed-History foundation. Recording Cache, UI polish,
and physical-device gates remain in their named roadmap milestones.
