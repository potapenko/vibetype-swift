# Swift Code Style And Project Rules

Apply these rules to all Swift, SwiftUI, AppKit interop, and Xcode project
changes in this repository.

This document is an engineering contract, not a product spec. Product behavior
still lives in `docs/specs/`.

## Source Basis

These local rules are based on official Swift and Apple references plus the
project's MVP constraints:

- Swift API Design Guidelines:
  `https://www.swift.org/documentation/api-design-guidelines/`
- The Swift Programming Language, especially concurrency:
  `https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/`
- SwiftUI documentation:
  `https://developer.apple.com/documentation/swiftui`
- SwiftUI data essentials and source-of-truth model:
  `https://developer.apple.com/videos/play/wwdc2020/10040/`
- SwiftUI identity, lifetime, and dependencies:
  `https://developer.apple.com/videos/play/wwdc2021/10022/`
- Swift Package Manager documentation:
  `https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/`
- Swift Testing and XCTest documentation:
  `https://developer.apple.com/documentation/testing`
  `https://developer.apple.com/documentation/xctest`
- Apple platform docs for the MVP boundaries:
  `https://developer.apple.com/documentation/SwiftUI/MenuBarExtra`
  `https://developer.apple.com/documentation/avfoundation/`
  `https://developer.apple.com/documentation/security/keychain-services`

## Core Style

- Prefer official Swift API Design Guidelines over ad hoc style preferences.
- Clarity at the point of use is more important than brevity.
- Use 4 spaces, no tabs, and keep line width readable near 100-120 characters.
- Use `UpperCamelCase` for types and protocols.
- Use `lowerCamelCase` for functions, properties, enum cases, and local values.
- Name side-effecting methods with imperative verbs: `startRecording()`,
  `saveAPIKey(_:)`, `insert(_:)`.
- Name non-mutating transformations as values or returned results when
  practical.
- Avoid unexplained abbreviations. Prefer `transcription` over `tx`, `audioURL`
  over `url2`, and `permissionStatus` over `perm`.
- Prefer `let` over `var`.
- Prefer small types and focused methods over large view or service files.
- Do not use force unwraps or force casts in production code unless the
  invariant is local, obvious, and documented by the surrounding code.
- Do not add global mutable state. Put long-lived state in app models,
  controllers, services, or actors with explicit ownership.

## Development Check Loop

1. Fast build after non-trivial Swift edits:

   ```sh
   xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
   ```

2. Test gate when tests or testable behavior changed:

   ```sh
   xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
   ```

3. Swift Package Manager gate, only if a `Package.swift` target is introduced:

   ```sh
   swift test
   ```

4. Diff hygiene gate:

   ```sh
   git diff --check
   ```

Use `swift-format` or SwiftLint only after they are intentionally configured in
the repository. Do not add formatter or lint churn as part of unrelated feature
work.

## Architecture Shape

Prefer a native macOS functional-core / imperative-shell shape:

- SwiftUI views describe UI state and user actions.
- AppKit, Accessibility, CoreGraphics, Keychain, AVFoundation, and URLSession
  effects live behind focused services.
- Pure state transitions, settings models, transcription settings, transcript
  records, and error mapping live in models or small helper types.
- A central `AppState` or `DictationController` coordinates recording,
  transcription, and text insertion.
- Do not put microphone, networking, Keychain, paste, hotkey, or file-system
  logic directly in SwiftUI view bodies.

Target source layout:

```text
vibetype/vibetype/
  vibetypeApp.swift
  AppState.swift
  Services/
    AudioRecorderService.swift
    OpenAITranscriptionService.swift
    TextInsertionService.swift
    GlobalHotkeyService.swift
    KeychainService.swift
    PermissionsService.swift
    TranscriptHistoryService.swift
  Models/
    AppSettings.swift
    TranscriptionSettings.swift
    TranscriptItem.swift
    AppError.swift
    RecordingState.swift
  Views/
    MenuBarView.swift
    SettingsView.swift
    FloatingIndicatorView.swift
    TranscriptHistoryView.swift
  Utilities/
    ClipboardSnapshot.swift
    Logger.swift
```

Add subfolders only when they represent real ownership boundaries. Do not add a
new top-level runtime directory unless it has a clear product or platform
boundary.

## SwiftUI Rules

- Keep views declarative and small.
- Keep `body` free of hidden side effects.
- Use a single source of truth for app state.
- Use local view state only for local visual state.
- Use observable app state for shared recording, transcription, settings, and
  error state.
- Keep view identity stable; avoid changing `.id(...)` to force refreshes
  unless a spec or bug analysis justifies it.
- Do not start long-running work in initializers or computed properties.
- Start async UI work from explicit user actions, `.task`, or lifecycle hooks
  with clear cancellation behavior.
- Prefer product-language UI states over raw technical flags.
- Keep Settings views connected to explicit settings models, not scattered
  `UserDefaults` calls.

## AppKit And System Interop

Use SwiftUI first for normal UI, but isolate AppKit interop where SwiftUI is not
enough:

- menu bar behavior may use `MenuBarExtra` or `NSStatusItem`;
- floating recording indicators may use `NSPanel` with SwiftUI content;
- auto-paste may use pasteboard plus `CGEvent`;
- permission checks may use AVFoundation, Accessibility APIs, and system
  settings deep links;
- Keychain access should stay in `KeychainService`;
- global hotkeys should stay in `GlobalHotkeyService`.

Interop code should be narrow, testable where practical, and documented when it
depends on platform quirks.

## Concurrency And Timeouts

- Prefer `async` / `await` over callback pyramids for new async code.
- Keep UI state mutation on the main actor.
- Make long-running service work cancellable where practical.
- Do not create unbounded detached tasks.
- Keep each external boundary behind an explicit timeout: OpenAI requests,
  media conversion, audio file writing, permission polling, and helper
  processes.
- If an external stage times out, fail the current attempt visibly and let a
  later retry resume from completed artifacts when possible.
- Do not block the main thread with recording, upload, file I/O, or sleeps.
- Bridge delegate/callback APIs with continuations carefully; resume exactly
  once and cancel/clean up on failure.

## Data Modeling

- Prefer structs for values and enums for closed states or modes.
- Use enums for `RecordingState`, language mode, paste mode, permission state,
  and app errors when the valid cases are known.
- Avoid stringly typed state when an enum can make invalid states
  unrepresentable.
- Use `Optional` for real absence and `throws` / `Result` for recoverable
  failures.
- Avoid Boolean parameter clusters when a small settings struct or enum makes
  the call site clearer.
- Keep DTOs for OpenAI requests/responses separate from internal app state once
  they become non-trivial.

## Error Handling

- Use typed errors for recoverable app failures where practical.
- Convert low-level platform errors into product-language `AppError` at service
  boundaries.
- Do not silently swallow microphone, permission, Keychain, transcription,
  clipboard, or paste failures.
- Do not overwrite a previous successful transcript after a failed session.
- Panic-like `fatalError` is acceptable only for programmer errors in tests or
  impossible startup invariants, not normal user failures.

## Privacy, Secrets, And Logging

- API keys must be stored in Keychain, not UserDefaults or plain text files.
- Never log API keys, authorization headers, raw audio, raw dictated text, or
  full provider responses in default logs.
- Default logs should be short, scannable, and outcome-oriented.
- Verbose payloads, timings, and platform traces belong behind opt-in debug
  logging.
- Delete temporary audio after successful transcription unless a spec-defined
  debug mode explicitly keeps it.
- No telemetry, analytics, accounts, subscriptions, cloud sync, or server-side
  app state belongs in the MVP.

## Dependencies

- Prefer Apple frameworks and standard library APIs for the MVP.
- Add a Swift Package Manager dependency only when it removes meaningful
  complexity or provides a platform capability that Apple frameworks do not
  cover well.
- Keep dependency additions scoped and documented in the task or final report.
- Commit `Package.resolved` for app targets when Xcode creates it for declared
  package dependencies.
- Do not introduce Electron, React, Node.js runtime, Tauri, Rust, local Whisper,
  sherpa-onnx, llama.cpp, qdrant, or local model downloaders for the first MVP.

## Testing

- Prefer fakes for microphone, transcription, Keychain, clipboard, and paste
  services in unit tests.
- Do not call the live OpenAI API from normal tests.
- Tests for timeouts must use bounded waits or injectable clocks/delays.
- UI tests should cover user-visible flows only when they are stable enough to
  maintain.
- Manual QA is acceptable for platform permission and active-app paste behavior
  when automated tests would be fragile; record the exact scenario and outcome.

## Comments And Documentation

- Public or cross-boundary types should have short useful documentation once
  their API stabilizes.
- Comments should explain why, invariants, platform quirks, or security
  boundaries.
- Do not add comments that merely restate the code.
- Keep product behavior in `docs/specs/`, agent workflow in `AGENTS.md` and
  `BACKLOG_DEVELOPMENT.md`, and Swift engineering rules in this file.

## Reference Implementation Use

Use `references/openwhispr-main/` only as behavior evidence. It is an
Electron/React/Node app with many non-MVP features, so its architecture is not
the target architecture for this project.

Useful concepts to inspect:

- global hotkey behavior;
- recording lifecycle;
- paste into the active app;
- settings names and defaults;
- permission checks and error states;
- recording/transcribing UI states.

Ignore or explicitly reject:

- Electron IPC and preload architecture;
- React component structure;
- local model downloaders and inference services;
- notes, semantic search, meeting transcription, diarization, AI agents;
- accounts, billing, cloud sync, telemetry, and updater behavior.
