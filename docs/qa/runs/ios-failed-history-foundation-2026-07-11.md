# iOS Failed History Foundation QA

Date: 2026-07-11
Milestone: P2 C4.1 strict failed-History values and persistence foundation

## Scope

- Add the containing-app-only failed-History v1 value model, strict wire codec,
  protected journal repository, root-shared store, and guarded policy-baseline
  evidence.
- Bound the queue to five failed rows and five exact audio-cleanup tombstones,
  with deterministic order, canonical identifiers and timestamps, and one
  durable retry operation at most.
- Keep malformed, future, oversized, incorrectly marked, protected-data-
  unavailable, and commit-uncertain storage fail-closed and preserved.
- Keep every failed row, retry identity, audio identifier, tombstone, journal
  mutation capability, and raw read surface internal to `HoldTypePersistence`.

PendingRecording ownership transfer, namespace inventory, retention, Delete,
physical audio cleanup, policy-cutover reconciliation, explicit Retry,
provider-free lifecycle recovery, and public app read models remain C4.2 through
C4.5. This checkpoint adds no partial History UI or keyboard behavior.

## Automated Evidence

- `swift test --package-path Packages/HoldTypePersistence -Xswiftc
  -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 628 tests in 30 suites.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test -quiet`
  - Result: passed for the full macOS suite; no live provider or credential was
    used.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,id=AFB49941-79A4-400A-AA0F-9E962155E485' test -quiet`
  - Result: passed, 991 tests, 0 failed, 0 skipped on iPhone 16 Pro simulator,
    iOS 18.6.
- The matching HoldType-iOS simulator `build` action passed and produced the
  containing app with its keyboard extension.
- `swift package --package-path Packages/HoldTypePersistence
  dump-symbol-graph --minimum-access-level public`
  - Result: no `IOSFailedHistory`, failed-store, journal-authority, or shared
    model-bound symbol is public.
- `otool -L` and `nm -gU` on the simulator keyboard executable and debug dylib
  - Result: no Domain, Persistence, IOSCore, OpenAI, PendingRecording,
    accepted-History, policy, or failed-History linkage or symbols.
- `git diff --check`
  - Result: passed for the checkpoint-owned source, tests, specs, roadmap, and
    QA record.

## Verified Foundation Contract

- The sole record is `Application Support/HoldType/ios-failed-history.json`,
  limited to 1 MiB, Complete-protected where the platform exposes that class,
  backup-excluded, owner-only, and marked exactly
  `com.holdtype.ios.failed-history = v1`.
- The root has exactly four members. Rows, retry operations, and tombstones have
  exactly 15, 7, and 5 members respectively; nullable language and retry fields
  are explicit JSON `null`.
- UUIDs are lowercase canonical values; timestamps are integral Unix
  milliseconds and reject conversion overflow without trapping. Entries are
  newest-first with ascending UUID ties; tombstones are oldest-first with
  ascending UUID ties.
- Attempt and audio identities are unique across rows and tombstones. A
  translation-stage failure requires translation intent. A retry operation
  requires a ready row and a positive retry count; a
  `pendingJournalRetirement` row has retry count zero.
- PendingRecording, failed History, accepted output, and accepted History share
  one persistable 256-byte UTF-8 model bound and the same metadata-character
  validation. The maximum valid PendingRecording model is proven to fit and
  round-trip in the complete journal record.
- The journal uses exclusive create and physical compare-and-swap replacement,
  maps protected-data and commit-uncertain failures distinctly, and never
  rewrites or removes corrupt, future, oversized, or incorrectly marked source
  bytes. Release builds let only the failed store mint journal mutation
  authority; the direct test constructor exists only in debug builds.
- The failed store treats only proven absence or a valid empty root as guarded
  baseline evidence. The production process context shares one failed store per
  physical root and rejects mixed capability owners before repository I/O.
- Existing policy bootstrap now includes failed-History evidence, so a nonempty
  failed root prevents creation of a fresh baseline policy.

## Independent Review Fixes

Two independent read-only reviews found and verified fixes for:

- a model bound equal to the entire PendingRecording journal size; the shared
  bound is now 256 bytes and has an end-to-end wire-capacity test;
- diverging PendingRecording and failed-row model validation;
- a positive retry count on a row whose pending journal was not yet retired;
- package-wide release construction of raw journal mutation authority;
- missing equal-time ordering, maximum-shape, enum, UUID, null, Int32 boundary,
  replacement-uncertainty, wrong-marker, and foreign failed-store tests.

The final reviewers reported no remaining P0 or P1 finding.

The full parallel package gate also exposed a scheduler-sensitive two-second
test synchronization deadline in the existing protected-audio lease test. Its
bounded test-only deadline is now ten seconds; the focused scenario and final
full strict suite both pass without changing production timing.

## Gate Decision

P2 C4.1 failed-History values and persistence foundation: passed for package,
macOS, and iOS simulator verification.

The next checkpoint is C4.2: sealed PendingRecording ownership transfer, exact
protected-audio inventory, bounded retention and Delete, and one-tombstone
cleanup. No user-visible failed History or Retry surface is shipping yet.

This is not physical-device evidence. Effective Complete Data Protection while
locked and force-quit/process-eviction behavior remain named signed-device
gates.
