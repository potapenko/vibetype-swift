# KBD-MVP-3 Production Voice Pipeline QA

Date: 2026-07-14

Decision: **Implementation passed; live-provider UI smoke pending explicit
authorization**

This record covers KBD-MVP-3 only. It does not claim the later signed-device
keyboard/host matrix, TestFlight readiness, or a live OpenAI acceptance run.

## Entry Gate

KBD-MVP-2 was confirmed Passed before implementation from
`kbd-mvp-2-physical-feasibility-2026-07-14.md`. Its signed-device evidence names
an iPhone 14 Pro Max (`iPhone15,3`) on iOS 26.5.2 (`23F84`), Apple Development
signing, matching app/extension App Group entitlements, and real app-owned
Start, Finish, and Cancel recording lifecycle results.

## Repository Boundary

- Branch: `master`
- Implementation base: `880a935`
- KBD-MVP-3 checkpoint: the commit containing this record
- No branch, backlog task, agent, or push was created
- No live provider request ran; no API key was requested, read, or printed

## Production Architecture Result

- `IOSKeyboardDictationSessionCoordinator` no longer imports or constructs an
  audio recorder and no longer fabricates a deterministic result. It adapts the
  two bounded App Group records to `IOSForegroundVoiceWorkflow`.
- Keyboard and foreground Voice share the same process-owned workflow,
  recorder dependency, provider processor, pending-recovery admission, and
  capture lifecycle. Admission is mutually exclusive in both directions.
- The existing processor order remains transcription, optional correction,
  local post-processing with Voice Emoji Commands and ordered Replacement
  Rules, then optional translation. The existing Dictionary prompt input is
  unchanged.
- Acceptance continues through `IOSV1ForegroundVoicePersistenceOwner`, which
  owns Latest, optional History, accepted-audio Recording Cache policy, pending
  cleanup, and retry/discard reconciliation.
- The app publishes transient text only when the accepted record's
  `sourceAttemptID` matches the keyboard capture owned by the same request ID.
  Failure, cancellation, stale commands, duplicate commands, and unrelated
  accepted results publish no transient text.
- The extension captures request ID, extension lifetime ID, and host-context
  generation at Start. It inserts at most once only while all three still
  match. Ownership loss leaves the canonical accepted result in Latest.
- The bridge still has one extension-written command record and one app-written
  state/result record, each capped at 4 KiB and expiring. Result text is capped
  at 3 KiB UTF-8 so encoded state stays inside the record budget.
- Existing provider timeouts and cancellation handlers remain the only provider
  boundary. The keyboard session adds no polling, replay, or retry mechanism.

## Focused Verification

The focused iOS workflow suite passed 59 tests, including keyboard background
continuation, matching accepted text, timeout, and foreground/keyboard
one-recorder arbitration in both directions. Earlier focused keyboard and
coordinator suites passed 77 tests; the final full regression below re-ran
those suites after the last stale-result assertion was added.

The focused IOSCore processor suite passed 7 tests. Its standard production
flow now proves one matching Latest result and one matching History entry for
the accepted result.

Coverage added or retained for this iteration includes:

- Start, Finish, and Cancel;
- provider timeout and provider failure;
- stale and wrong-request command/result;
- duplicate command and duplicate state notification;
- exactly-once automatic insertion;
- extension-lifetime and host-context ownership loss;
- foreground Voice versus keyboard admission in both directions;
- Latest and optional History exactly once;
- Recording Cache, Pending Retry/Discard, History, playback, provider timeout,
  and provider cancellation through the existing regression suites.

## Full Verification

Simulator: iPhone 16, iOS 18.6 (`71E5A24E-74E4-49EE-BDFB-026C4C15CCCC`).
A scoped `caffeinate -dimsu` guard ran for each Simulator test/UI session and
was stopped afterward.

```sh
xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS \
  -destination 'platform=iOS Simulator,id=71E5A24E-74E4-49EE-BDFB-026C4C15CCCC' \
  test
```

Result: **1,060 tests passed; 0 failed; 0 skipped**.

Affected package results:

- HoldTypeDomain: **165 tests passed**
- HoldTypeOpenAI: **118 tests passed**
- HoldTypePersistence: **200 tests passed**
- HoldTypeIOSCore: **53 tests passed**

Build results:

```sh
xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS \
  -configuration Release -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project HoldType.xcodeproj -scheme HoldType \
  -destination 'platform=macOS' build

git diff --check
```

Both builds passed. The generic iOS Release build emitted only the existing
interface-orientation warning. `git diff --check` passed.

## Computer Use And Live Boundary

Computer Use opened the real HoldType app on iPhone 16 Simulator, granted the
test Simulator microphone permission, started the bounded Keyboard Dictation
Session, and confirmed the visible state `Ready for HoldType Keyboard`. It then
presented the real embedded HoldType extension in the Keyboard Practice field.
The production Settings, Latest, microphone, punctuation, editing, Globe, and
Return surface was visible, and no deterministic probe control or result copy
remained.

That Simulator had Allow Full Access off, so the extension correctly presented
`Enable Full Access` and did not send Start. Enabling Full Access would be a
separate system-setting mutation. More importantly, accepted insertion and
Latest fallback through the real production pipeline would require a live
provider call. The task explicitly withheld authorization for live OpenAI.
Therefore no live provider call, API-key access, accepted insertion, or live
Latest-fallback smoke was attempted. Those UI acceptance steps remain pending
explicit user authorization and must not be inferred from deterministic tests.

## Result

The KBD-MVP-3 implementation exit is satisfied in code: the feasibility
recorder/result path is gone, keyboard commands use the existing production
pipeline, canonical persistence remains single-owned, and insertion fails
closed when ownership cannot be proven. Automated acceptance and all requested
build regressions pass. Only the explicitly authorization-gated live-provider
UI smoke remains open.
