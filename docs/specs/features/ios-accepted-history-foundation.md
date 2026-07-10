# iOS Accepted History Foundation

## Goal

Keep accepted iOS History durable without allowing Clear History, disabling
History, process loss, or an uncertain local commit to resurrect an old row or
repeat provider work.

This checkpoint owns the app-private History policy, accepted-History
repository, accepted-History outbox, and their coordination with the existing
accepted-output delivery record.

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

Only after duplicate/collision checks may one atomic mutation remove stale
generations, insert and sort the candidate, then evict deterministic oldest
rows until both the 20-row and 4-MiB limits hold. Duplicate upsert never evicts.
The durable row receipt records the final retention decision; only a receipt
that proves exact row membership is accepted-row proof for delivery removal.

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

Entries are oldest-first by `createdAt` ascending, then `deliveryID` ascending.
The outbox has at most 20 total entries and 4 MiB. Collision checks precede
pruning. Exact duplicate transfer is idempotent. Expired or durably stale-
generation entries may be pruned; a live entry is never evicted to admit a 21st
entry or satisfy the byte cap.

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
operations. Repositories never coordinate themselves. It issues opaque,
process-local, non-Codable, redacted receipts bound to exact identity, policy
generation, logical revision, and file revision:

- policy receipt: current enabled generation or durable invalidation;
- row receipt: durable accepted-row retention decision and optional membership;
- outbox receipt: exact durable membership of one reconstructible entry.

Before acceptance, the coordinator captures the current policy into an opaque
value. Only an enabled capture creates `historyWrite: pending` and supplies its
generation; callers cannot choose a generation or construct a pending marker
from a Boolean. The coordinator revalidates that generation after the delivery
commit. A cutover during acceptance cancels the stale marker and never upserts a
row.

After process loss, a receipt is recovered only by strict reload, identity
validation, and identical durability confirmation. A Boolean, stale revision,
or caller assertion is never authority.

Delivery `historyWrite` moves `pending -> committed` only with a matching row
receipt and `pending -> cancelled` only with a matching policy-invalidation
receipt. Neither terminal state returns to pending.

Normal accepted-History order is:

1. confirm delivery durability;
2. validate its enabled policy generation;
3. make the idempotent row decision;
4. revalidate policy;
5. commit the marker with the row receipt.

If policy changes before step 5, the row is hidden and later removed; the
pending marker is cancelled with the invalidation receipt. A marker already
committed before later cutover stays terminal while its stale row is hidden.

Before clear/replacement can remove a pending marker, transfer commits the exact
outbox entry first. Delivery removal requires opaque proof of exact outbox
membership or exact accepted-row membership. Failed/uncertain transfer leaves
delivery unchanged with `historyTransferRequired`. Duplicate ownership in
delivery and outbox after a crash is idempotent.

The outbox worker validates policy, makes the row decision, revalidates policy,
commits a matching pending marker when present, then removes the entry. For stale
policy it cancels the marker without upsert, then removes; at expiry it removes
without upsert. Row success plus uncertain outbox removal retries only local
idempotent work, never provider work.

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
corrupt/future preservation; no migration/provider replay; redaction; complete
strict-concurrency package tests; full macOS and iOS simulator suites; and no
Persistence/History linkage in the keyboard. Signed-device QA owns effective
Complete protection while locked.
