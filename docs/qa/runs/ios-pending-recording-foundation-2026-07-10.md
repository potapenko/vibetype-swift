# iOS Pending Recording Foundation QA

Date: 2026-07-10
Milestone: P2 protected recording and PendingRecording v1 checkpoint

## Scope

- Protect one completed app recording before provider work.
- Commit one strict app-private pending journal and transcription identity.
- Permit provider work through one non-detachable executor authorization.
- Make cancellation, process-loss recovery, discard, and uncertain journal
  commits deterministic without exposing state to the keyboard extension.
- Preserve existing macOS behavior and keep all verification provider-free.

## Automated Evidence

- `swift test --package-path Packages/HoldTypePersistence -Xswiftc
  -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 199 tests.
- `swift test --package-path Packages/HoldTypeIOSCore -Xswiftc
  -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 29 tests.
- The corresponding strict Domain and OpenAI package suites passed with 157 and
  109 tests.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test`
  - Result: passed, 441 tests on macOS 26.5.1.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,id=B12CCB99-5B3D-49A5-8CF2-7976C570D2EB' test
  CODE_SIGNING_ALLOWED=NO`
  - Result: passed, 562 tests on iPhone 16 simulator, iOS 18.1.
- `git diff --check`
  - Result: passed before checkpoint review.

The first full iOS run exposed a test-harness deadlock rather than a product
failure: `HoldTypeIOSTests` forced package test sources onto `MainActor`, so a
test could block that actor while waiting for a child `Task` that inherited the
same actor. The iOS test target now uses the package-default nonisolated model;
the app and keyboard targets remain `MainActor`-isolated. The four previously
blocked PendingRecording/lease tests then passed individually in milliseconds,
and the unmodified standard full-suite command passed.

## Storage And Race Evidence

- The strict journal has exactly 12 v1 members and rejects duplicate, unknown,
  wrong-typed, noncanonical, oversized, corrupt, or future input without
  rewriting it.
- Live journal replacement proves that a post-rename directory-sync failure
  preserves visible new bytes, reports typed commit uncertainty, and leaves no
  owned temporary file.
- Same-phase recovery performs a confirming rewrite and directory sync even
  from a different Store actor.
- Protected WAV round-trip coverage exercises the Darwin/AVFoundation path;
  media, descriptor identity, owner/mode/link count, protection, backup policy,
  duration, and byte count are revalidated before provider authorization.
- Concurrent authorization, reserve-versus-retire, cancellation registration,
  failed recovery writes, and non-cooperative late success are covered. A late
  result cannot escape after cancellation.
- Process-loss recovery requires destination absence, retires the old
  transcription identity, and allows only a fresh explicit Retry identity.

## Extension Isolation Evidence

- The simulator keyboard link list contains only `KeyboardViewController.o`
  and `KeyboardBridge.o`.
- `otool` on the extension debug dylib shows only system frameworks and Swift
  runtime libraries.
- `nm` finds no `HoldTypeDomain`, `HoldTypePersistence`, `HoldTypeOpenAI`, or
  `HoldTypeIOSCore` symbols in the extension.

## Independent Review

Three read-only reviews covered state-machine/durability ordering,
authorization/security boundaries, and race-test completeness. After the
cross-Store same-phase confirmation fix, all three reported no remaining P0 or
P1 finding.

## Gate Decision

P2 PendingRecording simulator/package checkpoint: passed.

This is not physical-device evidence. Signed-device Complete Data Protection,
microphone and AVAudioSession lifecycle, force-quit/process eviction, real
Keychain accessibility, App Group behavior, keyboard enablement, and Full
Access remain their named physical gates.
