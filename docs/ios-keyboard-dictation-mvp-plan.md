# HoldType iOS Keyboard Dictation MVP Plan

Status: canonical keyboard MVP execution plan; approved 2026-07-14.

Product behavior is governed by:

- `docs/specs/features/ios-v1-release.md`;
- `docs/specs/features/ios-keyboard-experience.md`.

This file defines execution order, scope limits, exit criteria, and ready-to-use
chat prompts. It is not a backlog queue. Each implementation iteration is a
direct task in a new chat and ends with one scoped checkpoint commit on
`master`.

## Outcome

Deliver the smallest useful iPhone product in which:

1. the containing app launches with permanent Voice, Library, History, and
   Settings destinations;
2. HoldType Keyboard presents Settings, an actionable microphone, punctuation,
   editing controls, Globe, and Latest;
3. after one-time setup and while an explicit Keyboard Dictation Session is
   available, the user taps the keyboard microphone, speaks, finishes, and
   receives accepted text in the same live host field;
4. the containing app owns microphone capture, OpenAI, correction/translation,
   Latest, History, and optional Recording Cache;
5. an unsafe or no-longer-owned result is kept in Latest rather than inserted
   into a different field;
6. the signed physical-iPhone path is proven before TestFlight or App Store
   readiness is claimed.

## Platform Facts And Reference Behavior

- Apple documents that a custom keyboard extension has no microphone access:
  [Custom Keyboard Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).
- App Review Guideline 4.4.1 permits a keyboard to launch Settings, but not other
  apps, and requires useful behavior without Full Access:
  [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- Wispr Flow documents the practical reference pattern: Full Access, microphone
  permission granted to the containing app, and an app-owned session. Its iOS
  26.4 path may visit Wispr and require a manual swipe back:
  [Wispr Flow iPhone setup](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone).

Competitor behavior is product evidence, not App Review proof. HoldType first
implements the path that does not launch its containing app from the keyboard.

## Fixed Product Decisions

- Replace the keyboard `History` action with a gear that opens public iOS
  Settings for HoldType.
- History remains a permanent containing-app tab and is never rendered inside
  the keyboard.
- The microphone button is real. It is disabled only when prerequisites or an
  app-owned session are unavailable.
- The extension never accesses microphone APIs and never owns provider code.
- Keyboard-controlled dictation requires Allow Full Access. Punctuation,
  Space, cursor movement, Delete, Return, Globe, Settings, and safe Latest
  fallback remain useful without it.
- The user starts a bounded Keyboard Dictation Session in the containing app.
  The MVP maximum is 60 minutes unless the physical-device spike proves a
  shorter supported boundary is required. The user can stop it immediately.
- Starting a session alone does not create a transcript, add History, or submit
  audio. Spoken content is captured only between acknowledged Start and Finish.
- The keyboard never opens HoldType. If the session is unavailable, it says
  `Open HoldType`.
- One accepted result auto-inserts once only while the original extension
  request still owns the active host context. Otherwise it remains in Latest.
- App Store approval is not promised from code or Simulator evidence. Signed
  device, TestFlight, privacy, and App Review remain explicit gates.

## Minimal Architecture

```text
Host text field
    ^
    | UITextDocumentProxy.insertText
    |
HoldType Keyboard Extension
    | writes one current command
    v
App Group command record ------ bounded signal ------+
                                                     |
                                          containing app is already
                                          running an explicit session
                                                     |
                                                     v
                                     app-owned recorder and OpenAI
                                                     |
                                                     v
App Group state/result record <--- one current result+
    |
    +--> keyboard inserts only if request/context still match
    +--> containing app commits canonical Latest and optional History
```

### Record Budget

The MVP may add only:

1. one extension-written current command record;
2. one app-written current session/state/result record.

Each is atomically replaced, schema-versioned, bounded, expiring, and has one
writer. Together they must remain a small transient coordination boundary.

They must not grow into:

- an append-only log;
- an outbox or inbox;
- receipts or acknowledgement families;
- retries, leases, tombstones, generations, or policy migrations;
- a second Latest or History repository;
- a database or general transaction coordinator.

Raw audio, API keys, provider bodies, prompts, dictionaries, canonical History,
and durable host context never enter App Group storage.

## MVP State Machine

```text
Open HoldType / Enable Full Access / Allow Microphone
                         |
                         v
                       Ready
                         |
                    tap microphone
                         |
             app acknowledges real capture
                         v
                    Listening...
                    /          \
               Cancel       Finish
                 |             |
               Ready      Processing...
                               |
                  +------------+------------+
                  |                         |
          same live request            ownership lost
                  |                         |
          insert exactly once        keep canonical Latest
                  |                         |
                Ready                     Ready
```

No status may claim Listening before the app acknowledges actual capture. No
error retries a provider request automatically.

## MVP Acceptance

The MVP is functionally complete only when all of the following are true:

- a normal iPhone cold launch shows all four app tabs;
- History list, Copy, swipe Delete, and conditional Play remain intact;
- the keyboard gear opens only public system Settings;
- the keyboard remains a useful editing surface with Full Access off;
- setup can make a bounded app-owned session available;
- real keyboard Start, Finish, and Cancel control app-owned audio on a signed
  physical iPhone;
- real OpenAI output follows existing text rules and becomes Latest plus
  optional History;
- a result inserts exactly once into the same still-owned host context;
- dismissal, focus change, expiry, process loss, or stale request prevents
  automatic insertion and preserves Latest fallback;
- permission, offline, timeout, interruption, and session-expired states are
  short and recoverable;
- one internal TestFlight candidate passes the bounded device matrix.

## Explicit Non-goals

- QWERTY, number/symbol decks, predictions, autocorrection, or locale layouts;
- partial/live transcription;
- silence detection or automatic Finish;
- multiple simultaneous recordings or provider operations;
- background Quick Session outside the keyboard-session requirement;
- indefinite session duration or configurable duration UI;
- Live Activity, widgets, Action Button, Siri, or automatic host return;
- cloud sync, accounts, billing, analytics, or profiles;
- new History models, failed History, retry audio, or persistence redesign;
- production iPad keyboard qualification;
- visual redesign beyond the already selected Brand Stage composition.

## Execution Rules

- Run iterations strictly in order and never in parallel.
- Use a new High-model chat for each iteration. Do not implement these tasks in
  the architecture chat.
- Do not spawn subagents unless the user explicitly changes this rule.
- Read only `AGENTS.md`, `docs/agent-onboarding.md`, `SWIFT.md`, this plan, the
  two governing specs, and task-owned source/tests.
- Treat each iteration as a direct task. Do not create backlog files or run the
  backlog selector.
- Work only on `master`; preserve unrelated changes; stage only owned paths.
- One iteration ends with one scoped checkpoint commit and an exact verification
  report.
- A failing feasibility or privacy gate stops the iteration. Do not compensate
  with extra architecture.
- DEBUG-only probes must be removed before the iteration's commit unless the QA
  contract explicitly keeps a bounded qualification route.

## Runtime QA And Computer Use Contract

Computer Use is mandatory for user-visible and interactive testing. Passing
unit tests, reading source, rendering an isolated screenshot, or using only
`simctl` does not qualify a flow that a user performs by tapping the app or
keyboard.

- Use CLI/Xcode tooling for builds, test execution, installation, log capture,
  and deterministic state preparation.
- Use Computer Use for the actual Mac-visible UI: Xcode, iOS Simulator, System
  Settings when authorized, and iPhone mirroring or device UI when available.
- Inspect fresh application state before acting and again after each meaningful
  action. Prefer accessibility-element actions; use screenshot coordinates only
  when the control is not exposed through accessibility.
- For Simulator QA, launch HoldType through the repository's sanitized
  verification path so automated checks do not interact with live Keychain.
  Never type a login-keychain password or click `Always Allow`.
- Exercise the real production shell and embedded keyboard. Qualification routes
  may prepare deterministic state, but they cannot replace a normal cold-launch
  and real-navigation pass.
- Capture screenshots only after performing the corresponding interaction.
  Evidence must name the build/commit, device or Simulator, OS, appearance,
  starting state, actions, and observed result.
- For physical-device work, first use Computer Use through any available
  Xcode/device-mirroring UI. If a required device action cannot be controlled
  from the Mac, request only the minimal user handoff and keep that row pending
  until its actual result is observed.
- If Computer Use is unavailable, fails to expose the required UI, or was not
  used, report the exact reason and leave the interactive gate pending. Do not
  replace it with a source-inspection claim.
- Follow Computer Use confirmation requirements for system-setting changes,
  credentials, uploads, or other consequential UI actions. Previously granted
  task authority does not permit entering secrets or bypassing security prompts.

## Iteration Dashboard

| ID | Scope | Status | Depends On |
| --- | --- | --- | --- |
| KBD-MVP-0 | Product contract and execution plan | Completed 2026-07-14 | — |
| KBD-MVP-1 | Settings action and normal app shell | Completed 2026-07-14 | KBD-MVP-0 |
| KBD-MVP-2 | Signed-device background-session feasibility | Passed 2026-07-14 | KBD-MVP-1 |
| KBD-MVP-3 | Real recorder, OpenAI, and safe insertion | Implemented 2026-07-14; live smoke pending authorization | KBD-MVP-2 pass |
| KBD-MVP-4 | Setup, failure states, and release UX | Pending | KBD-MVP-3 |
| KBD-MVP-5 | Device qualification and TestFlight candidate | Pending | KBD-MVP-4 |

## KBD-MVP-1 — Settings And Normal App Shell

Status: completed 2026-07-14.

### Purpose

Remove the known keyboard-to-History launch risk and restore a trustworthy
ordinary app launch before changing the voice architecture.

### Scope

- Replace the keyboard History action, accessibility label, dependency, and
  status handling with a Settings gear.
- Use only the public system Settings URL through the extension context.
- Remove the keyboard History opener and `holdtype://history` dependency when no
  other production consumer needs it. Do not remove the containing-app History
  tab or screen.
- Kill any running qualification instance and verify a normal cold launch.
- Confirm that iPhone production root uses the tab shell with Voice, Library,
  History, and Settings; a qualification route must not persist into a normal
  launch.
- Fix the root only if a real normal-launch defect is reproduced. Do not
  redesign navigation.

### Verification

- focused keyboard action/presentation tests;
- mandatory Computer Use pass: terminate any qualification instance, cold-launch
  the normal app, tap all four tabs, open History, return between destinations,
  present the real embedded keyboard, and tap its Settings gear;
- normal iPhone Simulator cold launch with four visible tabs;
- History selection retains the tab bar;
- Computer Use screenshots of the real keyboard in Light and Dark with the gear
  in the left position;
- public Settings request success/failure handling, with physical-device
  confirmation deferred only if no device is connected;
- generic iOS Debug build and `git diff --check`.

### Exit

The keyboard contains no History action or containing-app URL. The containing
app opens normally with four permanent destinations. One scoped commit records
the change.

### Evidence

- Focused iPhone Simulator tests passed: 35 tests in `KeyboardViewControllerTests`,
  `BrandStageKeyboardViewTests`, `KeyboardCommandSurfaceIOSTests`,
  `IOSContainingAppShellTests`, and `IOSVoicePlatformPlistTests`.
- A normal cold launch on iPhone 16, iOS 18.6, with no qualification launch
  environment showed Voice, Library, History, and Settings. Selecting History
  through Computer Use kept the tab bar visible; no production navigation fix
  was needed.
- The Settings action uses `UIApplication.openSettingsURLString` through the
  extension context. Focused tests cover successful and failed completion, and
  failure presents `Open Settings` before returning to `Ready`.
- The installed keyboard was checked in Light and Dark Mode with a fully visible
  Settings label and gear: [Light](qa/runs/assets/kbd-mvp-1-2026-07-14/keyboard-light.png)
  and [Dark](qa/runs/assets/kbd-mvp-1-2026-07-14/keyboard-dark.png).
- Generic iOS Simulator Debug and generic iOS device Debug builds succeeded,
  including the embedded keyboard extension. `git diff --check` passed.
- No signed physical iPhone was connected, so the plan's physical-device
  confirmation of public Settings navigation remains deferred to KBD-MVP-2.
  Full task evidence is recorded in
  [the KBD-MVP-1 QA note](qa/runs/kbd-mvp-1-settings-and-app-shell-2026-07-14.md).

### Ready-to-use prompt

> Implement KBD-MVP-1 from `docs/ios-keyboard-dictation-mvp-plan.md` on master.
> Replace the keyboard History action with a public system Settings gear and
> verify the ordinary iPhone tab shell. Do not touch recording, persistence,
> History contents, or unrelated UI. Read only the task-routed docs and files,
> add focused verification, run the required build/checks, update only this
> task's status/evidence, and create one scoped checkpoint commit. Do not create
> agents, branches, or backlog tasks. Use Computer Use for the real normal-launch,
> tab, keyboard, Settings, and Light/Dark interaction pass; tests or static
> screenshots alone are not acceptance evidence.

## KBD-MVP-2 — Physical Background-Session Feasibility

Status: Passed (2026-07-14).

### Purpose

Prove the only risky platform boundary before connecting production provider or
growing user-visible behavior.

### Preconditions

- KBD-MVP-1 is committed;
- one signed physical iPhone is connected and trusted;
- app and extension use matching development signing and App Group entitlement;
- the user grants microphone permission and enables Allow Full Access;
- no live OpenAI key is needed for this iteration.

If no qualifying physical iPhone is available, record the exact missing
precondition and stop. Simulator evidence must not be presented as a pass.

### Revised KBD-MVP-2 Qualification Split (2026-07-14)

For this feasibility spike, physical and Simulator evidence have separate,
explicit ownership:

- the signed physical iPhone proves only containing-app behavior: explicit
  bounded session start/stop, real app-owned recording, honest `Listening…`,
  Finish, Cancel, expiry, audio release, and the microphone indicator when the
  selected device-capture surface exposes it;
- a DEBUG-only containing-app probe exposes Start Recording, Finish Recording,
  and Cancel Recording so those physical checks never require presenting the
  custom keyboard through iPhone Mirroring;
- iPhone Mirroring is used only to operate and observe the containing app. Do
  not attempt to present or qualify HoldType Keyboard through Mirroring because
  the Mac is treated as an external keyboard and suppresses the onscreen
  keyboard;
- Mirroring must be disconnected before real capture if macOS reports
  `iPhone microphone is not available from Mac`; in that environment it may
  inspect only non-recording app state, while the signed DEBUG app route or a
  physical-device UI test drives the recorder directly on iPhone;
- the actual extension UI, bounded App Group command/state reduction,
  one-request/one-insertion behavior, Cancel-without-insertion, `Open HoldType`,
  Full Access on/off presentation, punctuation, Space, Delete, Return, and
  Globe are qualified in Simulator plus focused tests;
- this split may pass KBD-MVP-2, but it does not waive the later signed-device
  keyboard/host-app matrix required before TestFlight or release.

This is not a Simulator-only pass: real microphone ownership and recording
lifecycle remain mandatory physical-device evidence. The Simulator owns only
the keyboard-extension half of the spike.

### Scope

- Enable the production Full Access declaration while preserving restricted
  editing behavior.
- Add the smallest explicit `Start Keyboard Session` / Stop surface in Voice.
- Add only the two records allowed by the Record Budget.
- Let the extension send Start, Finish, and Cancel for one request id.
- Let an already-running app-owned session acknowledge and control real audio
  capture while the containing app is backgrounded.
- Return a deterministic non-provider test string after Finish so the real
  keyboard can prove one insertion into Notes.
- Record timestamps and state only in opt-in debug evidence; never log audio or
  host text.
- Remove the deterministic probe from production behavior before commit, or
  isolate it behind the repository's existing DEBUG qualification boundary.

### Required qualification proof

Physical containing-app probe:

1. Start the bounded session in HoldType on the signed iPhone.
2. Use the DEBUG Start Recording probe and confirm the app's real recorder
   returns `record() == true` and `isRecording == true` before `Listening…`
   appears. Record the system microphone indicator when the wired capture
   surface includes it; do not fabricate that observation when it does not.
3. Use Finish Recording and confirm the recorder stops and the audio session
   deactivates before the deterministic non-provider result becomes ready.
4. Repeat with Cancel Recording and confirm capture stops with no result.
5. Stop or expire the session and confirm the app returns to a stopped state
   without retaining idle audio.

Simulator keyboard proof:

1. Present the actual HoldType Keyboard in a standard host field.
2. Prove Start, Finish, and Cancel write one bounded current command and reduce
   the matching app-written current state/result.
3. Prove the deterministic result inserts exactly once through
   `UITextDocumentProxy`, while Cancel inserts nothing.
4. Prove stopped/expired state shows `Open HoldType`.
5. With Full Access disabled, prove punctuation, Space, Delete, Return, and
   Globe remain functional.

Use Computer Use through iPhone Mirroring only for non-recording inspection of
the physical containing app, and disconnect it before capture when the system
reports the iPhone microphone unavailable from Mac. Drive the recording probe
directly on the signed iPhone through the DEBUG app route or a physical-device
UI test. Use Simulator UI plus focused tests for the keyboard half. Record the
two evidence lanes separately and never describe Simulator microphone behavior
as physical proof.

### Stop conditions

Stop without KBD-MVP-3 if the proof requires:

- microphone access in the extension;
- launching HoldType from the keyboard;
- private Settings or responder-chain APIs;
- recording or retaining spoken content while idle;
- indefinite silent-audio playback solely to avoid suspension;
- more than the two bounded records;
- an unbounded polling or retry loop;
- no real signed-iPhone proof of the containing-app recording lifecycle.

### Exit

A QA record names device, OS, commit, signing boundary, exact steps, expected
and actual results, and privacy/energy observations. The dashboard marks either
`Passed` or `Failed — stop`; it never says complete from partial evidence. A
failed spike removes its incomplete production implementation before commit and
commits only the spec/QA/status evidence needed to preserve the decision.

### Evidence

- KBD-MVP-1 was committed at `d5b2c0a` on `master` before this spike began.
- A connected and trusted iPhone 14 Pro Max (`iPhone15,3`) running iOS 26.5.2
  (`23F84`) built and installed with Apple Development signing for team
  `PUA6HH22D7`. The signed app and extension both contain the matching
  `group.app.holdtype.HoldType.shared` entitlement.
- The signed DEBUG containing-app route confirmed real app-owned recording
  before publishing Listening. Finish stopped recording before publishing the
  deterministic non-provider result; a separate Cancel run stopped recording
  without a result. No extension recorder or live provider path ran.
- The actual HoldType extension in Simulator retained punctuation, Space,
  Delete, Return, and Globe with Full Access off. Focused controller/document-
  proxy tests proved bounded Start/Finish/Cancel reduction, exactly one result
  insertion, Cancel with no insertion, expiry, and `Open HoldType`.
- Settings and Latest retained their full intrinsic titles across 320, 375,
  393, and 430-point hosts. The interactive restricted-access pass is captured
  in [the Simulator screenshot](qa/runs/assets/kbd-mvp-2-2026-07-14/simulator-full-access-off.jpeg).
- All 34 focused tests in five suites passed. The bridge remains limited to one
  extension-written command record and one app-written state/result record,
  with no forbidden persistence, polling, keepalive, provider, or launch path.
- Full evidence and the exact rerun precondition are recorded in
  [the KBD-MVP-2 QA note](qa/runs/kbd-mvp-2-physical-feasibility-2026-07-14.md).

### Ready-to-use goal prompt

> Prove KBD-MVP-2 from `docs/ios-keyboard-dictation-mvp-plan.md` on a signed
> physical iPhone. Implement only the minimal app-owned background session, the
> two bounded App Group records, real Start/Finish/Cancel audio control, and one
> deterministic keyboard insertion in Notes. Do not connect OpenAI, redesign
> UI, add persistence families, or continue after a stop condition. Use no
> agents or backlog. Finish with a pass/fail QA record, focused verification,
> dashboard update, and one scoped checkpoint commit if repository files
> changed. On failure, remove the incomplete production spike before committing
> and preserve only the bounded evidence. Use Computer Use for every available
> Xcode, device-mirroring, keyboard, and Notes interaction; if the physical UI
> cannot be controlled or observed, leave the gate pending rather than claiming
> a pass.

## KBD-MVP-3 — Production Voice Pipeline And Safe Insertion

Status: implemented 2026-07-14; automated acceptance passed; live-provider UI
smoke remains pending explicit user authorization.

### Purpose

Replace the feasibility result with the existing app-owned dictation pipeline
without duplicating recorder, provider, Latest, or History ownership.

### Preconditions

- KBD-MVP-2 is recorded as Passed on a signed physical iPhone.

### Scope

- Route keyboard Start/Finish/Cancel through the existing recorder/session
  arbitration instead of adding a second recorder.
- Run existing OpenAI transcription, correction/translation, Dictionary, Voice
  Emoji Commands, and Replacement Rules in their existing order.
- Commit accepted text through existing Latest and optional History behavior.
- Publish only the matching transient result needed by the live keyboard.
- Auto-insert once only when request id, extension lifetime, and current host
  ownership still match.
- When ownership is not proven, do not insert and leave the accepted result in
  Latest.
- Keep existing foreground Voice, Pending Retry/Discard, History, and Recording
  Cache behavior unchanged.

### Verification

- deterministic tests for Start, Finish, Cancel, timeout, stale command, stale
  result, duplicate event, and one insertion;
- foreground Voice versus keyboard-session mutual exclusion;
- provider failure leaves no fabricated Listening or Processing state;
- accepted result reaches Latest and History exactly once;
- ownership loss suppresses auto-insert without losing Latest;
- mandatory Computer Use pass through the real containing app and embedded
  keyboard for Start, Finish, Cancel, accepted insertion, and Latest fallback;
- focused full iOS Simulator regression, persistence tests affected by the
  boundary, generic Release build, macOS build, and `git diff --check`;
- one live device smoke only after explicit user authorization and using the
  configured app-owned provider key. The agent never enters or prints the key.

### Exit

The deterministic probe is gone. A real keyboard request can complete the
existing production pipeline and insert one accepted result safely.

### Evidence

- The KBD-MVP-2 gate was confirmed Passed from its signed iPhone 14 Pro Max
  (`iPhone15,3`) evidence before implementation began.
- Keyboard Start, Finish, and Cancel now enter the existing process-owned
  foreground Voice workflow, recorder, provider, text-rule, Latest, optional
  History, and Recording Cache boundaries. No second recorder, persistence
  package, History store, transaction coordinator, outbox, receipt, or retry
  queue was added.
- Matching transient publication is bound to the keyboard request and the
  accepted source attempt. Automatic insertion additionally requires the same
  extension lifetime and host-context generation and remains exactly once.
- Focused workflow and package tests cover Start, Finish, Cancel, timeout,
  provider failure, stale command/result, duplicate delivery, ownership loss,
  foreground/keyboard arbitration, and one Latest/History acceptance. The full
  iOS Simulator regression passed 1,060 tests on iPhone 16, iOS 18.6.
- HoldTypeDomain passed 165 tests, HoldTypeOpenAI 118, HoldTypePersistence 200,
  and HoldTypeIOSCore 53. Generic iOS Release and macOS builds succeeded, and
  `git diff --check` passed.
- Computer Use confirmed the production containing-app session reaches
  `Ready for HoldType Keyboard` and the real embedded extension presents the
  production surface without the deterministic probe. Full Access was off in
  that Simulator state. It was not changed, and no live OpenAI request or key
  access occurred. The accepted live-provider insertion/fallback smoke remains
  pending the explicit authorization required by this plan.
- Full implementation and verification detail is recorded in
  [the KBD-MVP-3 QA note](qa/runs/kbd-mvp-3-production-pipeline-2026-07-14.md).

### Ready-to-use prompt

> Implement KBD-MVP-3 from `docs/ios-keyboard-dictation-mvp-plan.md` after
> confirming KBD-MVP-2 is Passed. Reuse the existing app-owned recorder, OpenAI,
> text rules, Latest, History, and Recording Cache boundaries. Replace the
> deterministic result with the real production pipeline and insert exactly
> once only for the same live request/host context; otherwise preserve Latest.
> Add no new persistence family or unrelated refactor. Run focused and baseline
> verification, update task evidence, and create one scoped commit on master.
> Do not create agents, branches, or backlog tasks. Use Computer Use for the
> actual app/keyboard interaction flow; automated tests alone do not complete
> this iteration.

## KBD-MVP-4 — Setup, States, And Release UX

### Purpose

Make the proven vertical slice understandable and recoverable without adding
new product areas.

### Scope

- Finish setup for keyboard enablement, Allow Full Access, microphone
  permission, provider readiness, and one fixed maximum 60-minute session.
- Make Start/Stop session state visible in Voice and Privacy.
- Implement the exact keyboard state vocabulary from the UX spec.
- Ensure `Listening…` and `Processing…` reflect acknowledged app state.
- Restore Ready after success; show no transcript preview or verbose help in the
  keyboard.
- Handle session expiry, Full Access removal, microphone denial, offline,
  provider timeout, interruption, and app-process loss.
- Set `hasDictationKey` consistently with the physically proven HoldType voice
  action so the system and HoldType do not present misleading duplicate voice
  controls.
- Finalize Light/Dark, VoiceOver labels, Reduce Motion, Increase Contrast, and
  compact-height layout without changing the selected composition.

### Verification

- presentation/state tests for every vocabulary item and transition;
- setup state tests with Full Access and microphone allowed/denied;
- normal app tabs and History remain intact;
- keyboard remains usable in restricted mode;
- mandatory Computer Use traversal of setup, session controls, each recoverable
  user state that can be induced safely, and the normal four-tab shell;
- Light/Dark screenshots on compact and standard iPhone captured after the real
  Computer Use interaction flow;
- no new placeholder, long keyboard copy, or app-launch action;
- full iOS regression, Release build, macOS build, and `git diff --check`.

### Exit

The full MVP path is understandable from setup through inserted text, with
short truthful recovery states and no unfinished control.

### Ready-to-use prompt

> Implement KBD-MVP-4 from `docs/ios-keyboard-dictation-mvp-plan.md`. Finish
> only setup, the bounded Keyboard Dictation Session UX, exact compact keyboard
> states, permission/failure recovery, accessibility, and existing Brand Stage
> appearance. Do not add product areas, QWERTY, partial transcription, or new
> persistence. Preserve the four-tab app and History behavior. Run the specified
> tests/screenshots/builds, update task evidence, and create one scoped master
> commit without agents or backlog work. Use Computer Use for setup, keyboard
> state transitions, navigation, accessibility-visible labels, and Light/Dark
> evidence; do not accept source inspection as UI QA.

## KBD-MVP-5 — Device Qualification And TestFlight Candidate

### Purpose

Turn engineering-complete behavior into one release candidate. This iteration
fixes discovered release blockers only; it does not add features.

### Scope

- Reconcile final marketing version/build with the V1.1 release designation.
- Produce a distribution-signed archive with matching app/extension App Group
  entitlements.
- Generate and inspect Xcode privacy evidence and the physical App Privacy
  Report.
- Run the signed physical-iPhone matrix below.
- Complete App Store Connect privacy answers, required URLs, screenshots,
  review notes, and keyboard setup instructions as operator-facing artifacts.
- Upload an internal TestFlight build and perform a bounded dogfood pass.
- Fix only P1/P2 blockers in the existing MVP scope, each as a small checkpoint.

### Physical matrix

- install, enable keyboard, Allow Full Access on/off, Globe;
- Notes, Messages, Mail, Safari, and two third-party standard text fields;
- secure field, phone pad, and host keyboard opt-out;
- Space cursor gesture, Delete repeat, adaptive Return, punctuation;
- Settings action;
- session start, Stop, expiry, background/foreground, Low Power Mode;
- Start, Finish, Cancel, interruption, provider timeout, offline recovery;
- live microphone -> OpenAI -> rules -> Latest -> History -> same-request
  insertion;
- host focus change and extension eviction suppress auto-insert;
- app termination preserves Latest or one Pending attempt as specified;
- Keychain, Data Protection, microphone indicator, and no idle-content capture;
- VoiceOver and Dynamic Type smoke in both appearances.

Drive every Mac-visible row with Computer Use, including Xcode Organizer,
Simulator, iPhone mirroring, and the real keyboard. Preserve screenshots and a
row-by-row evidence ledger. Any row that could not be operated or observed stays
pending and prevents a release-ready claim.

### Exit

One exact build is installed through TestFlight and has no unresolved P1/P2
issue. The release record distinguishes engineering evidence, TestFlight
evidence, remaining App Review risk, and final submission state. Upload alone
does not mean App Store ready.

### Ready-to-use prompt

> Execute KBD-MVP-5 from `docs/ios-keyboard-dictation-mvp-plan.md` as a release
> qualification task, not a feature project. Build one distribution/TestFlight
> candidate, run the bounded signed-device matrix, inspect privacy/signing, and
> prepare the required App Store artifacts. Fix only P1/P2 blockers inside the
> approved MVP scope. Do not add features, redesign persistence, create branches,
> or use agents. Use Computer Use for all available Xcode, Organizer, Simulator,
> device-mirroring, keyboard, and TestFlight UI checks. Record exact pass/fail
> evidence and make scoped checkpoint commits for any fixes; an unobserved UI
> row remains pending.

## Handoff Protocol

For each new chat:

1. Select the High model.
2. Paste only the matching ready-to-use prompt.
3. Do not start another implementation chat until the current one reports its
   checkpoint commit and final task status.
4. If the chat finds a product decision not settled by the governing specs, it
   stops and returns the question to the architecture chat.
5. If the chat completes, the next chat reads the committed plan and task status
   from the repository; no conversational history transfer is required.

The architecture chat remains the place for scope decisions and gate review.
It is not the implementation worker.
