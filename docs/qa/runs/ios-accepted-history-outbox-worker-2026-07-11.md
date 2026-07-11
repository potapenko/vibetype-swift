# iOS Accepted History FIFO Outbox Worker QA

Date: 2026-07-11
Milestone: P2 C2 strict one-head FIFO outbox recovery checkpoint

## Scope

- Recover at most the canonical oldest app-private outbox head per public call.
- Bind observation, membership, temporal state, policy, row decision, delivery
  relation, marker transition, and retirement to exact owner/store capabilities.
- Resume only the retained local phase after visible or invisible commit
  uncertainty, without repeating provider work or selecting a later head.
- Preserve rollback, protected-data, malformed/source-limit, collision, and CAS
  failures without skipping the head.
- Handle matching, invalidated, expired, missing, unrelated, discarded,
  pending, committed, and cancelled delivery relations.
- Protect an active terminal-History marker until matching outbox membership is
  retired or exact absence is proven under the paired stores' expected root
  operation gate. Exact expiry remains the bounded abandonment exception.
- Keep every History payload, receipt, capability, and record app-private and
  absent from the keyboard and App Group.

Global Clear/Disable/Enable policy cutover and stale-generation cleanup remain
the next P2 durability checkpoint. Failed History and retry audio follow that
checkpoint.

## Automated Evidence

- `swift test --package-path Packages/HoldTypePersistence -Xswiftc
  -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 574 tests in 26 suites.
- Strict-concurrency focused suites:
  - FIFO worker: 35/35 passed.
  - persistence operation gate: 15/15 passed.
  - outbox store: 38/38 passed.
  - accepted-output delivery store: 82/82 passed.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test`
  - Result: passed; no live provider, credential, or Keychain interaction was
    used.
- HoldType-iOS simulator test through XcodeBuildMCP
  - Result: 937 tests passed, 0 failed, 0 skipped on the live configured iPhone
    16 Pro simulator `AFB49941-79A4-400A-AA0F-9E962155E485`.
- HoldType-iOS simulator build through XcodeBuildMCP
  - Result: passed and produced the containing app with its keyboard extension.
- `swift package --package-path Packages/HoldTypePersistence
  dump-symbol-graph --minimum-access-level public`
  - Result: passed. The worker, raw stores, receipts, absence authorization,
    operation-gate identity/binding/lease, and retained phases are absent from
    the public symbol graph. Only the intentional payload-free
    `IOSAcceptedHistoryOutboxRecoveryResolution` and
    `recoverAcceptedHistoryOutbox()` surface are public.
- `otool -L` and `nm -gU` on the simulator keyboard executable and debug dylib
  - Result: the executable links only its debug dylib and system loader; the
    dylib links UIKit/Foundation/system/Swift runtimes. No Domain, Persistence,
    OpenAI, IOSCore, accepted-History, History-store, or outbox-worker link or
    symbol was found.
- `git diff --check`
  - Result: passed after implementation, review, spec, plan, and QA changes.

## Verified State And Durability Assertions

- Store-selected ordering is oldest `createdAt`, then UUID bytes. A call never
  accepts an index or identifier and never reaches the second head after
  rollback, failure, uncertainty, or definitive CAS supersession.
- Membership is identically rewritten before authority is issued. Temporal
  classification uses one sealed clock sample. Rollback performs no downstream
  mutation; exact expiry retires only that head.
- Matching policy performs one idempotent retained/not-retained row decision.
  A cutover found afterward performs no additional row decision. Strictly newer
  policy known first invalidates without new row work; equal-disabled and lower
  generations fail closed.
- Matching pending delivery is identically confirmed and transitioned with the
  exact row or invalidation authority. An exact committed terminal proof may
  retire without reinterpreting capacity; cancelled is terminal only under a
  strictly newer policy. Missing, unrelated, or discarded delivery retires from
  the durable row receipt.
- Root-shared worker state retains only the exact uncertain phase. Acceptance,
  pending replacement, delivery recovery, and future policy cutover cannot
  bypass it. Initial acceptance uncertainty prevents worker acquisition.
- Process loss reconstructs authority only from durable policy, row, outbox,
  and delivery state. Relaunch tests cover membership and retirement
  uncertainty, retained/not-retained row decisions, and newer-policy terminal
  markers.
- Delivery-absence authority is bound to exact delivery, owner, outbox and
  delivery stores, confirmed snapshot, and a live lease issued by the exact
  gate identity one-time-bound to both stores. A lease from another active gate,
  a same-owner foreign outbox, a stale capability, or post-release reuse fails
  before journal I/O. Foreign prebinding of either store poisons coordinator
  assembly before repository I/O.
- Production consumes an absence capability immediately in the same gate
  operation. The capability and lease do not escape to an unstructured task,
  and no outbox mutation intervenes; future sequencing that cannot preserve
  this ordering requires store-enforced revocation.
- Terminal-retirement visible/invisible uncertainty and a true same-journal
  multi-actor CAS race preserve the canonical next head. Definitive CAS clears
  retained worker state and ends the call.
- Repository-identity conflict remains a typed error even after head
  observation; the provider-free worker has no replay boundary that may hide
  permanent root poisoning.

## Independent Review

Initial state/security, spec, and coverage reviews found high-risk gaps in
gate-issuer binding, paired outbox provenance, repository-conflict semantics,
terminal retirement, process-loss coverage, and policy/delivery matrices. The
implementation and tests above include their fixes. Three independent final
follow-up reviews found no remaining P0/P1 issue. Their two residual coverage
observations were closed by coordinator foreign-prebinding integration and
end-to-end later-delivery-confirmation uncertainty tests. Defensive ordering
constraints for non-escaping absence capabilities are recorded in the product
specs and above.

## Gate Decision

P2 C2 containing-app-only FIFO outbox recovery: passed for simulator/package
code verification.

This is not physical-device evidence. Effective Complete Data Protection while
locked, force-quit/process eviction, signed App Group behavior, keyboard
enablement/Full Access, and actual insertion remain their named physical gates.
