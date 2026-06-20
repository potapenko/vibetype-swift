# Platform Testing Strategy

## Goal

Keep VibeType development verifiable on each small backlog task while avoiding
fragile full-app checks for every change.

Testing must prove the changed behavior at the smallest useful layer, then add
platform smoke evidence only when a task touches the platform surface.

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

Use macOS runtime smoke only for tasks that change the running app surface:

- menu bar item creation
- menu contents
- Settings window behavior
- floating indicator visibility
- permission-state UI
- active-app paste handoff

Runtime smoke should be bounded. If the app cannot be launched or inspected
quickly, record the blocker and keep unit/build verification explicit.

### Computer Use Smoke

Computer Use is the preferred visual smoke layer for the running macOS app.

Use it to capture evidence that a user-visible surface exists and can be
interacted with, such as opening the menu bar item or Settings window. Do not
use it as the primary assertion layer for service logic.

### iOS Simulator Checks

Use XcodeBuildMCP / Build iOS Apps for future iOS targets:

- simulator build
- simulator test
- screenshot capture
- UI snapshot or simple interaction when available

iOS checks should apply to iOS-specific targets and shared SwiftUI surfaces
once those targets exist. They are not required for a macOS-only task unless
the selected task explicitly changes shared iOS/macOS code.

## iOS Keyboard Constraints

The iOS keyboard path is a separate platform architecture, not a direct port of
the macOS menu bar flow.

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

This split must be confirmed by future iOS specs before implementation.

## Required Evidence By Task Type

- Docs/spec-only: `git diff --check`
- Swift model or service behavior: macOS test command plus `git diff --check`
- Swift app shell or UI behavior: macOS build command plus `git diff --check`;
  add Computer Use smoke when the task changes visible runtime UI
- External-service behavior: fake-backed tests with bounded timeout behavior;
  no live provider call in normal automation
- Permission or microphone behavior: fake-backed tests for app logic; bounded
  runtime smoke only when the selected task asks for platform evidence
- iOS or shared SwiftUI behavior: XcodeBuildMCP simulator build/test/screenshot
  when an iOS target exists and the selected task touches that surface

## Sources

- Apple App Extension Programming Guide: Custom Keyboard
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html`
- Apple Platform Security: Supporting extensions
  `https://support.apple.com/guide/security/supporting-extensions-secabd3504cd/web`
- Apple Developer: Configuring open access for a custom keyboard
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`
