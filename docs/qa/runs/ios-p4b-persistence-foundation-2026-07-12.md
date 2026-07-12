# iOS P4B Persistence Foundation QA

Date: 2026-07-12
Milestone: P4B app-only foreground voice persistence

## Scope

- Add one current-disclosure, app-private provider-consent record with explicit
  Accept and Withdraw, exact observation compare-and-swap, process-owned
  provider authority, and fail-closed repository identity checks.
- Close the canonical P4 accepted-output transaction from an exact
  `PendingRecording.outputDelivery` owner through mandatory generation-0
  accepted delivery, exact destination confirmation, Pending audio removal,
  Pending journal retirement, and ready-result publication.
- Preserve provider-free `Saving Result` recovery across local persistence
  failure, process loss, uncertain synchronization, collision, replacement,
  and final observation failure without repeating provider work.
- Add app-only Latest Result load, confirmed Clear, content-free tombstone
  cleanup, explicit recovery-to-`awaitingRecovery`, and launch reconciliation.
- Create no History row, History product state, or user-facing History action.
  Retained foreground work does join the shared admission interlock so accepted
  and failed History, outbox, cutover, deletion, Retry, transfer, and lifecycle
  mutations stop before I/O instead of racing the P4 transaction. Recording
  cache, microphone/audio-session implementation, provider transport, Voice UI,
  background mode, Quick Session, App Group bridge work, keyboard insertion,
  and keyboard dependencies remain outside this checkpoint.

## Automated Evidence

- Final focused `HoldTypePersistence` runs
  - Provider consent: 64 passed in three suites; log
    `/tmp/holdtype-p4b-final-consent.log`.
  - Pending audio filesystem, journal, and store: 132 passed in three suites;
    log `/tmp/holdtype-p4b-final-pending.log`.
  - Foreground persistence: 33 passed in one suite; log
    `/tmp/holdtype-p4b-final-foreground.log`.
  - Accepted-History/interlock integration: 138 passed in three suites; log
    `/tmp/holdtype-p4b-final-history.log`.
- Strict full `HoldTypePersistence` package test with complete concurrency and
  warnings as errors
  - Command used `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH=1`,
    `--no-parallel`, `-Xswiftc -strict-concurrency=complete`, and
    `-Xswiftc -warnings-as-errors`.
  - Result: 1,027 passed in 52 suites; log
    `/tmp/holdtype-p4b-final-package-strict.log`.
- Release `HoldTypePersistence` package build with complete concurrency and
  warnings as errors
  - Result: passed; log `/tmp/holdtype-p4b-final-package-release.log`.
- Full `HoldType-iOS` simulator tests
  - Run with `HOLDTYPE_AUTOMATION=1` and
    `HOLDTYPE_KEYCHAIN_AUTHENTICATION_UI=skip` on iPhone 16 Pro / iOS 18.6.
  - Result: 1,512 passed, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p4b-authoritative-ios-20260712.xcresult`, log
    `/tmp/holdtype-p4b-authoritative-ios-20260712.log`, and DerivedData
    `/tmp/holdtype-p4b-authoritative-ios-derived`.
- Full `HoldType` macOS tests
  - Run with the same automation credential boundary on macOS 26.5.1.
  - Result: 441 passed, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p4b-authoritative-macos-20260712.xcresult`, log
    `/tmp/holdtype-p4b-authoritative-macos-20260712.log`, and DerivedData
    `/tmp/holdtype-p4b-authoritative-macos-derived`.
- Release iOS Simulator and macOS Xcode builds
  - Both passed. iOS artifacts are under
    `/tmp/holdtype-p4b-release-ios-final` with log
    `/tmp/holdtype-p4b-release-ios-final.log`; macOS artifacts are under
    `/tmp/holdtype-p4b-release-macos-final` with log
    `/tmp/holdtype-p4b-release-macos-final.log`.
- Release keyboard-extension compile/link, dependency, symbol, string,
  byte-search, entitlement, and embedded-binary identity inspection
  - Both architecture source lists contain only `KeyboardBridge.swift` and
    `KeyboardViewController.swift`; link lists contain only their two object
    files. Both dependency-metadata lists are empty, and the target still has
    empty Frameworks, target dependencies, and package-product dependencies.
  - `otool`, `nm -gU` with Swift demangling, `strings`, and an entire-appex byte
    scan found no Domain, Persistence, IOSCore, OpenAI, consent, Pending,
    accepted-output, History, Keychain, or P4B xattr dependency/symbol/string.
  - `RequestsOpenAccess` is false. The source entitlement remains only the
    existing App Group; the simulator-processed entitlement dictionary is
    empty.
  - Standalone and embedded extension executables are byte-identical with
    SHA-256
    `54a3e0e58528f3aba9a18cb4222bca821ebab1bb957aec8e9e3475e7ca97fb8d`.
- `git diff --check`
  - Result: passed.

No verification contacted OpenAI, used a real API key, read or wrote live
Keychain data, requested microphone access, touched the clipboard, or enabled
keyboard Full Access. Consent lifecycle tests executed only in-process fake
launch/result closures; no live provider transport or network work ran.

## Provider Consent Contract

- Passive observation grants no authority. Explicit Accept commits one exact
  current-disclosure epoch/revision and only its confirmed physical file
  revision can mint short-lived provider capabilities.
- Transcription, correction, and Translation use separate dispatch and result
  capabilities. Registration, launch, finish, and result consumption revalidate
  the exact durable consent snapshot and physical repository root.
- Withdraw closes the process gate synchronously, cancels registered or live
  provider work, and makes queued old mutations or callbacks ineligible. A
  same-root record replacement, deletion, corruption, unavailability, or root
  substitution also closes the gate.
- Canonical Application Support creation is owner-only and descriptor-relative.
  Process-context resolution may resolve the path again, but initialization
  compares that pinned context/root and its final revalidation with the exact
  bootstrap identity and fails closed on any handoff mismatch.
- Public launch and result closures cannot deadlock the gate through callback
  re-entry. Consent records, authorizations, errors, callbacks, and diagnostic
  surfaces remain payload-free or redacted.

## App-Only Acceptance And Pending Retirement

- P4 accepts only an exact available `PendingRecording.outputDelivery` owner
  with matching attempt, transcript, and output intent. It creates or atomically
  replaces one generation-0, never-published delivery with `historyWrite: null`.
- Ready state is unavailable until the exact accepted destination is confirmed,
  Pending audio is absent with root-bound durable evidence, and the exact
  Pending journal is absent with separate durable evidence.
- P4 accepted-output and explicit Discard audio removal first record the
  content-free 50-byte `com.holdtype.ios.pending-audio-removal` intent on the
  exact Pending journal inode. The intent binds purpose, audio device/inode,
  byte count, modification time, and status-change time; it survives a fresh
  filesystem instance and cannot delete a recreated pathname.
- Discard uses the same evidence-producing audio path. A missing journal is
  success only after the entire protected Pending-audio namespace is proved
  empty; an orphan remains visible and fails closed.
- Process-loss reconciliation proves the exact destination or its canonical
  absence under the current root and active lease. Plain `nil` lookup is never
  durable absence evidence.

## Latest Result And Recovery

- A local failure after accepted-output preparation enters `Saving Result` and
  retries only the missing local step. Provider execution, transcript
  acceptance, and already-completed audio or journal retirement are not
  repeated.
- A prior confirmed result may remain visible while an unrelated replacement
  is saving. An overlapping attempt or transcript with the wrong Pending phase,
  partial identity, or metadata mismatch fails closed and cannot be shown or
  cleared as ready.
- Clear proves that no exact Pending owner still depends on the delivery before
  it commits a discarded tombstone. A missing Pending lookup is followed by a
  root-bound, directory-durable absence proof under the same operation lease.
- After a confirmed tombstone, text stays hidden while no-input physical cleanup
  retries. Expiry, clock rollback, collision, commit uncertainty, and final
  observation failure retain their exact provider-free recovery state.

## Privacy And Extension Isolation

- Consent metadata, Pending metadata/audio, accepted text, recovery state, and
  all P4B persistence capabilities stay beneath the containing app's private
  Application Support root. P4B introduces no bridge or App Group publication;
  this claim does not redefine the separate existing keyboard bridge contract.
- Accepted text remains intentionally available in the app-owned `resultReady`
  product value. Diagnostic descriptions, debug descriptions, mirrors, errors,
  state objects, receipts, authorizations, and temporal ineligible outcomes
  expose no accepted text, prompt, credential, path, raw audio, provider
  payload, or storage capability.
- The keyboard extension remains a two-source system-only target with
  `RequestsOpenAccess` false and no Domain, Persistence, IOSCore, OpenAI,
  provider-consent, Pending, accepted-delivery, History, or Keychain dependency.

## Independent Review Fixes

Independent persistence, consent, concurrency, crash-consistency, privacy, and
architecture reviews found and drove fixes for:

- stale consent observations and same-root record/root replacement retaining
  provider authority;
- queued Accept racing Withdraw and mutating durable consent after gate close;
- a gap between final durable/root validation and decisive launch/result
  transition;
- canonical bootstrap verifying one root and binding a later replacement;
- launch/result callback re-entry deadlocking the consent gate;
- cross-executor callback re-entry while an outer admission mutex remained
  held;
- final bootstrap handoff omitting parent-directory owner/mode revalidation;
- process memory being the only Pending-audio removal intent;
- missing descriptor/path pinning around the removal-intent xattr;
- Discard reporting success for a nil journal while orphan audio remained;
- process-loss destination inspection trusting a plain missing lookup;
- cleanup repeating after retirement or losing `Saving Result` on final read
  failure;
- Clear trusting a nil Pending read without durable absence evidence; and
- wrong-phase or partial Pending/delivery overlap falling through as a ready,
  clearable result.

Final targeted rereviews of the corrected consent gate and foreground/Pending
relation found no remaining P0, P1, or P2 issue.

## Assessment

P4B passes. The app-only foreground voice Persistence transaction and provider
consent foundation are complete. P4C is next: reader-based OpenAI plus
consent-gated foreground processing, with no microphone or Voice UI work until
P4D.

Simulator and unit evidence do not certify effective Data Protection while a
physical device is locked, signed-device process eviction, sudden power loss,
minimum-iOS directory `fsync`, keyboard Full Access, or real App Group delivery.
Those remain named physical-device or lab gates and are not required to close
this containing-app persistence-only checkpoint.
