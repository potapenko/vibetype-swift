# Brownfield Discovery

Status: initial discovery snapshot.

## Summary

`vibetype-swift` currently contains a minimal Xcode-generated macOS SwiftUI
project plus spec-first documentation. It does not yet implement the menu bar
dictation MVP.

## Existing Implementation

- Xcode project: `vibetype/vibetype.xcodeproj`
- App target: `vibetype`
- Unit test target: `vibetypeTests`
- UI test target: `vibetypeUITests`
- Scheme: `vibetype`

Current source files:

- `vibetype/vibetype/vibetypeApp.swift`
  - SwiftUI `@main` app.
  - Uses a default `WindowGroup`.
  - Opens `ContentView`.
- `vibetype/vibetype/ContentView.swift`
  - Default template view with a globe symbol and `Hello, world!`.
- `vibetype/vibetypeTests/vibetypeTests.swift`
  - Swift Testing placeholder.
- `vibetype/vibetypeUITests/vibetypeUITests.swift`
  - XCTest UI placeholder.

## Not Implemented Yet

- menu bar app shell
- settings window
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
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
```

Use this command when test-covered behavior changes:

```sh
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
```
