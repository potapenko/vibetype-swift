# iOS Accepted History Foundation

## Goal

Keep accepted iOS History durable without allowing Clear History, disabling
History, process loss, or an uncertain local commit to resurrect an old row or
repeat provider work.

This spec is the target contract for the app-private History policy,
accepted-History repository, accepted-History outbox, and their coordination
with the existing accepted-output delivery record. The C2 checkpoint implements
the contract through strict one-head FIFO recovery and terminal-proof
protection. Global policy cutover and stale-generation cleanup remain the next
checkpoint, and the full user-facing controls remain deferred as described
below.

## Scope And Deferred Work

In scope are the exact version-1 policy, accepted-row, and outbox records;
policy-generation cutover and retention; pending History transfer from delivery
to outbox; and strict CAS, commit uncertainty, expiry, privacy, and migration.

Failed History, retry-only audio, Recording Cache, History UI, and production
keyboard publication are deferred. The full user-visible Clear History and
History toggle must not be wired until failed History and retry-audio cleanup
join this policy cutover.

## Storage Contract

The only version-1 Application Support paths are:

- policy: `HoldType/ios-history-policy.json`;
- accepted rows: `HoldType/ios-accepted-history.json`;
- outbox: `HoldType/ios-accepted-history-outbox.json`.

Their exact create-only markers and encoded limits are:

| Record | Marker value | Maximum bytes |
| --- | --- | ---: |
| Policy | `com.holdtype.ios.history-policy = v1` | 16,384 |
| Accepted | `com.holdtype.ios.accepted-history = v1` | 4,194,304 |
| Outbox | `com.holdtype.ios.accepted-history-outbox = v1` | 4,194,304 |

All are containing-app-only. The `HoldType` directory is owner-only `0700`;
final and staging files are owned one-link regular files, mode `0600`, Complete
protected, backup-excluded, and opened without following links. They never
enter UserDefaults, App Group, iCloud, clipboard, state restoration, widgets,
Spotlight, notifications, or diagnostics export.

The three records use the same strict atomic boundary as the accepted-output
delivery record: protected staging before the first content byte, bounded I/O,
file sync, atomic publication, post-publication identity/configuration checks,
and directory sync. Pre-publication failure preserves the old value. A visible
publication followed by failed validation or sync is `commitUncertain`; retry
must reread and identically rewrite the intended bytes before returning
authority. All mutations use logical revision plus physical file revision CAS.

## History Policy V1

The root object contains exactly `schemaVersion`, `revision`, `historyEnabled`,
and `policyGeneration`.

Schema version is integer `1`; enabled is a JSON Boolean; revision and
generation are equal signed 64-bit integers in `1...Int64.max`.

A missing policy is the virtual baseline `revision: 1`,
`historyEnabled: true`, `policyGeneration: 1` only after the single app
coordinator proves in one serialized observation that accepted History and the
outbox are missing or valid and empty, and the current delivery is missing or
has `historyWrite: null`.

Corrupt, future, unavailable, uncertain, substituted, or non-empty state is not
baseline evidence and fails closed. A scene-local repository or independent
missing-path read cannot issue baseline authority. The baseline may remain
virtual only for read-only presentation. Before issuing the first policy
capture or any generation-1 authority, the coordinator physically creates and
confirms `1/1`. Its first semantic mutation then writes physical
revision/generation `2/2`.

Policy mutations are exact:

- Clear always increments revision and generation while preserving enabled;
- Disable changes true to false and increments both; repeated Disable is no-op;
- Enable changes false to true and increments both; repeated Enable is no-op;
- re-enable starts a new logical generation and never restores old rows;
- overflow fails before writing or cleanup.

Commit uncertainty authorizes no cleanup. The intended policy must first be
confirmed by an identical durable rewrite.

## Accepted History V1

The root contains exactly `schemaVersion`, `revision`, and `entries`. Schema
version is integer `1`; revision is signed `Int64` in `1...Int64.max`; a new
envelope starts at revision `1`; an empty created envelope is retained. Entries
are an array of at most 20 rows. A logical mutation increments revision exactly
once. Duplicate confirmation changes no logical revision, and overflow fails
before pruning or writing.

Each row contains exactly `deliveryID`, `transcriptID`, `acceptedText`,
`outputIntent`, `createdAt`, `policyGeneration`, `transcriptionModel`,
`transcriptionLanguageCode`, `durationMilliseconds`, and
`cachedAudioRelativeIdentifier`.

Delivery ID is the row/upsert identity. Delivery and transcript IDs are
lowercase canonical UUIDs. Session ID, attempt ID, delivery expiry, host, and
source-document identity are excluded.

Text, intent, timestamp, generation, model, language, and duration use the exact
accepted-delivery rules: text is byte-preserved and at most 131,072 UTF-8 bytes;
model is non-empty and at most 256 bytes; language is null or two/three lowercase
ASCII letters; duration is null or `1..<300_000`; intent is `standard` or
`translate`; dates are canonical UTC milliseconds.

`cachedAudioRelativeIdentifier` is null on creation. The cache checkpoint may
later move it only `null -> value`; it never returns to null or changes value.
A value is a non-absolute app-private relative identifier of at most 512 UTF-8
bytes with no empty, `.`, `..`, leading/trailing slash, backslash, or NUL
component. This checkpoint performs no cache attachment.

Rows are newest-first by `createdAt` descending, then `deliveryID` ascending.
Before pruning, the whole source is checked for collisions:

- same delivery ID plus identical immutable bytes is idempotent and preserves
  an existing cache link;
- same delivery ID plus different immutable bytes is a collision;
- the same transcript ID under another delivery ID is a collision.

Immutable identity is all nine non-cache row fields. Text and model identity is
their exact UTF-8 byte sequence, not Swift canonical String equality. An exact
duplicate confirms the current envelope without pruning unrelated stale rows.

Only after duplicate/collision checks may one atomic mutation remove stale
generations, insert and sort the candidate, then evict deterministic oldest
rows until both the 20-row and canonical encoded 4-MiB limits hold. Duplicate
upsert never evicts.
If the candidate is itself evicted and the final membership is byte-identical
to the source, that is a retention confirmation rather than a logical mutation:
revision is unchanged and the exact envelope receives an identical durability
rewrite.
The durable row receipt records the final retention decision; only a receipt
that proves exact row membership is accepted-row proof for delivery removal.
A matching `.retained` or `.notRetained` receipt proves that the local History
decision itself is durable and may finish the delivery marker. A
`.notRetained` decision is never row-ownership proof and cannot stand in for an
outbox transfer when active pending delivery bytes are removed.

Individual Delete uses revision CAS, does not advance policy generation, and
never deletes an independently retained cache file. Before deleting, the
coordinator proves that no matching pending delivery marker or outbox membership
can recreate the row. If either owner exists, Delete is unavailable until it is
committed, cancelled, transferred, or otherwise reconciled.

## Accepted History Outbox V1

The root contains exactly `schemaVersion`, `revision`, and `entries`. Revision
is signed `Int64` in `1...Int64.max`; a new envelope starts at revision `1`; an
empty created envelope is retained. A logical membership mutation increments
revision exactly once. Identical confirmation changes no logical revision, and
overflow fails before pruning or writing.

Each entry contains exactly `deliveryID`, `transcriptID`, `acceptedText`,
`outputIntent`, `createdAt`, `expiresAt`, `policyGeneration`,
`transcriptionModel`, `transcriptionLanguageCode`, and
`durationMilliseconds`, using the same rules as the delivery and accepted row.

Expiry is immutable and exactly 86,400 seconds after creation. Eligibility is
`createdAt <= now < expiresAt`; the entry is expired exactly at `expiresAt`.
Clock rollback before creation is ambiguous and preserves the entry while
blocking upsert and cleanup; a forward jump may expire it early.
Rollback and expiry do not prevent exact existing membership from being
recovered by identity validation plus an identical durability rewrite; that
confirmation neither inserts nor removes an entry.
An observation is snapshot-bound read authority, not direct accepted-row
upsert authority. The worker first obtains an outbox receipt through identical
membership confirmation, then uses that sealed receipt for the accepted-row
decision.

Entries are oldest-first by `createdAt` ascending, then `deliveryID` ascending.
The outbox has at most 20 total entries and 4 MiB. Collision checks precede
pruning. Delivery and transcript collision semantics are the same as accepted
History. Exact duplicate transfer is idempotent, performs no unrelated pruning,
and confirms the unchanged envelope. Expired or durably stale-generation
entries may be pruned; a live entry is never evicted to admit a 21st entry or
satisfy the byte cap. If allowed pruning is insufficient, capacity failure
preserves the entire source rather than committing partial cleanup.

Membership is the only persisted outbox state; no entry-state field and no new
delivery enum case are added. Confirmed transfer moves absent to pending
membership. A durable row decision removes pending membership; durable policy
invalidation or expiry removes it without upsert.

Every transition is revision CAS. Identical membership confirmation increments
no logical revision but performs the strict durability rewrite.

## Strict JSON Safety

All records require UTF-8 JSON without BOM, duplicate/unknown/missing keys,
numeric aliases, omitted nullable fields, non-canonical values, or unsupported
enums. Nullable values are explicit null. Public values are non-Codable.

The initial schema-dispatch safety pass uses bounded headroom so an ordinary
future schema remains a typed unsupported version before the v1 allowlists are
applied:

| Record | Depth | Members/object | Total members | Array elements | Total values |
| --- | ---: | ---: | ---: | ---: | ---: |
| Policy | 1 | 16 | 16 | 0 | 17 |
| Accepted | 3 | 32 | 512 | 32 | 600 |
| Outbox | 3 | 32 | 512 | 32 | 600 |

Decoded keys are at most 64 UTF-8 bytes and number tokens at most 20 bytes.
Decoded value strings are at most 131,072 UTF-8 bytes. After schema version `1`
is confirmed, exact policy shape is four root fields; exact accepted/outbox
shape is three root fields, at most 20 entries, and ten fields per entry. Arrays
are allowed only at root `entries`. Bounded structural validation occurs before
schema-specific decoding. Malformed, oversized, wrongly marked, corrupt, or
future bytes are preserved and block defaults, overwrite, migration, and
cleanup. Protected-data unavailability is temporary, never absence.

## Coordinator, Receipts, And Ordering

One containing-app coordinator serializes policy, accepted, outbox, and delivery
operations. Repositories never coordinate themselves. Raw policy, accepted,
outbox, and delivery stores are coordinator-owned.
Production assembly cannot construct duplicate owners for one Application
Support root; internal constructors are test and injection seams only.
If previously distinct lexical or physical roots converge, every involved
coordinator context fails closed before repository I/O; no owner is selected
silently. A registered capture requires an existing physical Application
Support root and revalidates the same resolved-path and file-identity binding
before returning authority. A binding change during the transaction returns no
capture. This inherits the app-private stable-namespace assumption; hostile
same-user namespace interposition is outside this foundation contract.

The coordinator issues opaque, process-local, non-Codable, redacted receipts
bound to exact identity, policy generation, logical revision, and file
revision:

One opaque capability-owner identity belongs to the process context for an
Application Support root and is injected into its policy, accepted-row, outbox,
delivery, and coordinator owners. Policy, delivery, row, outbox-observation,
outbox-membership, guarded-baseline, and combined-baseline capabilities carry
that identity. Every consumer validates its own owner and every input owner
before uncertainty, time, or journal I/O. Byte-identical capabilities from a
different root are therefore rejected with zero storage work. Standalone test
or injection stores default to distinct owners; an injected coordinator with a
mixed owner graph is permanently repository-conflicted before capture or
acceptance. Same-root aliases share one process context and owner. Records,
expectations, and journal mutation tokens are not capabilities and carry no
owner identity.

Within one app process, coordinator transactions use a FIFO, non-reentrant gate
across suspension points. Cancellation before acquisition performs no
transaction work; after acquisition, success, failure, or caller cancellation
cannot release the gate before that transaction finishes exactly once.

- policy receipt: current enabled generation or durable invalidation;
- row receipt: durable accepted-row retention decision and optional membership;
  the replacement-only prepared-not-retained variant is not independently
  durable and proves a decision only for the exact `pendingReplacement`
  delivery whose terminal marker will seal it;
- outbox receipt: exact durable membership of one reconstructible entry.

An outbox receipt obtained from transfer or delivery-based confirmation remains
bound to that exact delivery authorization and physical delivery revision. It
may prove ownership before removing that delivery. A receipt recovered only
from an outbox observation remains sufficient for outbox-to-row worker recovery
but cannot authorize delivery removal.

Before acceptance, the coordinator captures the current policy into an opaque
value. Only an enabled capture creates `historyWrite: pending` and supplies its
generation; callers cannot choose a generation or construct a pending marker
from a Boolean. The coordinator revalidates that generation after the delivery
commit. A cutover during acceptance cancels the stale marker and never upserts a
row.

Normal acceptance accepts only a preparation carrying the exact opaque capture
that created its marker. A raw or capture-less preparation is not a production
input. Each capture is also bound to the opaque process context for its
Application Support root; another root rejects it before delivery I/O. Its
public redacted result carries the durable accepted-delivery record and exactly
one of four History resolutions:
`notRequested`, `committed`, `cancelled`, and `pendingLocalRecovery`.
Owner validation runs inside the FIFO transaction after repository-binding
prevalidation and before delivery I/O.

Durable delivery acceptance is the provider-replay boundary. A delivery failure
before that boundary remains a typed thrown error. Once delivery acceptance is
durably confirmed, policy, row, marker, protection, CAS, expiry, or local-read
failure returns `pendingLocalRecovery`; provider work is never repeated. The
one process context for an Application Support root retains the exact delivery
authorization, confirmed policy receipt, row receipt, or invalidation receipt
for the current phase. A commit-uncertain retry uses those byte- and
physical-revision-identical capabilities and cannot reauthorize or reconstruct
them from caller data.
The shared phase is consulted before another delivery load or acceptance. An
exact same-preparation retry resumes it; different work cannot replace it.
After the second policy confirmation succeeds, a distinct pre-marker phase
retains the exact delivery authorization and row receipt, so an uncertain
marker commit retries that operation without another policy branch.

Delivery acceptance also seals whether the record was freshly committed by
the current process or was already present. That provenance survives visible
and invisible commit uncertainty. An ordinary preexisting `pending` record
always follows relaunch recovery even if a new current-owner capture
reconstructs the same IDs and bytes; it may confirm exact row membership but
never upserts an absent row. A freshly committed record may run the normal row
decision. The one deliberate exception is store-minted
`pendingReplacement`: it proves that atomic replacement committed before any
row decision, so strict relaunch recovery may run the replacement-only
`decideReplayableReplacement` decision.

Repository-binding finalization runs on success and every error. A conflict
before delivery acceptance remains thrown. A conflict discovered after the
durable delivery boundary returns `pendingLocalRecovery` with the accepted
record and preserves any exact retained phase; it never signals provider
replay. Once a recovery transaction has observed a durable delivery, later
supersession reload or read failure cannot erase that post-boundary fact.

After process loss, a receipt is recovered only by strict reload, identity
validation, and identical durability confirmation. A Boolean, stale revision,
or caller assertion is never authority.
Outbox recovery does not depend on retaining the original delivery
authorization: strict load yields an opaque snapshot-bound observation, and
confirmation succeeds only while that exact snapshot still contains the
byte-identical entry.

Delivery `historyWrite` moves either unresolved state (`pending` or
`pendingReplacement`) to `committed` only with a matching row receipt and to
`cancelled` only with a matching policy-invalidation receipt. Neither terminal
state returns to an unresolved state.

Normal accepted-History order is:

1. confirm delivery durability;
2. validate its enabled policy generation;
3. make the idempotent row decision;
4. revalidate policy;
5. commit the marker with the row receipt.

For a store-minted `pendingReplacement`, capacity rejection is a deliberately
narrow exception to the ordinary durable-row-receipt rule. The row store makes
an identical source rewrite, preserving the exact logical envelope, logical
revision, all entries, and therefore every stale row, then returns a
prepared-not-retained receipt bound to that replacement delivery. The rewrite
makes commit uncertainty observable and retryable but is not a standalone
durable retention decision. Only the exact
terminal delivery-marker CAS seals the not-retained outcome. Process loss
before that marker makes recovery evaluate the idempotent replacement row
decision again; process loss after the marker observes the terminal marker and
does no row work. Visible and invisible rewrite uncertainty retain the prepared
receipt mode for exact same-process retry.

If policy changes before step 5, the row is hidden and later removed; the
pending marker is cancelled with the invalidation receipt. A marker already
committed before later cutover stays terminal while its stale row is hidden.

`recoverAcceptedHistory()` is a provider-free coordinator entrypoint returning
an optional History resolution; callers cannot select its internal phase or
supply receipts. Missing delivery means no work and returns nil.
An active record is strictly loaded and identically rewritten before any local
decision. A null marker returns `notRequested`; cancelled is terminal. A
committed marker is terminal proof of a durable retained-or-not-retained row
decision after the generic delivery rewrite. For ordinary `pending`, the
coordinator may identically confirm an exact row when present, never inserts an
absent row, and exact absence remains committed. That marker under the
still-enabled matching generation confirms membership only: present membership
may finish it, while an absent row remains `pendingLocalRecovery` for later
outbox/worker handling. A `pendingReplacement` marker is the narrow exception:
after strict reload and identical delivery confirmation, recovery may repeat
`decideReplayableReplacement`; its idempotent retained-or-not-retained receipt
then completes the marker.
A strictly newer confirmed policy cancels a pending marker with that exact
invalidation receipt. Expired delivery is identically confirmed and removed as
bounded abandonment without row or marker work; successful removal returns nil
because no delivery remains, while removal failure returns
`pendingLocalRecovery`. Clock rollback performs no mutation and returns
`pendingLocalRecovery`. Process-retained fresh acceptance phase may resume its
exact ordinary row decision; relaunched recovery may run only the distinct
replacement decision for `pendingReplacement`.
Retained row or marker uncertainty is replayed with its exact capability before
expiry or rollback branching. A visible intended row or terminal marker may be
identically confirmed after expiry; an invisible row or marker intent is first
definitively cleared, then bounded delivery abandonment may run.
Before abandonment confirmation, the coordinator stores a sealed observation
that the exact delivery was expired and bridge-revoked. Its confirmation and
the resulting exact physical removal authorization never resample time or
return to row, policy, or marker work. Absent is success; the same logical
record at another physical revision is identically reconfirmed before removal;
a genuinely different current delivery supersedes the old authorization and is
reloaded without deletion. Read, protection, confirmation, and removal
uncertainty retain only this removal phase, including across later rollback.
Both expiry-sealed values additionally carry the opaque identity of their
issuing delivery-store instance;
another Application Support root rejects even byte-identical copied delivery
state before journal I/O. Same-root aliases share the one process store owner.

If expiry is reached after normal delivery acceptance crossed the replay
boundary, that call returns `pendingLocalRecovery` with its accepted delivery
record even when bounded abandonment succeeds; a later recovery observes no
remaining delivery and returns nil. Expiry never reports a cancelled marker.

Before clear/replacement can remove a pending marker, transfer commits the exact
outbox entry first. Delivery removal requires opaque proof of exact outbox
membership or exact accepted-row membership. Failed/uncertain transfer leaves
delivery unchanged with `historyTransferRequired`. Duplicate ownership in
delivery and outbox after a crash is idempotent.
Replacement is part of normal coordinator acceptance rather than a public raw
store flow. It first finishes any retained row, marker, or expiry work, then
confirms the old delivery, confirms the current policy, and either transfers an
enabled current-generation payload or cancels a stale marker with a strictly
newer policy receipt. For the matching branch, the delivery store mints an
opaque process-local reservation after policy confirmation and before the first
outbox read or write. It is bound to the exact authorization, physical
revision, capability owner, issuing delivery-store identity, policy generation,
and a monotonic deadline derived while that delivery is active. Production
assembly injects the same delivery-store identity into the paired outbox; a
mismatched delivery/outbox pair is a permanent coordinator conflict before
repository I/O.

The first outbox use before the deadline atomically claims the lease for that
one outbox-store identity. Another outbox store, a consumed reservation, or a
released reservation is invalid. A first claim after the deadline fails before
outbox I/O. A claim made while live may retry after the deadline only to confirm
an already-visible exact transfer; if the intended transfer is invisible, its
uncertain intent is cleared and the attempt expires. The atomic replacement
consumes the claimed reservation together with the exact outbox receipt;
definitive pre-replacement expiry or conflict releases it. Once minted, the
transfer reservation supersedes the policy receipt for the transfer and
replacement phases; those phases do not retain the policy receipt as separate
authority.

C1 also provides a mutually exclusive in-memory bridge-publication reservation
from the same delivery-store actor. It requires the exact owner-bound delivery
authorization produced by the mandatory identical durability-confirmation
rewrite, not an expectation or caller assertion. If that bridge reservation
already exists, transfer reservation fails before outbox mutation; if transfer
reservation wins first, bridge reservation fails closed. C1 performs neither
the generation `0 -> 1` commit nor the App Group write. P6 must consume the
exact bridge reservation inside that actual ordered publication flow rather
than treating it as a caller-side preflight. Either active reservation freezes
the authorized delivery snapshot and blocks every non-consuming delivery
mutation, including a History terminal transition, before delivery-journal
I/O. The newly committed delivery carries store-minted `pendingReplacement`,
so its normal row decision survives a crash even when the replacement rename
became visible before the caller observed it.

Transfer and replacement uncertainty retain the owner-bound exact preparation,
authorization, reservation, outbox receipt when already obtained, and physical
revisions in the root process context. The policy receipt is retained only
before reservation mint; after mint the reservation supersedes it. Every
retained phase validates its work, capture, and capability owner before storage
I/O; invalid injected work is cleared fail-closed. Different accepted work
cannot take over that phase.
Provider-free recovery may finish it. After process loss, the coordinator
re-authorizes the old delivery and identically confirms duplicate outbox
membership before replacing it; IDs or caller assertions are never proof. If
the replacement itself was already visible, `pendingReplacement` reconstructs
fresh row-decision authority without the lost process state.
If the old delivery reaches expiry before replacement, the coordinator returns
to ordinary atomic acceptance, which replaces the expired slot without an
unlink/create gap and without creating a new outbox entry. A transfer already
confirmed before expiry remains harmless stale/expired outbox work for the
worker. All failures before the new delivery commit remain typed local errors;
after that durable boundary, existing pending-local-recovery semantics apply.
For an active pending marker, that proof is checked inside the delivery store
and cannot be replaced by a Boolean or caller-side assertion. Exact delivery
expiry remains the bounded abandonment exception: expired pending work is
removed without creating or requiring a new outbox entry.

One provider-free coordinator call processes at most one store-selected outbox
head. The head is the first entry in canonical oldest-first order. The store,
not a caller-supplied index or identifier, selects it. Its observation,
identical membership-confirmation rewrite, temporal classification, retained
capabilities, and retirement remain bound to that exact snapshot, capability
owner, and outbox-store identity. Failure, rollback, uncertainty, or CAS
supersession never selects a later entry in the same call. A second head always
requires another call.
The public result is payload-free and redacted: `noWork`, `retired`, or
`pendingLocalRecovery`. It does not expose which entry, policy branch, temporal
branch, or retention decision ran. Operation-gate cancellation/reentrancy and
repository-identity conflict remain typed throws rather than being collapsed
into a result case, including when the conflict is found after a head was
retained. The worker is provider-free, so observing an existing head is not a
provider-replay boundary that may hide permanent repository poisoning.

After membership confirmation, the outbox store classifies one canonical clock
sample and issues an opaque temporal receipt. Rollback preserves the head
without policy, row, delivery, or retirement mutation. Initial expiry retires
that head without an accepted-row decision. A live classification is not
permanent insertion authority: the accepted-row store rechecks its own clock,
and expiry before an absent-row mutation returns the worker to temporal
classification. Expired retirement consumes the exact expiry receipt; an
uncertain retry does not resample time in the same process. Process loss
reconstructs classification from durable state.

A live head confirms current policy. Enabled policy at the entry generation is
matching; a strictly newer generation is invalidated. Lower generation or an
equal disabled state fails closed. Matching policy normally permits the
idempotent row decision, followed by confirmation of the exact same policy
state. A cutover discovered after the row decision changes to the invalidated
branch; the stale row may remain physically present but is hidden by generation
filtering. Invalidated work performs no new row decision.

Before repeating a matching-policy row decision, the coordinator confirms
whether the current delivery is the exact same immutable accepted payload. An
exact `committed` marker seals the earlier retained-or-not-retained outcome and
authorizes head retirement without reinterpreting current capacity. An exact
`cancelled` marker is accepted only with newer-policy invalidation. Otherwise,
after row and policy revalidation, an exact active unresolved marker is
identically rewritten and then committed with the row receipt, or cancelled
with newer-policy authority. Missing, unrelated, or already-discarded delivery
requires no marker mutation. Matching expired delivery is left for bounded
delivery abandonment; a row decision already made while live may still retire
the outbox head. Matching rollback blocks the head. A partial identity match or
any immutable payload mismatch is a collision and never degrades to
"unrelated."

For a non-discarded delivery, the exact delivery relation includes delivery and
transcript IDs, accepted-text UTF-8 bytes, output intent, creation and expiry
timestamps, policy generation, model, language, and duration. A discarded
tombstone intentionally no longer contains text or History metadata, so its
relation uses only the immutable IDs, intent, and timestamps that the tombstone
retains; a mismatch in any retained field is still a collision. IDs or caller
assertions alone are never marker authority. Terminal delivery confirmation
uses the same mandatory identical physical rewrite as other delivery recovery.
Every resulting delivery authorization is also bound to the issuing
delivery-store identity. An authorization from another actor or root cannot
commit or cancel a marker, prove a terminal relation, retire outbox work, or
mint absence authority even when its owner and logical bytes happen to match.

Processed, invalidated, and expired retirement remove only the confirmed head
with revision CAS. Row, policy, marker, and retirement commit uncertainty retain
their exact capabilities in one root-shared worker phase and retry only that
phase. A definitive CAS supersession clears the retained phase but ends the
current call before any new head selection. Process loss may repeat an unsealed
not-retained capacity decision while its outbox membership still exists; once a
matching terminal marker or outbox retirement seals that decision, recovery
must not reinterpret it. No branch repeats provider work.

The worker never starts a head while acceptance or pending replacement retains
root-scoped work. Conversely, capture, acceptance, delivery recovery, and
future policy cutover cannot bypass a retained worker phase. This prevents the
worker from consuming the exact outbox receipt that still owns a C1 replacement
and prevents another operation from invalidating a retained row, marker, or
retirement capability.

While any outbox membership still matches an active, non-expired delivery,
production replacement, Clear Latest, discard, and non-retention removal may
not erase that delivery's terminal History proof. They require an opaque absence
capability minted only after an exact missing observation or identical
outbox-snapshot rewrite. The capability is bound to the exact delivery,
capability owner, paired delivery and outbox stores, and a currently active
lease issued by their exact expected production root operation gate. It becomes
invalid before that lease is released and never survives process loss. A stale
snapshot or a capability from another root, store pair, gate, or operation is
not authority. If the delivery mutation is
commit-uncertain, a later operation confirms an already-visible intended
delivery without the old capability; if the old terminal source remains
visible, it must classify outbox absence again under its new lease. All
production outbox mutations use the same root gate. Production consumes the
absence capability immediately in that gate operation: neither the capability
nor its lease may escape to an unstructured task, and no outbox mutation may be
inserted between classification and delivery mutation. Future sequencing that
cannot preserve this ordering requires store-enforced capability revocation.
Otherwise the operation fails closed until the FIFO worker retires the matching
membership. Exact delivery expiry remains the bounded abandonment exception.
This guard is required even for an active terminal marker because not-retained
is otherwise indistinguishable from an absent row after process loss.

## Clear, Disable, Enable, And Migration

Clear or a state-changing toggle first commits policy cutover. That is logical
success: UI immediately filters by current enabled generation. Cleanup then
cancels stale pending markers and CAS-removes stale rows/outbox entries. Crash,
lock, CAS, or removal failure may leave hidden bytes for lifecycle
reconciliation; cleanup never rolls policy back or deletes current generation.

Clear/Disable do not remove Usage, settings, credentials, current provider work,
or Recording Cache. Failed rows and retry audio join later; until then the full
user-facing Clear/toggle remains unavailable.

There is no automatic import from macOS UserDefaults, macOS History, legacy
Codable rows, Phase-0 bridge data, or external files. Missing accepted/outbox
paths mean empty only when absence is proven. Their first mutation creates
revision `1`. Unsupported or legacy-shaped bytes are preserved. Any future
migration or explicit reset requires a separate spec.

## Privacy And Verification

History files contain no audio, absolute path, key, prompt, provider payload,
dictionary, surrounding text, host identity, clipboard data, or keystrokes.
Text, model, IDs, relative identifiers, paths, JSON, raw errors, values,
receipts, reflection, and debug output are redacted from default diagnostics.

Tests must cover exact paths/wire/limits; modes, protection, backup, markers and
sync failure; guarded baseline and first `2/2`; Clear/toggle/overflow races;
row ordering, collisions, retention and cache-link one-way mutation; outbox
ordering, capacity, expiry and no live eviction; every crash point in normal
write, transfer, worker and cleanup; stale receipts/two actors/process loss;
replacement capacity rejection sealed only by the exact terminal marker;
delivery-store binding, one-outbox lease claiming, consume/release revocation,
and monotonic transfer expiry; exact bridge authorization and snapshot freeze;
store-enforced one-head FIFO ordering including equal-time UUID order; no skip
on rollback, protected-data failure, corruption, CAS supersession, or
uncertainty; expiry before and after a durable row decision; policy cutover
before and after that decision; retained and not-retained recovery; crash after
a terminal marker but before retirement; terminal-delivery removal blocked by
matching outbox membership; pending, committed, cancelled, discarded, expired,
unrelated, and collision delivery relations; visible and invisible uncertainty
at every worker phase; process loss at every durable boundary; and mutual
exclusion among worker, C1 replacement, and acceptance retained phases;
corrupt/future preservation; no migration/provider replay; redaction; complete
strict-concurrency package tests; full macOS and iOS simulator suites; and no
Persistence/History linkage in the keyboard. Signed-device QA owns effective
Complete protection while locked.
