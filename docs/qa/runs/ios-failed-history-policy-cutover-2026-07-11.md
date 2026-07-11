# iOS Failed History Policy Cutover QA

Date: 2026-07-11
Milestone: P2 C4.3 failed-History and retry-audio policy-cutover integration

## Scope

- Join failed rows, pending-journal retirement, retry ownership, and exact
  audio cleanup to the completed C3 History policy cutover without another
  policy generation change.
- Reconcile the failed domain before accepted-row pruning, one canonical
  outbox head, and standalone delivery inspection.
- Perform at most one provider-free failed-domain action per cleanup call:
  exact PJR recovery, process-lost Retry cancellation, one existing tombstone
  cleanup, or one canonical-oldest row invalidation.
- Preserve current-generation rows on a confirmed no-op, filter disabled
  History immediately, and fail closed on future generations or an invalidated
  `acceptingOutput` retry.
- Bind live Retry ownership and process-loss cancellation to one canonical
  physical-root state without exposing failed state or audio to the keyboard.

Explicit provider Retry, accepted-output success handoff, public redacted
History boundaries, and containing-app lifecycle wiring remain C4.4 and C4.5.

## Automated Evidence

- Focused strict suites passed:
  - policy-cutover Store: 6 of 6 tests;
  - failed transfer coordinator: 11 of 11 tests;
  - failed audio-cleanup coordinator: 14 of 14 tests;
  - matching C3 coordinator filter: 136 tests across accepted coordinator,
    outbox worker, and policy-cutover suites.
- `swift test --package-path Packages/HoldTypePersistence --no-parallel
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 766 tests in 38 suites.
- The matching strict-concurrency, warnings-as-errors release package build
  passed.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' build` and the matching test action passed.
  - Test result: 441 passed, 0 failed, 0 skipped.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,id=AFB49941-79A4-400A-AA0F-9E962155E485' build` and
  the matching test action passed on iPhone 16 Pro running iOS 18.6.
  - Test result: 1,129 passed, 0 failed, 0 skipped.
- `swift package --package-path Packages/HoldTypePersistence
  dump-symbol-graph --minimum-access-level public`
  - Result: policy-cutover directives, live-owner tokens, reservations,
    completion authorizations, Store helpers, and PJR recovery helpers remain
    absent from the public graph.
- `otool -L`, `nm -gU`, and `strings` on the simulator keyboard executable and
  debug dylib
  - Result: only expected system linkage; no Domain, Persistence, IOSCore,
    OpenAI, failed-History, PendingRecording, policy-cutover, retry-owner, or
    protected-audio linkage, symbol, or string entered the keyboard.
- `git diff --check`
  - Result: passed.

## Verified Cutover Contract

- Policy confirmation remains the logical-success boundary. Every retry after
  that point reuses the same receipt and generation; failed cleanup cannot
  roll policy back or create an N+2 generation.
- Failed-domain order is PJR, process-lost retry cancellation, an existing
  canonical tombstone head, then the absolute canonical oldest invalidated
  ready row. One call completes at most one of those actions and returns
  `pendingLocalRecovery` when more local work remains.
- A real PJR survives process loss with Pending metadata and audio intact. A
  fresh context retires only that metadata, commits the row to `ready`, and
  leaves policy generation and audio identity unchanged.
- Every retained or freshly refreshed PJR authority validates all failed rows
  and tombstones against the committed generation before further Pending or
  failed-root effects. A future sibling preserves failed bytes, Pending state,
  audio, retained phase, and policy.
- Existing tombstone cleanup precedes row invalidation. Row invalidation first
  commits exact tombstone ownership; a later pass removes only its validated
  audio and retires only that tombstone.
- Current-generation rows survive an enabled no-op unchanged. Disabled reads
  return no rows immediately after policy confirmation, while physical cleanup
  remains bounded and resumable.
- Failed cleanup completes before C3 accepted-row cleanup. The mixed-domain
  test retains the accepted row through failed invalidation and audio cleanup,
  then prunes it only after the failed domain is empty.

## Verified Retry-Owner Contract

- The failed Store owns the one canonical retry-owner actor for its physical
  root, and every coordinator over that Store reuses it. A foreign shadow actor
  cannot authorize cancellation or poison a valid canonical coordinator.
- A current-generation durable retry can produce a Store-minted live-owner
  token under the active root lease. Cutover observes that live owner before
  policy mutation; an inactive lease expires without wedging cleanup.
- Live-owner removal requires exact token equality, including the lease. A
  delayed cleanup from an older lease cannot clear a newer registration for the
  same durable retry.
- Process-loss cancellation atomically changes idle ownership to one exact
  reservation. The reservation blocks a later live owner and a second
  reservation, survives source- or outcome-visible commit uncertainty, and is
  consumed only by a Store-minted completion after the exact
  `retryOperation = null` outcome is durable.
- `reserved` and `providerDispatched` cancel locally without provider work or
  audio mutation. `acceptingOutput` remains blocked for the C4.4 exact delivery
  branch.

## Independent Review Fixes

Three independent read-only reviews found and verified fixes for:

- a stale absence proof that initially allowed a live owner to appear between
  proof minting and retry cancellation;
- a shadow retry-owner state whose proof was not initially bound to the
  canonical physical-root Store state;
- an owner model that initially represented only already-stale rows, not a
  real current-generation provider Retry;
- inactive live ownership that could wedge cutover, plus a late-clear ABA race
  that could clear a newer exact registration;
- coordinator defaults that initially created different retry actors over one
  Store and poisoned legitimate multi-coordinator composition;
- PJR recovery that initially checked only its target row, then only its old
  retained authority, rather than the whole freshly observed failed envelope;
- missing tests for true PJR process loss, retry-cancellation uncertainty,
  future rows and retained subphases, provider-dispatched ordering, and the
  failed-to-C3 handoff.

The final independent re-review reported no remaining P0 or P1 finding.

## Gate Decision

P2 C4.3 failed-History and retry-audio policy-cutover integration: passed for
focused Store/coordinator suites, the serialized full strict package gate,
release build, macOS, iOS simulator, public API isolation, keyboard binary
isolation, and independent review.

C4.3 is complete. The next checkpoint is C4.4: one explicit, durable,
cancellable Retry and its exact accepted-output success handoff.

This is not signed-device evidence. Effective Complete Data Protection while
locked, physical interruption behavior, and force-quit/process-eviction remain
their named device gates.
