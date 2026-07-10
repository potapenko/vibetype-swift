# iOS Accepted Output Delivery Record

## Goal

Prevent an accepted iOS transcript from being lost, repeated, or published
before its app-private recovery owner is durably committed.

This record is the containing app's crash-safe owner for the interval between
accepting final text and finishing History handoff, keyboard delivery
reconciliation, or explicit recovery. It is not the keyboard snapshot, the
History database, or an analytics event.

## Scope

This contract defines:

- the exact version-1 value and wire format;
- app-private storage, Data Protection, and durability;
- compare-and-swap mutation and replay rules;
- delivery, History, replacement, clear, and expiry ordering;
- the privacy boundary between the containing app and keyboard extension.

The production App Group bridge, extension claim ledger, History outbox, and
containing-app UI are separate checkpoints. They must consume this contract
without weakening it.

## Runtime Value And Identity

Every newly accepted result receives a fresh globally unique `deliveryID`.
`sessionID`, `attemptID`, and `transcriptID` retain their canonical upstream
identities. The four IDs are lowercase canonical UUID strings on disk.

`transcriptID` is exactly the transcription ID already committed by
`PendingRecording`. One `sessionID` may legitimately contain multiple attempts,
and one `attemptID` may legitimately receive a new transcript ID after an
explicit Retry. `deliveryID` is allocated once for one accepted
`(attemptID, transcriptID)` result and is then the stable identity used by
History, bridge snapshots, extension claims, acknowledgements, and recovery.
Reusing that delivery ID or that complete attempt/transcript pair is idempotent
only when every immutable field matches byte-for-byte. Reusing a session ID or
attempt ID by itself is not a collision.

The containing app owns a signed 64-bit `revision` in `1...Int64.max` for record
compare-and-swap and a separate signed 64-bit `publicationGeneration` in the
version-1 set `{0, 1}` for bridge publication. Both fail before overflow or an
unsupported value. A new record starts at revision `1` and publication
generation `0`. Every logical durable mutation
increments revision exactly once; an idempotent no-op or identical durability-
confirmation rewrite increments neither revision nor `updatedAt`.

Version 1 has one stable publication eligibility epoch. The first authorized
bridge publication changes generation `0` to `1` and commits it before the
snapshot. Refreshing or republishing that same still-eligible delivery retains
generation `1`; only the bridge writer revision changes. Revocation ends that
delivery's epoch permanently, so a truthful delayed generation-1
acknowledgement remains reconcilable while stale bridge bytes cannot be
republished. Version 1 never increments a delivery beyond `1`.

The delivery state is exactly one of:

- `pending`: accepted text is durable and no insertion outcome is reconciled;
- `confirmedInserted`: a matching acknowledgement verified the insertion;
- `submittedUnverified`: `insertText` was called but success could not be
  proven, so automatic replay is permanently forbidden;
- `discarded`: a logical tombstone that cannot be displayed, published,
  inserted, or restored.

Only `pending` may become either insertion outcome. Any non-discarded state may
become `discarded`. Terminal states never become `pending`. Reapplying the
identical transition is idempotent; a different terminal outcome is a typed
conflict.

Strict construction and decode reject impossible cross-field combinations.
Publication generation is only `0` or `1`; `confirmedInserted` and
`submittedUnverified` require generation `1`; and `discarded` requires null
text, false insertion preference, and null History state. History state moves
only `pending -> committed` or
`pending -> cancelled`; the mutation API rejects a stale callback that tries to
recreate pending work. Insertion terminal states are writable only by the
matching generation-1 acknowledgement transition, never by a general save API.

## Strict Version-1 Wire Contract

The root JSON object contains exactly these 16 fields:

1. `schemaVersion`
2. `revision`
3. `deliveryID`
4. `sessionID`
5. `attemptID`
6. `transcriptID`
7. `acceptedText`
8. `outputIntent`
9. `createdAt`
10. `updatedAt`
11. `expiresAt`
12. `deliveryState`
13. `automaticInsertionPreferenceEnabled`
14. `keepLatestResult`
15. `publicationGeneration`
16. `historyWrite`

`schemaVersion` is the integer `1`. `outputIntent` is `standard` or
`translate`. Booleans are JSON booleans, never numeric aliases. Optional
values are represented by explicit JSON `null`; omitted and unknown members
are invalid.

`automaticInsertionPreferenceEnabled` is exactly the acceptance-time
`OutputDeliveryPreferences.automaticInsertionPreferenceEnabled` value. It is
intent only, not target eligibility or authorization; the bridge derives its
separate `automaticInsertionAuthorized` value only after every runtime gate.

Dates use exactly four ASCII calendar-year digits, `-`, two month digits, `-`,
two day digits, `T`, two hour digits, `:`, two minute digits, `:`, two second
digits, `.`, three millisecond digits, and `Z`. They use proleptic Gregorian UTC,
year `0001...9999`, and no leap second. Implementations must not use the
week-based `YYYY` date pattern. The decoder validates schema version before
applying the version-1 key allowlist, so a future version remains a distinct
unsupported value rather than malformed version-1 data.

`acceptedText` is a non-empty string in every state except `discarded`, where
it is exactly `null`. `IOSAcceptedOutputDeliveryPreparation` is the iOS
post-processing acceptance gate. It rejects forbidden controls in the raw
candidate before trimming, then trims only this frozen edge-scalar set:
`U+0009`, `U+000A`, `U+000D`, `U+0020`, `U+00A0`, `U+1680`,
`U+2000...U+200A`, `U+2028`, `U+2029`, `U+202F`, `U+205F`, and `U+3000`.
It then constructs `AcceptedTranscript` and rejects an oversized value before
the UI declares
`resultReady` and before pending ownership can advance to output delivery. The
constructed transcript's UTF-8 bytes must equal the frozen-trim result exactly;
if Foundation would trim any additional scalar, including edge `U+200B`, the
candidate is rejected rather than silently changed. The
record, History, bridge, and insertion use the resulting UTF-8 bytes
byte-for-byte: no later Unicode normalization, case folding, newline conversion,
or lossy replacement is allowed. Swift canonical-equivalence `String` equality
is insufficient for payload identity; collision checks compare UTF-8 bytes.
Emoji, combining sequences, ZWJ, and bidirectional characters remain intact.
DEL, C1 controls, and C0 controls other than tab, line feed, and carriage return
are rejected. Whitespace-only text is rejected. The maximum is 131,072 UTF-8
bytes.

`createdAt`, `updatedAt`, and `expiresAt` are canonical UTC timestamps with
exactly millisecond precision. `createdAt` is immutable, `createdAt <=
updatedAt <= expiresAt`, and `expiresAt` is exactly 86,400 seconds after
`createdAt`. A normal real mutation uses canonical `now`, requires
`previousUpdatedAt <= now < expiresAt`, and stores that `now`. The explicit
clear exception during clock rollback retains the prior `updatedAt`; expiry
cleanup does not create another logical value. The full encoded file is at most
1,048,576 bytes.

`historyWrite` is either `null` when History was disabled at acceptance, or an
object containing exactly:

- `state`: `pending`, `committed`, or `cancelled`;
- `policyGeneration`: signed 64-bit History policy generation in
  `1...Int64.max`;
- `transcriptionModel`: trimmed non-empty resolved model name, at most 256
  UTF-8 bytes, with the same forbidden-control policy as accepted text;
- `transcriptionLanguageCode`: lowercase ASCII language code of exactly two or
  three letters, or `null`;
- `durationMilliseconds`: `null` or an integer in `1..<300_000`.

The parent record supplies delivery ID, transcript ID, accepted text, creation
time, and output intent for an idempotent accepted-History write. A Boolean
marker is forbidden because it cannot reconstruct that row after pending audio
metadata has moved or been removed. A result accepted while History is enabled
commits with `state: pending` already present; no crash gap exists between
delivery commit and History ownership. A successful idempotent History upsert
changes only state to `committed`; a stale/disabled policy changes only state to
`cancelled`. The metadata remains for accepted-result collision checks until
the whole delivery is discarded. Neither terminal state can return to pending.

All identifiers, accepted text bytes, output intent, created/expiry dates,
captured insertion preference, and History metadata are
immutable. `keepLatestResult` captures acceptance-time intent but may move only
from `true` to `false` when the live setting disables retention; it never moves
back to true for an existing delivery. That one-way CAS affects cleanup after
reconciliation without deleting an unresolved or submitted-unverified result.
An otherwise-identical acceptance replay carrying `false` applies that same
one-way revocation; a replay carrying `true` never restores a current `false`.
The captured insertion preference never grants authorization, and live settings
or runtime gates may always revoke publication. A discarded tombstone has
`acceptedText: null`, `automaticInsertionPreferenceEnabled: false`, and
`historyWrite: null`. Publication is legal only for an unexpired `pending`
delivery. Completing or cancelling History changes only its nested state. An
idempotent operation changes no bytes.

The decoder accepts only UTF-8 JSON without a byte-order mark, duplicate keys,
unknown keys, missing keys, numeric aliases, non-canonical UUIDs or dates, or
unsupported enum/schema values. It bounds bytes, members, string lengths, and
nesting before materializing the value. The initial schema-dispatch safety pass
allows nesting depth `2`, at most 32 members in one object, 64 total object
members, no arrays, at most 65 total values, decoded key length 64 UTF-8 bytes,
decoded value-string length 131,072 UTF-8 bytes, and number-token length 20
bytes. After `schemaVersion: 1` is confirmed, the exact version-1 shape is 16
root members, five History members, 21 total object members, and 22 total
values. This bounded headroom lets an ordinary future schema remain the typed
unsupported-version case before the version-1 allowlist is applied. Malformed,
oversized, and future-version source bytes are preserved and block automatic
replacement.

The public value and errors redact text and metadata from app-owned
`description`, `debugDescription`, `CustomReflectable`, logs, assertions, and
diagnostics. Raw Foundation/POSIX errors, including `NSError` URL user info, are
collapsed immediately into content-free typed categories. Text and paths never
enter `OSLog`, even with private interpolation. The persistence value is not a
general-purpose `Codable` payload; the dedicated strict codec owns its wire
contract.

## Storage And Durability

The only version-1 location is:

`<Application Support>/HoldType/ios-accepted-output-delivery.json`

It belongs only to the containing app. It is never stored in the App Group,
UserDefaults, SceneStorage, clipboard, notification payloads, widgets,
Spotlight, state restoration, or diagnostics export.

The `HoldType` directory is owner-only mode `0700`. Because older app-private
repositories may already have created that shared directory with wider mode,
the first strict writer opens it without following symlinks, verifies its
descriptor identity and effective-user ownership, tightens it to `0700`,
revalidates it, and synchronizes both directory and parent before file access.
It never chmods an unowned or substituted path. The record and every
staging file are owner-only mode `0600`, regular files with one link, opened
without following symlinks. Every creation and replacement has
`NSFileProtectionComplete`, backup exclusion, and the exact extended-attribute
marker named `com.holdtype.ios.accepted-output-delivery` with exact UTF-8 bytes
`v1`, created with create-only xattr semantics, configured and verified before
its first content byte is written. Every staging and final delivery file is
excluded from backup; the shared `HoldType` directory is not excluded because
it also owns backup-eligible settings. Replacement reapplies and revalidates
the file exclusion after rename because file operations may reset URL resource
metadata.

A successful commit requires a bounded descriptor-relative read, strict decode,
revision comparison, protected temporary creation, complete bounded write,
file synchronization, descriptor/path identity revalidation, atomic rename,
post-rename configuration revalidation, and containing-directory
synchronization. Version 1 uses bounded retry around Darwin `fsync` for file and
directory descriptors; `EINTR` is retried, while unsupported or failed barriers
fail closed. This is an observable ordering and error-detection protocol, not a
claim of absolute durability under sudden hardware power loss. A general
metadata writer whose directory synchronization is best effort does not
satisfy this contract.

Failure before rename leaves the prior record intact. Rename followed by failed
validation or directory synchronization returns `commitUncertain`; it does not
roll back or authorize History, bridge, cleanup, or provider replay. Retrying
the same logical mutation rereads the file. If the exact intended value is
visible, the store rewrites those identical bytes without changing logical
revision or timestamp and completes a successful directory sync before it
confirms durability.

Every mutation requires the expected delivery identity, record revision, and
underlying file revision read by that operation. The file revision is the exact
descriptor snapshot of device, inode, byte count, modification seconds and
nanoseconds, and status-change seconds and nanoseconds. The containing
app process uses one static mutex shared by every strict file-system instance,
and the containing directory's bounded `flock` is the additional cross-process
guard. Both are held while that revision is revalidated, through rename and
directory synchronization. The in-process mutex is mandatory because an
advisory file lock alone does not establish the required same-process actor
semantics. Thus two store actors may both read revision N, but only one can
publish N+1; the other sees a stale snapshot under the lock. Stale callbacks,
actors, clear requests, acknowledgements, and retries cannot mutate a newer
value. When that conflict reveals the exact same immutable acceptance, one
bounded reload reconciles it as an idempotent result and performs the required
identical confirmation; a different value remains a typed slot/CAS conflict or
identity collision.

The first side-effect authorization in every containing-app process performs an
identical strict rewrite and successful directory synchronization of the
currently valid value. This confirms a record that a prior process might have
made visible immediately before crashing; simple decode after relaunch cannot
authorize History or bridge work. History authority is returned only after the
post-rewrite value is revalidated as unexpired. One operation captures one
temporal-state decision for replacement and clear branching, so a later clock
sample cannot turn rollback or expiry into destructive eligibility. A corrupt,
future, protected-unavailable, or uncertain record is never interpreted as
missing. Protected-data unavailability while locked is a temporary typed
outcome and never triggers fallback protection, overwrite, or corruption
recovery.

Malformed or future bytes do not create a permanent local-data denial of
service. An explicit user-confirmed `Discard unreadable local result` operation
first publishes a content-free tombstone for the entire app-owned accepted-
result snapshot at a higher bridge writer revision, or proves that no unexpired
snapshot exists. It may then pin the exact path/file revision and remove that
opaque file without decoding it, followed by directory synchronization. Until
the production bridge can supply that proof, the operation returns
`bridgeRevocationRequired`. It cannot publish text, retry provider work, or
remove a substituted revision. A future-version value remains preserved by
default so a newer app can recover it.

Staging maintenance recognizes only
`.ios-accepted-output-delivery.json.<lowercase UUID>.tmp`. One pass inspects at
most 256 directory names, 32 exact-name candidates, 4,194,304 candidate logical
bytes, and 100 milliseconds of monotonic time. A process-local descriptor-
relative enumeration cursor is pinned to the directory device/inode and resumes
the next bounded pass after the prior 256-name window; it resets at end of
directory, identity change, missing directory, or enumeration error. A rotating
start index within each candidate window prevents the 32-candidate cap from
starving a later candidate. An oversized or unsafe candidate is preserved and
skipped rather than ending the pass. Cleanup may remove only an owner-only,
one-link regular file older than 24 hours whose descriptor/path identity is
pinned and which either has the exact delivery marker or is still zero bytes.
It never follows links, widens one pass, or removes an unknown sibling. After
the first unlink, every exit attempts the directory durability barrier before
returning or throwing.

## Commit, History, And Publication Ordering

The accepted-result sequence is:

1. commit the version-1 record in `pending` state, including a structured
   `historyWrite` object in `pending` state when History was enabled;
2. make an idempotent History upsert by `deliveryID` while that state is
   pending;
3. CAS its nested state to `committed` after that upsert is durable;
4. commit the stable version-1 publication generation `1` before creating any
   matching short-lived output projection;
5. publish a sanitized bridge snapshot no later than ten minutes from
   publication and never later than the parent record's expiry;
6. remove or transfer pending recording ownership only after its canonical
   destinations are durable.

A History failure leaves the structured pending state durable, presents a bounded
non-blocking local error, and allows output to continue. Retry performs only
the idempotent local History upsert; it never repeats transcription or other
provider work. The retry applies only while its captured policy generation is
still valid. Clear History or a later disabled generation cannot resurrect a
row.

The canonical History setting and generation live in the strict app-private
`HoldType/ios-history-policy.json` record rather than the general settings file.
Its exact version-1 root fields are `schemaVersion`, `revision`,
`historyEnabled`, and `policyGeneration`; a missing record means enabled with
both counters at `1`, and both counters remain in `1...Int64.max`. Clear
History, disabling History, and re-enabling History
each commit the next revision and policy generation; overflow fails without
changing policy. Clear or disable commits the new generation before removing
rows. Every accepted History row is tagged with its generation, and History
displays or retries only rows and markers matching the current enabled
generation. Thus a crash after the policy commit may leave physically stale
bytes, but can neither display nor resurrect them. Reconciliation then clears
old rows and outbox entries and CASes a stale delivery History state to
`cancelled` without an upsert.

The single current-delivery file is not the long-term owner of an outstanding
History retry. The version-1 outbox is the strict app-private file
`HoldType/ios-accepted-history-outbox.json`, protected and synchronized like the
delivery record, with custom marker
`com.holdtype.ios.accepted-history-outbox = v1`. Its exact root fields are
`schemaVersion`, positive `revision`, and `entries`; a newly created envelope
starts at revision `1`. Each entry contains exactly
`deliveryID`, `transcriptID`, `acceptedText`, `outputIntent`, `createdAt`,
`expiresAt`, `policyGeneration`, `transcriptionModel`,
`transcriptionLanguageCode`, and `durationMilliseconds` under the same value
rules. It keeps at most 20 unexpired entries and at most 4,194,304 encoded bytes.
Exact duplicate transfer is idempotent; same identity with different UTF-8
payload is a collision. Before adding entry 21, only expired or stale-generation
entries may be pruned. Otherwise transfer fails closed and never evicts a live
retry.

Before replacement, Clear Latest, explicit discard, or non-retention cleanup
can remove a record whose History state is pending, the app durably transfers
its metadata and reconstructible payload to the outbox with revision CAS. Until
the outbox checkpoint exists and confirms transfer, the operation returns
`historyTransferRequired` and leaves the delivery unchanged. Expiry is the
bounded exception: after the exact 24-hour deadline, the stale state may be
abandoned and must never create a later row.

No History, bridge, cleanup, or output event may use a record whose mandatory
commit is failed or uncertain.

## Acknowledgement, Clear, And Replacement

An acknowledgement contains no text. It identifies `deliveryID`, `sessionID`,
`attemptID`, `transcriptID`, publication generation, optional conservative
source-document identity, and exactly one honest insertion outcome. The app
applies it only when all immutable identities and committed eligibility epoch
match. Generation `1` remains the current epoch across snapshot refreshes, so a
delayed truthful acknowledgement is not discarded merely because bridge writer
revision advanced. Missing, stale, duplicate, or cross-delivery
acknowledgements cannot trigger another insertion or mutate the current record.

Clear, discard, cancellation, and replacement first make the matching bridge
eligibility epoch ineligible with a tombstone at a higher bridge-writer
revision while retaining delivery generation `1`. Immediately before a durable
claim, the extension rereads and validates that latest writer revision; cached
ready bytes cannot insert after Clear. When a supported read proves that no
unexpired matching snapshot exists, Clear need not wait for a redundant
tombstone. The app then CASes the private value to `discarded`, with
`acceptedText: null`, insertion preference false, and `historyWrite: null`,
and finally unlink the record and synchronize the directory. A failure at any
step preserves the more conservative recoverable or tombstoned state. During a
detected clock rollback, explicit user clear remains available and retains the
prior `updatedAt`; other mutations fail closed.

A new result never destroys the only durable accepted payload between two file
commits. The app first revokes the old bridge and transfers any pending History
write. It then atomically CAS-replaces the old bytes directly with the new
`pending` record; it does not discard/unlink and later create. Before rename the
old result remains recoverable but ineligible for automatic insertion. After
rename the new result is recoverable; until its commit is confirmed it is not
published. If the old record is already absent, normal create-only semantics
apply.

With Keep Latest Result on, a terminal record remains available until clear,
replacement, or expiry. With it off, `confirmedInserted` may be cleaned after
reconciliation and any History transfer. `submittedUnverified` remains
recoverable until explicit clear, replacement, or expiry even when Keep Latest
Result is off because automatic replay is forbidden and insertion success is
unknown.

## Expiry And Clock Safety

Eligibility is `createdAt <= now < expiresAt`; the record is expired exactly at
`expiresAt`. Reading, relaunching, publishing, or mutating never extends the
deadline. A wall-clock value earlier than `createdAt` or the last committed
`updatedAt` is a rollback ambiguity and fails closed: automatic insertion and
state mutation stop while the protected app recovery value remains available
for explicit clear or later trustworthy maintenance. Explicit clear uses the
exception above. A forward clock jump may expire the record early.

Inside one process lifetime, the store always captures a monotonic deadline
from the remaining wall interval; that deadline may further restrict
eligibility but can never extend the wall-clock deadline. After reboot or
relaunch there is no trusted-time source, so the product guarantees the
immutable wall deadline and fail-closed behavior for detected anomalies, not
proof of exactly 24 elapsed hours after arbitrary manual clock changes. A bridge
snapshot's expiry is at most the earlier of its parent expiry and ten minutes
after publication.

Logical expiry immediately disables display from this record, publication, and
insertion even if iOS has not scheduled physical cleanup. Expiry does not need a
discard mutation whose timestamp would exceed `expiresAt`: after bridge
revocation the containing app removes the exact expected file revision directly
and synchronizes the directory. Removal uncertainty authorizes no downstream
side effect; a later missing read confirms only that the already-ineligible
expired record is absent. Temporary files are cleaned at the next bounded
lifecycle opportunity.

## Privacy And Extension Isolation

The record contains no audio, API key, authorization header, prompt, provider
payload, surrounding text, host-app identity, source document identity,
clipboard state, or file-system path. Default logs contain no transcript text,
raw JSON, content hash, UUID, document identifier, or path.

The keyboard receives only a separate, short-lived, sanitized App Group
projection. It never receives the app-private file URL, History metadata,
model/language metadata, recovery paths, or 24-hour retention state. The
extension target must not link app-private persistence repositories, History
storage, provider clients, or secret storage.

The extension's separate claim ledger is keyed by `deliveryID`. It retains at
most 512 live claims for 24 hours and never evicts an unexpired claim. A 513th
live claim, corrupt ledger, unsupported version, or failed durable update
disables insertion rather than weakening the at-most-once barrier. Explicit
ledger reset is permitted only after a current bridge read proves that no
insertable snapshot exists.

The app-private recovery limit is not the keyboard insertion limit. A bridge
snapshot contains accepted text only up to 8,192 UTF-8 bytes; a larger result
remains available for app-owned Copy/Share recovery and is never inserted in
chunks. Bidirectional controls are preserved as plain text but displayed in a
directionally isolated text region, never interpolated into a formatted status,
action label, Markdown string, or format string.

Data Protection and backup exclusion reduce disclosure while locked and in
backups. They do not claim protection against a compromised containing-app
process, a privileged attacker, or execution while the device and file are
legitimately unlocked.

## Current Checkpoint Verification

Deterministic tests must cover:

- exact encode/decode keys, canonical UUID/date/enum values, duplicate and
  unknown keys, wrong types, unsupported versions, bounded depth, and exact
  text/file size limits;
- emoji, combining and bidirectional text, CR/LF/tab, forbidden controls,
  invalid UTF-8, whitespace-only text, and absence of Unicode mutation;
- legal and illegal state transitions, full identity collision, stale CAS,
  two store actors, duplicate callbacks, revision overflow, and generation
  values outside the version-1 `0...1` range;
- expiry immediately before/at/after the deadline, rollback and forward jumps,
  no sliding TTL, explicit-clear exception, and direct expired removal;
- History pending-state creation, committed/cancelled transitions, transition
  uncertainty, immutable metadata, and fail-closed `historyTransferRequired`
  behavior before the outbox checkpoint;
- atomic replacement keeps old bytes on every pre-rename failure and keeps new
  bytes visible but unauthorized on every post-rename uncertain outcome;
- first-process authorization performs the identical durability-confirmation
  rewrite after a simulated prior-process crash;
- opaque corrupt/future discard requires bridge-wide revocation proof and exact
  file revision, and refuses a substituted revision;
- staging cleanup enforces its filename, age, count, byte, time, marker/zero-byte
  and unknown-sibling boundaries;
- file mode, link/type/owner checks, symlink and hard-link substitution,
  protection/backup/marker verification, partial I/O, interruption, rename,
  post-rename validation, file sync, directory sync, and uncertain retry;
- ordering authorization evidence that failed or uncertain delivery commits
  cannot permit History, bridge, cleanup, or provider replay;
- the current checkpoint exposes no public generation `0 -> 1` transition until
  the production bridge checkpoint can commit the matching projection;
- redaction canaries through values, errors, reflection, and storage errors.

## Downstream Conformance Verification

The checkpoint owning each deferred component must add the remaining tests:

- History policy generation, idempotent upsert, outbox bounds/transfer and every
  crash point around row, policy, marker, and outbox commits;
- bridge expiry clamping, refresh with a stable eligibility epoch, revocation,
  stale writer revisions, and delayed truthful acknowledgements;
- extension at-most-once behavior for restart, eviction, claimed and
  submitted-unverified states, corrupt ledger, and 513 live claims;
- redaction canaries through app logs, diagnostics, App Group, clipboard, and
  backup eligibility.

Unit and injected-fault tests own codec, state machine, CAS, clocks, and syscall
failure classification. Simulator tests own modes, links, xattrs/resource
flags, App Group schemas, and target linkage. Physical-device QA remains
required for Data Protection under lock, Full Access transitions, App Group
delivery, real keyboard hosts, and `UITextDocumentProxy` behavior. Sudden power
loss, deterministic process eviction, and actual system-backup contents require
manual or lab evidence; ordinary XCTest and simulator runs do not certify those
platform boundaries. Directory `fsync` and the combined process-mutex/`flock`
behavior on the minimum supported signed iOS version also remain a named
physical-device gate.

## Deferred

This checkpoint does not implement the History policy migration/outbox, App
Group production bridge, extension claim ledger, acknowledgement channel, or
UI. Until the owning checkpoint lands, record operations that require an outbox
or durable bridge revocation fail closed instead of pretending the dependency
exists. Their implementations must retain the identities, ordering, failure
states, size limits, and privacy boundary above.
