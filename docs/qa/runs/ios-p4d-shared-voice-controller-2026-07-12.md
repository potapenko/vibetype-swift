# iOS P4D-1 Shared Voice Controller QA

Date: 2026-07-12
Milestone: P4D-1 payload-free processor progress and shared Voice controller

## Scope

- Add a payload-free `VoiceAttemptStage` progress seam to the existing
  foreground processor only after its matching durable Pending boundary.
- Permit explicit Retry from either `readyForTranscription` or
  `awaitingRecovery` while keeping passive recovery provider-free and requiring
  a fresh transcription identity and current compact configuration.
- Keep accepted final text in provider-free `savingResult` recovery when
  cancellation races output persistence.
- Add one passive, process-lifetime, fake-backed Voice controller with separate
  phase, stage, outcome, setup, failure, recovery, action, and Latest axes.
- Bind commands, progress, completion, and cancellation to one private runtime
  authority; reject stale or regressive callbacks and wait for durable workflow
  resolution before admitting another operation.
- Add no AVFoundation object, microphone prompt, audio-session activation,
  recording, production composition, scene aggregation, Voice UI, plist key,
  entitlement, background mode, App Group publication, or keyboard dependency.

## Processor Progress And Recovery

- `transcription` is emitted only after the fresh ID and one-shot dispatch are
  durable. Cancellation while that admission is suspended emits no progress,
  provider request, or Usage work.
- `postProcessing` and `outputDelivery` are emitted only after the matching
  Pending phase is durable or exact same-phase confirmation succeeds.
- One invocation deduplicates each semantic stage. Retained `beginning` emits
  nothing until it regains the exact live durable dispatch authority.
- Local recovery distinguishes `processingCheckpoint` from `savingResult`.
  Once final accepted text exists, cancellation preserves that exact local
  checkpoint and never converts it into a provider Retry.
- Progress is ordered on the main actor and is presentation evidence only. The
  processor task, operation identity, durable state, and returned resolution
  remain the cancellation and terminal authority.

## Shared Controller

- Construction is passive. Explicit activation coalesces one observation and
  creates no capture, provider, persistence mutation, permission request, or
  secret access.
- Start, Retry Pending, Recover Recording, confirmed Discard, Retry Saving, and
  Retry Local Checkpoint share one primary operation slot. Commands carry a
  presentation revision and are rejected when stale or unavailable.
- Current-token progress is monotonic. A delayed Listening, Finalizing, or
  earlier processing callback cannot regress a later phase, restore invalid
  actions, or make Cancel Processing available after `outputDelivery`.
- Cancel Start, Cancel Utterance, and Cancel Processing cancel once and wait for
  the durable resolution. Every cancellation preserves the independently
  confirmed Latest availability. Ordinary capture cancellation strips hostile
  workflow outcome, failure, and recovery values; processing cancellation
  retains only canonical durable recovery.
- A cancelled token cannot publish a late `resultReady`. Hostile late success
  becomes blocked local reconciliation without replacing prior Latest truth.
- Activation and completion project Pending/local processing recovery as
  `recoverableFailure`; Saving Result preserves its retained semantic stage
  instead of forcing every case to `outputDelivery`.
- Controller, client, commands, authorities, observations, failures, recovery,
  and resolutions have fixed redacted descriptions and empty reflection. No
  accepted text, credential, request, path, Settings, Library content, or
  private operation identity enters observable presentation.

## Automated Evidence

- Strict full `HoldTypeIOSCore` package tests with complete concurrency and
  warnings as errors
  - Result: 95 tests passed in 8 suites.
- Strict serialized full `HoldTypePersistence` package tests with complete
  concurrency and warnings as errors
  - Result: 1,029 tests passed in 52 suites.
- Focused `IOSForegroundVoiceControllerTests` on iPhone 16 Pro / iOS 18.6 with
  automation Keychain access disabled
  - Result: 12 tests passed in 1 suite.
  - Result bundle:
    `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/HoldType-aiagnlkblhltvacjmbtlpyjistgi/Logs/Test/Test-HoldType-iOS-2026.07.12_23-42-06-+0200.xcresult`.
- Full `HoldType-iOS` simulator regression with the same automation credential
  boundary
  - Result: 1,576 tests passed, 0 failed, 0 skipped in 151 suites on iPhone 16
    Pro / iOS 18.6.
  - Result bundle:
    `/tmp/holdtype-p4d1-ios-tests/Logs/Test/Test-HoldType-iOS-2026.07.12_23-46-30-+0200.xcresult`.
- Full `HoldType` macOS regression with automation Keychain access disabled
  - Result: 441 tests passed, 0 failed, 0 skipped on macOS 26.5.1.
  - Result bundle:
    `/tmp/holdtype-p4d1-macos-tests/Logs/Test/Test-HoldType-2026.07.12_23-43-18-+0200.xcresult`.
- Release builds
  - Strict `HoldTypeIOSCore` and `HoldTypePersistence` package builds: passed.
  - Generic iOS Simulator `HoldType-iOS`: passed under
    `/tmp/holdtype-p4d1-release-ios`.
  - macOS `HoldType`: passed under `/tmp/holdtype-p4d1-release-macos`.
- `git diff --check`
  - Result: passed.

The strict Persistence suite is intentionally serialized. A diagnostic
parallel run exercised timing-sensitive coordination fixtures concurrently and
failed their bounded test-entry waits; the required serialized suite passed
all 1,029 tests without changing production code.

A preliminary unsigned full iOS run was also non-qualifying: disabling code
signing intentionally omitted the containing-app access-group substitution and
the simulator killed one concurrent processor test. The required simulator-
signed rerun used the same automation credential boundary and passed all 1,576
tests, including both affected cases.

No verification contacted OpenAI, used a real API key, read or wrote live
Keychain data, requested microphone access, activated an audio session, touched
the clipboard, enabled keyboard Full Access, or exercised a live provider.

## Independent Review

Independent review first found cancellation-admission, accepted-final-text,
Latest-baseline, same-token progress-regression, and canonical-recovery issues.
Each received a focused regression test and implementation fix. Final review
covered durable progress boundaries, provider replay, cancellation races,
revision and token authority, Latest independence, terminal projection,
redaction, and the P4D-1 non-goals.

Release inspection confirmed the keyboard still links only system
Foundation/UIKit/Swift libraries, keeps `RequestsOpenAccess` false, and receives
no Voice controller, IOSCore, Persistence, OpenAI, Keychain, microphone, or
audio dependency. The standalone and embedded Release executables are
byte-identical with SHA-256
`8b73557ba0b8e10e520602a642d1a36bbac05bc88e10bb4a9e10e37284d518e5`.

## Assessment

P4D-1 passes. HoldType now has deterministic payload-free processing progress
and a fake-backed process-owned Voice controller whose actions and presentation
cannot be driven by stale callbacks or payload data. P4D-2 is next: implement
the descriptor-bound capture source and frozen iOS permission, audio-session,
recorder, cue/haptic, and bounded-finalization adapters without adding
background audio or keyboard dependencies.
