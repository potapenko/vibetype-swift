# iOS Failed History Retry Accepted-Output Handoff QA

Date: 2026-07-12
Milestone: P2 C4.4C accepted-output handoff and terminal success

## Scope

- Reserve the exact accepted-delivery slot before the failed row publishes
  `acceptingOutput`, without an await-sized mutation window.
- Protect the frozen slot and durable relation with one shared failed/delivery
  interlock and store-minted, root-lease-bound permits.
- Commit normal accepted output with automatic insertion disabled, the frozen
  Keep Latest preference, exact History metadata, and immutable failed-Retry
  provenance.
- Complete pending History, including the one exact absent-row decision, then
  move the failed row to its pre-reserved audio-cleanup tombstone only after
  terminal delivery is durable.
- Reconcile acceptance and success commit uncertainty without replaying the
  provider, duplicating History, deleting audio inline, or exposing text.
- Preserve the existing strict version-1 accepted-delivery wire while adding a
  strict version-2 form for store-authorized failed-Retry provenance only.

C4.4D still owns provider-free process-loss recovery across every interrupted
C4.4 phase. C4.5 still owns containing-app lifecycle wiring and the public
redacted app boundary.

## Automated Evidence

- `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1 swift test
  --package-path Packages/HoldTypePersistence --no-parallel
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 846 tests in 45 suites.
- `swift build --package-path Packages/HoldTypePersistence -c release
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test -quiet`
  - Result: passed.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,id=AFB49941-79A4-400A-AA0F-9E962155E485' test
  -quiet`
  - Result: passed on iPhone 16 Pro running iOS 18.6.
- `swift package --package-path Packages/HoldTypePersistence
  dump-symbol-graph --minimum-access-level public`
  - Result: Retry accepting-output values, freeze reservations, terminal
    delivery capabilities, entrypoints, and `failedRetryID` remain absent from
    the public graph.
- `otool -L`, `nm -gU`, and `strings` on the simulator keyboard executable and
  debug dylib
  - Result: only expected system linkage; no Domain, Persistence, IOSCore,
    OpenAI, PendingRecording, failed History, Retry, Usage, Keychain,
    accepted-output, or accepted-History linkage, symbol, or string entered the
    keyboard.
- `git diff --check`
  - Result: passed.

No verification command contacted OpenAI or used a live API key.

## Verified Acceptance Boundary

- Retry admission requires an empty accepted-History outbox and preserves the
  durable capacity invariant `audioCleanup.count + activeRetryCount <= 5`.
  Unrelated failed-row mutations cannot consume the reserved cleanup slot.
- The delivery actor observes the current slot and installs one opaque freeze
  reservation atomically. Ordinary delivery and failed-store mutations are
  blocked before `acceptingOutput` exists; exact upgrade, refresh, and clear
  require the same reservation ID and relation key.
- A raw relation key is not bearer authority. Every Retry delivery mutation
  requires a store-minted permit bound to the exact receipt, delivery store,
  owner, root gate, live lease, and interlock.
- Exact accepted text remains process-local until the normal accepted-output
  record is committed. A definitive pre-boundary failure releases only the
  exact freeze; commit uncertainty or visible `acceptingOutput` retains local
  recovery and never re-enters provider work.
- Concurrent or repeated `accept()` callers share one in-flight operation and
  receive the same completed resolution.

## Verified Provenance, History, And Success

- Version 1 keeps its exact 16-field shape and decodes with no Retry
  provenance. Version 2 has exactly 17 fields and requires one canonical,
  non-null `failedRetryID`; ordinary delivery cannot write or adopt it.
- Retry provenance participates in record and expectation equality, survives
  every non-discard History transition, and clears only on the exact discarded
  tombstone path. An untagged or differently tagged byte-identical record is a
  collision, not idempotent success.
- Predecessor transfer requires exact source lineage, one revision step, and
  byte-exact UTF-8. A substituted unrelated current slot cannot be authorized,
  and an exact cancelled predecessor remains recoverable.
- The exact relation suspends delivery expiry only for proof-bound local work:
  acceptance replay, pending History authorization, one absent-row decision,
  terminal marker mutation and confirmation, and final failed-row success.
  It never re-enables publication, insertion, ordinary mutation, or removal.
- Successful completion requires the tagged delivery, terminal History, and
  exact failed-row relation. Only then does one physical CAS replace the row
  with its audio-cleanup tombstone; audio remains for the existing bounded
  cleanup worker.
- Source-visible acceptance or success uncertainty reuses the same frozen
  capability and reconciles either invisible or already-durable outcomes
  without a second provider request or duplicate transition.

## Independent Review Fixes

Three independent read-only reviews found and verified fixes for:

- an initial await-sized gap between delivery-slot observation and relation
  publication;
- raw relation identity initially carrying too much mutation authority;
- incomplete isolation between ordinary delivery mutation and the failed Retry
  relation;
- accepted-delivery Retry provenance initially being reconstructable from
  otherwise matching identity and bytes;
- immediate History reconciliation initially omitting `failedRetryID` from its
  idempotent-CAS lineage;
- expiry initially blocking proof-bound local completion after accepted output
  was already durable;
- success cleanup and concurrent acceptance ownership edge cases.

The final repeated Store/lease, contract/provenance, and test-map reviews
reported no remaining correctness finding.

## Verdict

P2 C4.4C accepted-output handoff and terminal success: passed for focused and
full strict package tests, release build, macOS regression, iOS simulator,
public API isolation, keyboard binary isolation, exact reservation/interlock
ownership, strict v1/v2 provenance, post-expiry local completion, Store
uncertainty, terminal History, audio-cleanup reservation, privacy, and
independent review.

The next checkpoint is C4.4D: recover every durable interrupted Retry phase
after process loss without provider replay, caller-reconstructed text, or
cross-store authority widening.
