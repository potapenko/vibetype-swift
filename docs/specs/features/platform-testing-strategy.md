# Platform Testing Strategy

## Goal

Keep HoldType development verifiable on each small backlog task while avoiding
fragile full-app checks for every change.

The active product phase is the native macOS menu bar MVP. iOS companion,
simulator, keyboard-extension, and shared cross-platform QA remain future v2
scope unless a direct user request or explicitly v2-labeled task opts into
deferred lanes.

Testing must prove the changed behavior at the smallest useful layer, then add
platform smoke evidence when a task touches the platform surface or a
user-visible interaction that can only be trusted after launching the app.

Detailed MVP service seams and fake/manual boundaries are defined in
`verification-strategy.md`.

## Test Layers

### Unit And Model Tests

Use unit tests for deterministic app behavior:

- recording and transcription state transitions
- settings defaults and persistence mapping
- error mapping
- timeout behavior with fake clocks or bounded delays
- clipboard and paste decisions through fake boundaries
- OpenAI request construction without live network calls

Normal tests must not call the live OpenAI API, require real microphone input,
or depend on real system permission prompts.

### macOS Build And Runtime Smoke

For normal Swift behavior changes, the baseline verification is a macOS build
or test command plus diff hygiene.

When Build macOS Apps or macOS-capable XcodeBuildMCP is available in the active
Codex session, use it for macOS build/run/test, screenshots, runtime UI
snapshots, or simple interactions that match the selected task. If the macOS
MCP surface is missing or unavailable, use the documented `xcodebuild` fallback
and bounded Computer Use runtime smoke for changed UI.

Use macOS runtime smoke for tasks that change the running app surface or the
user action behind that surface:

- menu bar item creation
- menu contents
- Settings window behavior
- floating indicator visibility
- permission-state UI
- active-app paste handoff
- buttons, toggles, fields, labels, status text, or menu actions that a user
  can operate
- end-to-end flows that connect visible UI to a newly implemented service seam

Runtime smoke should be bounded. If the app cannot be launched or inspected
quickly, record the blocker and keep unit/build verification explicit.

### Computer Use Smoke

Computer Use is the required visual smoke layer for a changed macOS runtime
surface unless the task is model/service-only or the surface is explicitly
blocked in the current environment.

Use it to capture evidence that a user-visible surface exists and can be
interacted with, such as opening the menu bar item or Settings window. Do not
use it as the primary assertion layer for service logic.

Every implementation run must report a runtime QA decision:

- `required`: Computer Use was used to launch or relaunch the app and inspect
  the changed surface or interaction.
- `not_applicable`: the change was non-UI service/model behavior and was
  covered by build, unit, or fake-backed test evidence.
- `blocked`: Computer Use or the app run could not reach the relevant surface
  within the bounded run; report the blocker and the last successful
  build/test evidence.

### v2 iOS Simulator Checks

Use XcodeBuildMCP / Build iOS Apps only for explicit future v2 iOS targets:

- simulator build
- simulator test
- screenshot capture
- UI snapshot or simple interaction when available

iOS checks should apply to iOS-specific targets once a v2 task explicitly opts
into deferred iOS lanes. They are not required for ordinary macOS MVP work,
including shared SwiftUI files used by the macOS app, unless the selected task
is explicitly scoped as cross-platform v2 verification. Operational MCP usage
and fallbacks live in `docs/agent-tooling.md`.

When an explicit v2 shared SwiftUI surface changes, verification should
include:

- typechecking or building the shared source against both macOS and iOS SDKs;
- an iOS simulator build/run/screenshot through XcodeBuildMCP when the build
  product can be produced within the bounded run;
- a QA blocker note when the simulator build or launch times out before a
  screenshot can be captured.

## v2 iOS Keyboard Constraints

The iOS keyboard path is a separate platform architecture, not a direct port of
the macOS menu bar flow. The product split is defined in
`ios-keyboard-feasibility.md`.

Product constraints:

- an iOS custom keyboard must provide a way to switch to the next keyboard
- it is unavailable in secure text fields and some phone-pad contexts
- keyboard extensions are sandboxed and may need Open Access for network or
  shared-container behavior
- dictation must not be assumed to run directly inside the keyboard extension
  because Apple's custom keyboard guidance documents microphone restrictions

The likely iOS product split is:

- containing app handles onboarding, settings, permissions, and any recording
  or network transcription flow that cannot safely live in the extension
- keyboard extension focuses on compact UI and text insertion
- shared SwiftUI screens may be reused where product behavior is common

This split is confirmed by `ios-keyboard-feasibility.md`,
`ios-keyboard-experience.md`, and `ios-keyboard-shared-state.md`. The active
implementation sequence and physical-device gates live in
`docs/ios-keyboard-development-plan.md`.

## Required Evidence By Task Type

- Docs/spec-only: `git diff --check`
- Swift model or service behavior: macOS test command plus `git diff --check`
- Swift app shell, UI behavior, or user-visible interaction: macOS build
  command plus `git diff --check`; run bounded Computer Use smoke against the
  changed surface or report a concrete blocker
- External-service behavior: fake-backed tests with bounded timeout behavior;
  no live provider call in normal automation
- Permission or microphone behavior: fake-backed tests for app logic; bounded
  runtime smoke only when the selected task asks for platform evidence
- v2 iOS behavior: XcodeBuildMCP simulator build/test/screenshot only when
  deferred iOS lanes were explicitly included and the selected task touches
  that surface; if full `xcodebuild` or MCP build/run times out without
  compiler diagnostics, record the timeout and keep SDK typecheck evidence
  explicit

For the Phase 0 keyboard spike, simulator verification must additionally prove
that the containing app embeds the `.appex` and that the processed extension
plist declares `com.apple.keyboard-service`. Full Access, secure-field fallback,
keyboard switching, app return, microphone lifecycle, process eviction, and
iPad floating layout remain physical-device evidence.

## Sources

- Apple App Extension Programming Guide: Custom Keyboard
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html`
- Apple Platform Security: Supporting extensions
  `https://support.apple.com/guide/security/supporting-extensions-secabd3504cd/web`
- Apple Developer: Configuring open access for a custom keyboard
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`
