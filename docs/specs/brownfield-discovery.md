# Brownfield Discovery

Status: current discovery snapshot after root Xcode flattening.

## Summary

`vibetype-swift` now keeps the Xcode project at the repository root next to
the spec-first documentation, backlog, scripts, and reference material.

The app has early macOS and iOS SwiftUI surfaces plus shared state/UI code. It
does not yet implement the full dictation MVP.

## Existing Implementation

- Xcode project: `vibetype.xcodeproj`
- App target: `vibetype`
- iOS containing app target: `vibetype-iOS`
- Unit test target: `vibetypeTests`
- iOS unit test target: `vibetypeIOSTests`
- UI test target: `vibetypeUITests`
- Schemes: `vibetype`, `vibetype-iOS`

Current source files:

- `vibetype/vibetypeApp.swift`
  - SwiftUI `@main` app.
  - Defines the macOS menu bar extra and Settings window.
- `vibetype/MenuBarView.swift`
  - Early menu bar surface with placeholder recording and transcript actions.
- `vibetype/SettingsView.swift`
  - Early Settings window surface with permission status.
- `vibetypeIOS/VibeTypeIOSApp.swift`
  - Minimal iOS containing app surface.
- `Shared/`
  - Shared SwiftUI setup/status UI and keyboard session state.
- `vibetypeTests/vibetypeTests.swift`
  - Swift Testing placeholder plus model/service tests.
- `vibetypeIOSTests/KeyboardSessionStateIOSTests.swift`
  - Hostless iOS unit coverage for shared keyboard state.
- `vibetypeUITests/vibetypeUITests.swift`
  - XCTest UI placeholder.

## Not Implemented Yet

- complete menu bar app shell
- complete settings form and persistence
- app state or dictation controller
- microphone permission handling
- audio recording
- OpenAI transcription
- Keychain storage
- global hotkey
- clipboard and auto-paste
- floating indicator
- transcript history
- product-specific tests

## Reference Material

- Product brief: `docs/openwhispr_swiftui_codex_tz.md`
- Specs: `docs/specs/features/`
- Copied OpenWhispr reference: `references/openwhispr-main/`

OpenWhispr is behavior evidence only. Its Electron/React/Node architecture is
not the target architecture.

## Verification Baseline

Use this build command for Swift behavior changes:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
```

Use this command when test-covered behavior changes:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
```
