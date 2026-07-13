# iOS P4D-3 Production Composition QA

Date: 2026-07-13
Milestone: P4D-3 process Voice composition and multi-scene lifecycle

## Decision

P4D-3 is complete. The containing app now constructs one passive,
process-lifetime foreground Voice graph and gives every iPhone and iPad window
the same controller, workflow, platform owners, persistence owners, and
provider bridge. Each window owns a different opaque scene facade, while one
process binding converts only validated aggregate foreground transitions into
bounded lifecycle recovery.

P4D-3 adds no Voice UI, Quick Session, audio background mode, App Group
publication, keyboard command, or external-app insertion. Those surfaces remain
owned by later milestones. `AVAudioRecorder` also remains a fail-closed
candidate until the separate P4D-2C physical-device proof succeeds.

## Delivered Contract

- Production composition retains one scene registry, permission adapter and
  owner, audio-session adapter and owner, feedback bridge, finalization owner,
  recorder bridge, provider bridge, History-playback arbitrator, workflow,
  controller, and lifecycle coordinator.
- Construction is passive. It does not load Settings, Library, consent,
  Keychain, Pending, Latest Result, microphone permission, or audio state and
  does not create a provider request.
- Missing credential coordination still constructs the Voice graph.
  Provider-free observation and local recovery remain available, while
  provider-authorized work fails closed at the credential boundary.
- The lifecycle scheduler has one recovery route:
  controller lifecycle lease, capture-source reconciliation, History recovery
  for the exact opportunity, Pending, Latest Result, then Settings and Library
  only when no durable recovery owns the surface.
- Lifecycle recovery waits for the exact active Voice task and reserves the
  controller before that task publishes its terminal state. A new Start cannot
  enter the publication-to-recovery race window. Cancellation-hostile recovery
  retains its lease until its child actually returns.
- Cancellation gates separate every awaited lifecycle stage. A late Capture,
  History, Pending, Latest, Settings, or Library result cannot start the next
  stage after cancellation.
- `HoldTypeIOSApp` no longer treats one app-level `scenePhase` as every window.
  Each `WindowGroup` creates one passive scene host, registers from its own
  lifecycle observation, maps active/inactive/background exactly, preserves
  its identity while backgrounded, and unregisters synchronously at most once
  with an off-main deinitialization fallback.
- Every scene action is submitted through that host's private facade. Removing
  the initiating window invalidates its exact prompt lease; another window
  cannot inherit it and may only acquire a fresh lease.
- A process-owned registry binding seeds the initial aggregate without work,
  covers the first activation with launch recovery, ignores prompt-only and
  stale events, and schedules exactly one foreground opportunity after a later
  aggregate inactive-to-active transition.
- Storage-unavailable and injected compositions create no Voice runtime, scene
  facade, or registry-to-scheduler binding.

## Automated Evidence

- Broad runtime and lifecycle regression
  - Selected production composition, lifecycle scheduler, controller,
    lifecycle coordinator, runtime, and workflow suites.
  - Result: 87 tests in 6 suites passed; log
    `/tmp/p4d3-lifecycle-tests.log`.
- Isolated workflow warnings-as-errors gate
  - `SWIFT_SUPPRESS_WARNINGS=NO`,
    `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, and
    `GCC_TREAT_WARNINGS_AS_ERRORS=YES`.
  - Result: 57 tests in 1 suite passed; log
    `/tmp/p4d3-lifecycle-workflow-wae-isolated.log`.
- Per-scene composition warnings-as-errors gate
  - Selected composition, scheduler, scene host, scene owner, aggregate
    binding, and scene-registry suites under the same strict build settings.
  - Result: 34 tests in 6 suites passed; log
    `/tmp/p4d3-scene-host-wae2.log`.
- Two independent read-only reviews found no P1 or P2 issue in controller
  serialization, cancellation gates, retention, redaction, SwiftUI state
  lifetime, exact facade ownership, or aggregate multi-window scheduling.
- `git diff --check` passed before this documentation checkpoint.

Xcode emitted only the expected AppIntents metadata-tool notice that extraction
was skipped because the targets do not depend on AppIntents. Swift compilation
and the selected tests ran with warnings as errors.

## Safety And Redaction

Runtime, lifecycle coordinator, refresh result, scene owner, binding, opaque
facades, leases, and events expose content-free diagnostics. Observable
presentation contains no accepted text, Settings or Library content,
credential, path, provider request, private token, scene identity, or prompt
generation.

All verification used fakes and local simulator storage. It did not request
microphone permission, activate a live audio session, record or play audio,
emit a real haptic, begin a real background assertion, contact OpenAI, read or
write a live API key, enable keyboard Full Access, or publish Voice state to the
keyboard.

## Remaining Gates

- P4D-4 owns native Voice and Privacy UI bound to the shared controller and the
  invoking scene owner. It must expose the frozen phases, recovery actions,
  setup routes, accepted-result actions, and destructive confirmations without
  inventing per-window Voice truth.
- P4D-2C remains the physical iPhone/iPad recorder identity and runtime matrix.
  Failure selects a descriptor-backed writer without weakening Persistence.
- P4D-5 owns the final simulator, Release, keyboard-isolation, accessibility,
  and physical-device evidence. P4 and the keyboard product remain not
  release-ready until those gates pass.
