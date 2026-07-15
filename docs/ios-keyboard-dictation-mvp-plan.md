# HoldType iOS Keyboard Handoff Implementation Plan

Status: approved product direction; implementation not started; revised
2026-07-15.

This file is the durable execution plan for the HoldType Keyboard to Voice
handoff. Goal runs and direct implementation chats must read this file from the
current checkout instead of reconstructing the plan from chat history.

Product behavior remains governed by:

- `docs/specs/features/ios-keyboard-handoff-and-delivery.md` for the keyboard
  microphone, app handoff, request continuity, and text delivery contract;
- `docs/specs/features/ios-keyboard-experience.md` for keyboard composition,
  the central Voice indicator, the voice/error area, and accessibility;
- `docs/specs/features/ios-settings-guided-recovery.md` for exact setup routing
  and the rule that setup repair does not replay an earlier action;
- `docs/specs/features/ios-v1-release.md` for the standalone iOS product.

The first implementation slice must update any conflicting clauses in those
specs before changing production behavior.

This is a direct product plan, not a backlog. Work stays on `master`, preserves
unrelated changes, and ends every file-changing slice with focused verification
and one scoped checkpoint commit.

## Product Decision

HoldType remains a normal custom keyboard. Its Voice indicator is the single
primary dictation control.

The keyboard never tells the user to open HoldType, find a menu, or manually
prepare a Keyboard Session. If app-owned recording is not currently available,
the microphone tap opens HoldType automatically.

There are three user paths.

### Warm Session

```text
tap keyboard Voice indicator
    -> Listening
    -> speak
    -> tap again to finish
    -> Processing
    -> insert accepted text into the originating input
```

HoldType does not become foreground when the current bounded keyboard session
can already accept the request.

### Cold Session With Valid Setup

```text
tap keyboard Voice indicator
    -> keyboard writes a fresh bounded handoff intent
    -> HoldType opens automatically
    -> app validates setup and starts real app-owned capture
    -> a large handoff sheet rises over the existing Voice screen
    -> user swipes right on the system bottom bar
    -> recreated keyboard reconnects in Listening
    -> finish, process, and insert exactly once
```

The keyboard tap is the explicit start action. When setup is valid, the user
does not press a second Voice button inside HoldType. The sheet is informational
and cancellable; it is not a preparatory session screen.

### Setup Recovery

```text
tap keyboard Voice indicator
    -> HoldType opens automatically
    -> preflight identifies one concrete setup blocker
    -> no recording and no handoff sheet
    -> HoldType opens the exact owning Settings field or permission surface
    -> user repairs setup
    -> user returns to the original app and taps the keyboard indicator again
```

Setup repair never replays the stale request, starts recording, or contacts a
provider automatically. A fresh keyboard tap creates a fresh request.

## Non-Negotiable Boundaries

- Ordinary standalone Voice behavior must not change.
- The existing Voice screen, recorder, workflow, permission owners, provider
  pipeline, Latest, and History remain authoritative.
- The handoff sheet is a separate presentation layer over Voice, not a copied
  recorder or second Voice implementation.
- The keyboard extension never records audio and never receives credentials.
- The app never reports Listening before the real recorder acknowledges capture.
- Setup instructions do not appear in the keyboard. The keyboard may show short
  operational states and compact failures in its existing voice/error area.
- An ordinary app launch never starts recording or presents the handoff sheet.
- A stale, repeated, malformed, or superseded handoff never starts a second
  capture.
- Unsafe destination identity never inserts into a different text field.
- Accepted text is inserted automatically at most once.
- If the complete keyboard behavior cannot ship, the product fallback is an
  app-only release, not a manual-session keyboard.

## Keyboard Handoff Sheet Contract

The handoff presentation is a large SwiftUI sheet over the existing first Voice
screen. It is not a new tab, navigation destination, or replacement Voice page.

### Appearance

- large detent with the underlying Voice screen still visible around it;
- rounded top corners and one close button in the top-right corner;
- the existing HoldType Voice activity visual, reused rather than approximated;
- a short title, one return instruction, and a simple system-bottom-bar swipe
  illustration or animation;
- no Draft editor, Copy, History, setup controls, mode picker, or second Start
  button;
- localizable copy, Light and Dark appearance, Dynamic Type, VoiceOver, Reduce
  Motion, Reduce Transparency, and sufficient contrast.

### Presentation States

`starting`

- The request and setup are valid and app-owned capture is arming.
- The sheet may say `Starting dictation...` but must not claim Listening.
- The return gesture instruction is visually secondary until capture begins.

`listening`

- Real capture has started.
- Recommended copy:
  - title: `HoldType is listening`;
  - instruction: `Swipe right on the bottom bar to return to the app where you
    were typing.`;
  - supporting text: `Recording will continue.`
- The user performs the normal iOS app-switch gesture; HoldType does not promise
  a programmatic return to an arbitrary host app.

`cancelled` or terminal

- The sheet dismisses after explicit cancel, startup failure, expiry, or terminal
  request completion.
- It must not remain stale on a later ordinary HoldType launch.

### Close Semantics

- The close button cancels the keyboard-originated request.
- If capture is active, cancel stops it before dismissing the sheet.
- No partial result is automatically inserted after this cancellation.
- The underlying ordinary Voice screen returns to its normal Ready state.
- Interactive drag-to-dismiss is disabled while capture is active so the user
  cannot confuse dismissing the sheet with swiping on the system bottom bar.

## Setup Routing Matrix

The handoff must reuse the existing Voice preflight and guided Settings routing.
Do not duplicate configuration validity rules in the sheet or keyboard.

| Blocker | Destination | Handoff result |
| --- | --- | --- |
| Full Access unavailable | Keyboard Setup, targeted Full Access guidance | No sheet; fresh tap required after repair |
| OpenAI key missing or unreadable | OpenAI Settings, API key field | No sheet; fresh tap required |
| Transcription configuration invalid | Exact invalid Transcription field | No sheet; fresh tap required |
| Translation action without a valid route | Exact invalid Translation field | No sheet; fresh tap required |
| Correction action with invalid setup | Exact owning Writing Correction field | No sheet; fresh tap required |
| Provider disclosure not authorized | Privacy and Permissions, provider consent | No sheet; fresh tap required |
| Microphone permission undetermined | System permission prompt | Continue directly if granted while request is fresh |
| Microphone permission denied | Privacy and Permissions, microphone guidance | No sheet; fresh tap required |
| Keyboard setup incomplete | Keyboard Setup, exact incomplete step | No sheet; fresh tap required |
| App-private storage unavailable | Existing storage-unavailable presentation | Request expires; fresh tap required |

Offline, timeout, audio interruption, empty audio, and provider failure are
runtime failures, not setup routing. They use the existing bounded failure and
Latest recovery behavior.

## Minimal Architecture Change

The current app-owned recording and transcription pipeline stays in place. The
handoff adds a narrow launch-intent layer and extends the existing session bridge
only where round-trip identity requires it.

### Bounded Handoff Intent

Before opening HoldType, the keyboard writes one atomically replaced, expiring
intent containing only:

- opaque handoff/request ID;
- selected Standard, Translate, Improve, or combined action;
- creation and expiry timestamps;
- originating `UITextDocumentProxy.documentIdentifier` when iOS provides it;
- schema version.

The launch URL carries only the opaque routing identity. It never carries typed
text, transcript text, prompts, credentials, provider data, or audio.

### Session And Attempt Identity

The bridge must distinguish:

- a bounded app-owned keyboard session that can remain warm briefly; and
- an individual dictation attempt and result inside that session.

The exact schema should remain small and have one authoritative writer per
record. It must support fresh intent validation, session/attempt state,
document-bound reconnection, expiry, and an at-most-once delivery claim. It must
not become a durable queue, log, or second History database.

### App Ownership

A small app-owned handoff presentation owner coordinates:

- accepted handoff URL;
- preflight result;
- targeted setup routing;
- automatic session and capture start;
- sheet state;
- cancel and terminal dismissal.

It calls the existing Voice workflow and Keyboard Session coordinator. The
sheet itself contains no setup logic, recorder ownership, or provider code.

## Execution Rules

- Execute slices in order.
- KBD-FLOW-1 is the first implementation slice and builds the isolated sheet
  before any keyboard launch behavior.
- Stop after KBD-FLOW-1 and present visual evidence for user confirmation before
  wiring the production handoff.
- Do not run overlapping implementation work against the same keyboard, Voice,
  bridge, project, or spec files.
- Read `AGENTS.md`, `docs/agent-onboarding.md`, `SWIFT.md`, this plan, and only
  the governing specs/source files for the selected slice.
- Do not create branches, worktrees, or backlog tasks.
- Preserve unrelated edits and stage only task-owned paths.
- Use `apply_patch` for file edits.
- Every slice that changes files ends with focused verification and one scoped
  checkpoint commit.
- Do not spawn subagents unless the user explicitly asks.
- Do not use live OpenAI for automation unless the user explicitly authorizes a
  live-provider session.
- Physical-device work follows `docs/agent-tooling.md`, uses scoped `caffeinate`,
  and keeps Simulator, Mirroring, and signed-device claims separate.

## Delivery Sequence

| ID | Scope | Exit condition | Status |
| --- | --- | --- | --- |
| KBD-FLOW-0 | Durable strategy and execution plan | This checkout contains the approved plan and launch contract | Completed when this plan is checkpointed |
| KBD-FLOW-1 | Isolated Keyboard Handoff Sheet | Sheet states, cancel behavior, accessibility, and visual evidence pass without production routing changes | Completed 2026-07-15; awaiting user confirmation before KBD-FLOW-2 |
| KBD-FLOW-2 | Keyboard launch intent and app URL route | Missing session writes a bounded intent and opens only a matching HoldType route; warm path stays direct | Pending |
| KBD-FLOW-3 | Shared Voice preflight and targeted setup recovery | Every setup blocker routes to its exact owner; no blocker presents Listening or the sheet | Pending |
| KBD-FLOW-4 | Automatic app-owned capture and live sheet | A valid cold request starts real capture once and presents the sheet as Starting then Listening | Pending |
| KBD-FLOW-5 | Keyboard reconnection and state UX | A recreated extension reconnects by session, attempt, and document identity with no manual instructions | Pending |
| KBD-FLOW-6 | Finish, exactly-once delivery, and warm reuse | Finish processes once, safe output inserts once, and an unexpired session returns to Ready | Pending |
| KBD-FLOW-7 | Legacy-copy cleanup and product completion | Manual-session recovery copy is absent and ordinary Voice remains unchanged | Pending |
| KBD-FLOW-8 | Signed-device and TestFlight qualification | Full physical matrix passes or an explicit app-only release decision is recorded | Pending |

## KBD-FLOW-1 - Isolated Keyboard Handoff Sheet

### Scope

1. Update the governing spec language for a temporary sheet over Voice.
2. Add a neutral sheet presentation model with `starting` and `listening`.
3. Add `IOSKeyboardHandoffSheet` using the current Voice visual language.
4. Add explicit cancel/close behavior through injected callbacks.
5. Add a UI qualification route or deterministic host that does not affect the
   production launch path.
6. Cover Light/Dark, compact/regular width, Dynamic Type, VoiceOver, and Reduce
   Motion.
7. Capture visual evidence and stop for user review.

### Non-Goals

- no keyboard URL launch;
- no App Group intent;
- no real microphone or provider work;
- no change to ordinary Voice behavior;
- no production sheet presentation.

### Verification

- focused sheet presentation and interaction tests;
- iOS build and relevant test target;
- Simulator visual QA with scoped `caffeinate`;
- `git diff --check`;
- scoped checkpoint commit.

## KBD-FLOW-2 - Intent And Launch Routing

1. Add the bounded handoff intent record and atomic App Group store.
2. Give the keyboard microphone two branches:
   - valid warm session: use the existing Start path;
   - no valid session: write intent and open the handoff URL.
3. Keep the central Ready indicator visible when no session exists.
4. Add an `Opening HoldType` operational state without manual instructions.
5. Parse and validate the URL in the containing app.
6. Select Voice only for a valid fresh matching intent.
7. Make ordinary, malformed, expired, repeated, and superseded launches inert.
8. Route no-Full-Access launches to the existing targeted setup path.

Exit when deterministic tests prove routing identity and show that no launch
alone can falsely start capture.

## KBD-FLOW-3 - Preflight And Setup Recovery

1. Expose a structured keyboard-handoff preflight result from the existing Voice
   workflow instead of duplicating its checks.
2. Map every `RecoveryDestination` to `IOSSettingsAttention` and the exact owning
   field.
3. Add a correction-specific attention route only if the current correction
   workflow can report a distinct invalid setup.
4. Handle microphone-undetermined inline; continue only after a granted result.
5. Consume/cancel requests routed to setup so returning from Settings cannot
   replay them.
6. Verify that setup repair requires a fresh keyboard tap.

Exit when each setup fixture opens the correct field and neither records nor
presents the handoff sheet.

## KBD-FLOW-4 - Automatic Capture And Live Sheet

1. Add an app-owned entry point that starts the bounded keyboard session and its
   first attempt from the validated handoff ID and selected action.
2. Reuse the existing keyboard Voice workflow, recorder, permission owner,
   provider pipeline, and accepted-output persistence.
3. Present the sheet in `starting` while arming.
4. Transition to `listening` only after real recorder acknowledgement.
5. Keep recording while the user swipes back and the app becomes background.
6. Make the close button cancel capture and dismiss to ordinary Voice Ready.
7. Dismiss on failure, expiry, cancellation, or terminal completion.
8. Keep normal app launches and ordinary Voice actions unchanged.

Exit when app integration tests and signed-device evidence prove one valid cold
handoff starts one real capture and one sheet.

## KBD-FLOW-5 - Reconnection And Keyboard State UX

1. Reconnect a recreated extension through session ID, attempt ID, request ID,
   and source document identity rather than extension-process identity.
2. Drive the keyboard through:
   `Ready -> Opening HoldType -> Listening -> Processing -> Ready`.
3. Keep the existing central Voice indicator visible through nominal states.
4. Route the microphone to Finish while Listening and keep Cancel explicit.
5. Remove instructional navigation copy from every keyboard recovery state.
6. Preserve compact operational and runtime failures in the existing error area.
7. Make a changed or missing destination identity ineligible for automatic
   insertion without discarding the accepted result.

Exit when recreation, return, focus-change, and expiry tests pass without a
wrong-field insertion or manual-session message.

## KBD-FLOW-6 - Delivery And Warm Session Reuse

1. Finish real capture from the keyboard.
2. Run existing transcription and selected post-processing exactly once.
3. Persist accepted output in canonical Latest and current History policy.
4. Claim delivery before `insertText` and never replay an uncertain insertion.
5. Fall back to Latest when document identity or delivery certainty is missing.
6. Acknowledge terminal attempt delivery separately from session lifetime.
7. Return an unexpired, healthy session to Ready for another keyboard attempt.
8. Let an expired or unavailable session cause the next microphone tap to open
   HoldType again.

Exit when one accepted result inserts at most once, fallback remains recoverable,
and warm/cold transitions are deterministic.

## KBD-FLOW-7 - Product Completion

1. Remove keyboard production strings and presentations for:
   - `Session not running`;
   - `Start a voice session`;
   - `Open HoldType -> Voice -> Keyboard Dictation Session`;
   - all written manual navigation instructions.
2. Keep the existing manual Keyboard Session surface temporarily as a bounded
   diagnostic tool until physical qualification proves it is no longer needed.
3. Reconcile the handoff, keyboard experience, release, and guided recovery
   specs.
4. Verify standalone Voice, Draft, Rules, History, Usage, Settings, and keyboard
   typing behavior for regressions.
5. Complete accessibility, localization readiness, diagnostics, and app-only
   packaging behavior.

Exit when production search finds no retired keyboard guidance and the ordinary
Voice flow has unchanged behavioral coverage.

## KBD-FLOW-8 - Signed-Device Qualification

Run a bounded matrix on a signed physical iPhone:

- cold and warm HoldType;
- valid setup and each targeted setup blocker;
- Full Access off/on;
- microphone undecided/granted/denied;
- Standard, Translate, Improve, and combined mode where available;
- sheet Starting, Listening, close, expiry, and stale relaunch;
- swipe back with extension retained and recreated;
- same field, changed field, and changed host app;
- Finish, Cancel, offline, timeout, interruption, provider failure, and app
  termination;
- automatic insertion, Latest fallback, and duplicate-delivery attempts;
- repeated dictation inside a healthy warm session;
- session expiry followed by a fresh cold handoff;
- ordinary standalone Voice with no sheet.

Use deterministic providers for normal automation. A live provider smoke requires
explicit user authorization. Record device, iOS version, build/commit, starting
state, actions, and observed result.

Then qualify one internal TestFlight candidate. App Review uncertainty does not
weaken the keyboard UX in advance. If the complete keyboard cannot ship, record
an explicit app-only release decision.

## Likely File Ownership

Specs and plan:

- `docs/ios-keyboard-dictation-mvp-plan.md`;
- `docs/specs/features/ios-keyboard-handoff-and-delivery.md`;
- `docs/specs/features/ios-keyboard-experience.md`;
- `docs/specs/features/ios-settings-guided-recovery.md`;
- `docs/specs/features/ios-v1-release.md`.

New or extended presentation and routing:

- `HoldTypeIOS/IOSKeyboardHandoffSheet.swift`;
- a small handoff presentation/owner type under `HoldTypeIOS/`;
- `HoldTypeIOS/IOSContainingAppShell.swift`;
- `HoldTypeIOS/IOSContainingAppDestination.swift`;
- `HoldTypeIOS/IOSVoiceHomeView.swift`;
- `HoldTypeIOS/IOSUIQualificationGallery.swift`.

Bridge and runtime:

- `KeyboardShared/KeyboardDictationBridge.swift` or one narrowly separated
  handoff-intent file;
- `KeyboardShared/KeyboardCommandSurface.swift`;
- `HoldTypeKeyboard/KeyboardViewController.swift`;
- `HoldTypeKeyboard/BrandStageKeyboardView.swift`;
- `HoldTypeIOS/IOSKeyboardDictationSessionCoordinator.swift`;
- `HoldTypeIOS/IOSForegroundVoiceWorkflow.swift`;
- `HoldTypeIOS/IOSForegroundVoiceRuntime.swift`;
- `HoldTypeIOS/IOSContainingAppSceneHost.swift`.

Tests should mirror these owners. Do not assume every listed file needs to
change; verify ownership at the start of each slice and keep the diff narrow.

## Definition Of Done

The feature is complete only when:

- a keyboard with no valid session contains no manual setup instructions;
- tapping its existing Voice indicator opens HoldType automatically;
- valid setup starts real recording and shows the handoff sheet without another
  app button tap;
- missing setup opens the exact repair location and requires a fresh keyboard
  tap afterward;
- the user swipes back and sees the keyboard in Listening even after extension
  recreation;
- Finish and Cancel control the same app-owned attempt;
- accepted text inserts into the originating input at most once;
- unsafe delivery stays in Latest;
- a healthy session supports its intended bounded warm path;
- an expired session restarts the cold handoff;
- ordinary standalone Voice behaves as before;
- signed-device and TestFlight evidence cover the complete path;
- the app-only release fallback remains coherent without a degraded manual
  keyboard.

## Goal Launch Contract

When the user authorizes goal execution, the goal must treat this file as the
source of truth, execute KBD-FLOW slices in order, and begin with KBD-FLOW-1
only. After the KBD-FLOW-1 checkpoint it must present visual evidence and wait
for user confirmation before wiring KBD-FLOW-2.
