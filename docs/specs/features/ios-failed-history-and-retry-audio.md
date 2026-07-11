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
  active, and current settings and credentials can run its output intent.
- Missing or invalid current setup routes to the owning Settings section
  without changing the row or retry count.
- Retry preserves `.standard` or `.translate`. Translation retries use the
  current valid translation configuration and never publish the intermediate
  transcription as the requested result.
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
and every coordinator over that store must reuse it. A live retry registers one
exact store-minted token under an active root lease; a delayed completion from
an older lease cannot clear a newer registration for the same durable retry.
Cutover may prove process loss only by atomically moving that canonical state
from idle to one exact cancellation reservation. While reserved, no retry may
become live. The reservation is consumed only by a store-minted completion
after the exact `retryOperation = null` outcome is durably confirmed; commit
uncertainty retains the reservation. Foreign owner states are rejected, while
an inactive exact lease cannot wedge cleanup indefinitely.

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
- `state`

Its stable states are `reserved`, `providerDispatched`, and
`acceptingOutput`. The operation contains no credential, prompt, accepted text,
translation text, provider payload, or host-field identity. The row's model and
language update to the fresh configuration captured for this retry before
dispatch; Translation-specific current configuration remains transient because
provider work never resumes automatically after process loss.

The retry count advances exactly once when a valid new operation is durably
reserved. The store then mints one process-local, cancellable provider handoff
for the exact operation. Re-entry cannot obtain a second handoff. Cancellation
retires that authority before the row becomes retryable again and wins over a
late response.

On a recoverable failure, the same root mutation clears `retryOperation`, keeps
the audio, and records the mapped category and actual failed stage. A setup
failure before reservation changes nothing. A nonrecoverable or unmappable
runtime outcome clears the operation and retains the row's previous durable
category rather than inventing one. Current audio and setup validation still
govern whether another explicit Retry is available; Delete follows the normal
local cleanup contract.

On process loss, lifecycle recovery never resumes `reserved` or
`providerDispatched` work. It cancels the durable operation locally and keeps
the row available for a new explicit Retry with new identities. For
`acceptingOutput`, recovery first checks the exact accepted-output delivery
identity: a matching durable delivery authorizes success cleanup; absence keeps
the failed row and clears the interrupted operation; unrelated, corrupt, or
unavailable delivery state fails closed.

After the requested Transcription or Translation produces accepted text, the
coordinator sets `acceptingOutput` and commits that text through the existing
accepted-output/accepted-History coordinator using the preallocated identities,
the row's output intent, automatic insertion disabled, and the current
Keep Latest Result preference. Delivery commit is the provider-replay boundary.
Only a matching durable delivery receipt may atomically move the failed row to
audio cleanup. Accepted-output uncertainty is resumed or confirmed with the
same preparation in process; it never triggers a second provider request.

The durable `acceptingOutput` relation protects a matching committed delivery
until that row-to-tombstone transition finishes. Under the shared root gate,
delivery replacement, explicit clear, expiry removal, bridge publication, and
any other mutation that could remove or supersede the matching record must
first prove from the failed store that no such relation exists, or consume the
exact delivery receipt while retiring the failed row. Caller assertions and
process-local reservations are insufficient. If the failed store is corrupt,
unavailable, foreign, or uncertain, the matching delivery remains protected
and later accepted output fails closed rather than losing the only durable
success proof. After process loss, a matching delivery therefore still proves
success; confirmed absence is safe only because every compatible removal path
enforces this interlock.

A release that writes `retryOperation` is no-downgrade to a binary that does
not enforce this delivery protection. Downgrade cannot be used as a cleanup or
recovery path.

Usage bookkeeping remains independent. A successful audio transcription is
recorded once under its retry `transcriptionID` even if Translation or later
accepted-output work fails. Clear History never clears Usage.

## Coordination And Isolation

- Failed transfer, Delete, retention, cleanup, Retry, accepted-output success,
  and policy cutover share one expected production-root operation gate and
  baseline identity with the existing History coordinator.
- A live pending provider handoff, failed-row retry, accepted-output acceptance,
  outbox worker, policy cutover, or audio-ownership transition excludes
  conflicting work. Same-operation uncertainty may resume only its exact
  retained phase.
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
- No failed row is added while History is disabled or against an unconfirmed
  policy generation.
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
- Test Retry setup rejection, reservation, one-shot dispatch, retry-count
  idempotency, cancellation before and after launch, noncooperative late
  results, Transcription and Translation success/failure, fresh settings,
  automatic insertion off, accepted-delivery uncertainty, exact success
  cleanup, process loss in each durable state, and no automatic provider call.
- Test that a matching `acceptingOutput` delivery blocks replacement, Clear
  Latest, expiry, bridge publication, and every other removal path across
  process loss; exact success cleanup releases the interlock, while failed-store
  corruption or uncertainty preserves the delivery.
- Run strict-concurrency package tests, the full macOS suite, iOS simulator
  build/tests, public symbol-graph review, and keyboard binary linkage checks.
  Signed-device QA owns effective Complete protection while locked and actual
  force-quit/process-eviction evidence.

## Unknowns Requiring Confirmation

None for the bounded failed-History foundation. Recording Cache, UI polish,
and physical-device gates remain in their named roadmap milestones.
