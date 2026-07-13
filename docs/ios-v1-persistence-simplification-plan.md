# iOS V1.1 Persistence Simplification Plan

Status: completed 2026-07-13.

Product behavior is fixed by
`docs/specs/features/ios-v1-release.md` and
`docs/specs/features/ios-v1-voice-state-persistence.md`. This document defines
the safe cutover and deletion order; it does not add product scope.

## Outcome

Replace the active legacy Pending/Latest compatibility graph with one small
voice-state owner, retain compact successful-text History, then delete the
transactional research system now preserved in the private
`holdtype-persistence-lab` repository.

The production result must still provide foreground Voice, one Pending,
explicit Retry/Discard, one non-expiring Latest Result, compact History, and
local-only relaunch recovery. It must not start accepted/failed History,
retry-audio, generation, outbox, receipt, tombstone, or automatic-provider-
retry behavior.

## Baseline

At the start of this plan, `HoldTypePersistence` contains:

| Area | Source lines | Test lines |
| --- | ---: | ---: |
| Whole package | 66,064 | 66,898 |
| Keep unchanged | 4,924 | 6,319 |
| Rewrite behind a smaller contract | 8,644 | 7,304 |
| Delete after cutover | 52,496 | 53,275 |

The delete set is 105,771 Swift lines. It cannot be removed first because the
current process context still creates Pending, Latest, provider consent, and
capture services through the legacy accepted-History graph.

## Completion Evidence

The transactional research system is preserved in the private
`holdtype-persistence-lab` repository at commit
`b68474179e8576b4c1b31a6cbc7905327f61acc8` and tag
`archive-2026-07-13`.

The production package finished inside every complexity budget:

| Area | Before | After | Change |
| --- | ---: | ---: | ---: |
| Source files | 79 | 23 | -56 |
| Test files | 55 | 12 | -43 |
| Source lines | 66,064 | 9,254 | -56,810 |
| Test lines | 66,898 | 8,030 | -58,868 |
| Total Swift lines | 132,962 | 17,284 | -115,678 |

The compact voice-state repository, capture owner, and foreground facade use
3,527 production lines against the 4,000-line budget. Their focused tests use
1,697 lines against the 3,000-line budget. Standalone provider consent adds
937 production and 255 test lines outside that voice-state budget.

The final deletion removed 60 legacy source files and 47 specialized test
files, totaling 122,165 lines. Searches over production and tests contain no
types declared by those deleted files and no old provider-consent symbols.

Qualification completed with:

- 193 `HoldTypePersistence` tests and its production build;
- 53 `HoldTypeIOSCore` tests and its production build;
- 990 tests in the `HoldType-iOS` scheme;
- iOS Simulator Debug and Release builds, including the keyboard extension;
- release-bundle privacy, identifier, dependency, forbidden-marker, and
  signature checks, with processed App Group entitlements correctly left as a
  physical signed-device gate;
- the macOS `HoldType` build and clean diff checks.

Physical Data Protection, eviction, and App Group entitlement claims remain
device gates and were not inferred from Simulator evidence.

## Complexity Budget

- The replacement voice-state, audio, capture, and facade implementation is
  capped at 4,000 production lines.
- Its focused persistence tests are capped at 3,000 lines.
- The final `HoldTypePersistence` target should be below 15,000 production and
  16,000 test lines.
- The checkpoint must remove at least 80,000 tracked Swift lines net.
- If a required invariant cannot fit inside those limits, stop and amend this
  plan before adding another capability, journal, generation, receipt, or
  recovery worker.

## Replacement Boundary

Add the new implementation beside the old graph under new storage names.
Production owns one actor with:

- one bounded atomic voice-state record containing optional Pending and
  optional Latest;
- one exact protected Pending audio file;
- semantic operations for adopt capture, begin provider work, fail, accept,
  reconcile locally, Retry authorization, Discard, and Clear Latest;
- a narrow compact-History client used only after Latest commit;
- test-only semantic checkpoints at Pending commit, Latest commit, History
  attempt, and audio removal.

The actor is the serialization boundary. It does not use a global operation
gate, process-context registry, capability graph, outbox, policy generation,
or cross-store transaction protocol. Existing atomic-file and bounded-JSON
helpers remain shared internal primitives.

Provider consent becomes a standalone record/owner. Capture becomes a small
exact-file owner. Neither may depend on accepted/failed History, old Pending
journals, or shared transactional root guards.

## Execution

### P1 — Characterize The Contract

Before production cutover, add focused scenarios for:

1. successful Pending -> provider -> Latest -> History -> cleanup;
2. History enabled, disabled, failing, and idempotent reconciliation;
3. provider failure followed only by explicit Retry or Discard;
4. relaunch before provider, during provider, after Latest, and after History,
   with a provider spy proving zero automatic calls;
5. exact Discard and Latest Clear isolation;
6. corrupt, future, oversized, and temporarily unavailable metadata;
7. one-Pending admission and atomic-write rollback.

Reuse product assertions, not the old capability permutation matrix.

### P2 — Build The Replacement In Isolation

- add the compact voice-state values, codec, repository actor, and exact audio
  owner under new storage names;
- rewrite capture around that owner;
- make provider consent independent of the legacy process context;
- keep the existing production facade temporarily so UI and provider code can
  move without a simultaneous full-app rewrite;
- pass the focused persistence tests before composition changes.

### P3 — Cut Over Production

- switch `IOSForegroundVoicePersistenceOwner` to the replacement actor;
- adapt `HoldTypeIOSCore` processing to the narrow semantic interface;
- switch containing-app composition, recorder bridge, workflow, lifecycle,
  Latest owner, and Debug qualification fixtures;
- create a fresh process owner in relaunch tests and prove zero provider calls;
- keep compact History and all unrelated Settings, Library, Usage, Keychain,
  and app UI behavior green.

### P4 — Prove Legacy Is Detached

The following production search must be empty before deletion:

```sh
legacy='IOSAcceptedHistory(Coordinator|Store|Journal|Outbox|Acceptance|PendingReplacement)|IOSHistoryPolicy|IOSFailedHistory|IOSAcceptedOutputDelivery|IOSPersistenceOperationGate|IOSPersistenceRepositoryRootIdentity|IOSProtectedAudioNamespaceInventory|IOSPendingRecording(Store|Journal|OperationGate|PublishedAudio|ProtectedAudio)'

rg -n "$legacy" \
  HoldTypeIOS \
  Packages/HoldTypePersistence/Sources \
  Packages/HoldTypeIOSCore/Sources \
  --glob '*.swift'
```

Also verify that executable code contains no old storage names and that
external tests no longer construct an accepted-History process context.

### P5 — Delete Whole Legacy Families

Delete together with their specialized tests:

- `IOSAcceptedHistory*` except `IOSAcceptedTextHistory*`;
- `IOSHistoryPolicy*`;
- `IOSFailedHistory*`;
- `IOSAcceptedOutputDelivery*`;
- old Pending journal/store/audio-filesystem/operation-gate/inventory files;
- shared persistence operation gate and root-identity registry.

Historical specs and Git history remain as evidence. The standalone package
and filtered history remain in the private persistence-lab repository; the
production repository does not keep a second source copy.

### P6 — Qualification And Closeout

Run, at minimum:

- `HoldTypePersistence` package build and focused/full surviving tests;
- `HoldTypeIOSCore` package tests;
- relevant `HoldTypeIOSTests` Voice, Latest, History, lifecycle, and
  composition tests;
- macOS build;
- iOS Simulator Debug and Release builds with the embedded extension;
- dependency-isolation checks and `git diff --check`.

Record before/after file, source-line, test-line, and test-count movement in
`docs/ios-v1-development-plan.md`. Device-lock and real eviction claims remain
physical-device gates and are not inferred from Simulator results.

## Keep, Rewrite, Delete

Keep current compact History, Settings, Library, Usage, credential marker,
Keychain, bounded JSON, and protected atomic metadata primitives.

Rewrite the V1.1 Pending model, storage location, capture owner, foreground
persistence facade/owner, local lifecycle recovery, and provider-consent
storage boundary.

Delete the old transactional families only after P4 passes. Do not migrate or
automatically delete their unshipped development files.

## Stop Conditions

Stop the cutover and preserve the last green checkpoint if:

- Latest can be lost after a provider success;
- relaunch can make a provider call without explicit Retry;
- corrupt or unavailable state is treated as empty;
- Discard can affect unrelated Latest or History;
- History failure can block acceptance cleanup;
- production still references a legacy family at the deletion gate;
- the replacement exceeds the complexity budget without a revised contract.
