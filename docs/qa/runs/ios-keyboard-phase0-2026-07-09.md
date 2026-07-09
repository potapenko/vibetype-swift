# iOS Keyboard Phase 0 QA

Date: 2026-07-09
Task: direct user-approved iOS keyboard feasibility implementation

## Scope

- Add a buildable custom keyboard extension embedded in `HoldType-iOS`.
- Add an App Group snapshot written by the containing app and read by the
  extension.
- Keep microphone, background audio, provider networking, Keychain sharing,
  Full Access, and containing-app launch outside this slice.
- Add a visible containing-app probe and pure bridge tests.

## Automated Evidence

- `plutil -lint HoldType.xcodeproj/project.pbxproj`
  - Result: passed.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO`
  - Result: passed.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,id=2388F192-115A-45FF-B5C3-2B666B4E42F7' test
  CODE_SIGNING_ALLOWED=NO`
  - Result: passed on iPhone 17 Pro, iOS 26.5.
  - Nine tests passed: three keyboard-session reducer tests and six bridge
    normalization, decoded-input validation, monotonic-revision, round-trip,
    expiry/schema, and corrupt-data tests.
- Built bundle inspection:
  - `HoldType-iOS.app/PlugIns/HoldTypeKeyboard.appex` exists.
  - Processed extension plist reports `com.apple.keyboard-service`.
  - Processed `RequestsOpenAccess` is `false`.
- Simulator App Group inspection:
  - Installed app reports `group.app.holdtype.HoldType.shared` in its registered
    group containers.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'generic/platform=iOS' build`
  - Result: expected signing gate. Both `HoldType-iOS` and `HoldTypeKeyboard`
    require an operator-local development team before a physical-device build.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' build`
  - Result: passed with pre-existing Swift actor-isolation warnings.
- `git diff --check`
  - Result: passed before final review.

## Runtime Evidence

The containing app launched successfully on an iPhone 17 Pro simulator running
iOS 26.5. Visual inspection confirmed:

- the Phase 0 status screen is readable without clipping at launch;
- the extension/bridge/voice-gate scope is stated honestly;
- the sample transcript action is visible and reachable in the scroll view;
- no microphone or provider permission was requested.

The extension was not enabled as a system keyboard in this automated pass, so
the real `UITextDocumentProxy` insertion and next-keyboard interaction remain
unproven runtime behavior.

## Runtime QA Decision

Containing-app runtime QA: passed.

Keyboard-extension runtime QA: pending physical-device/manual validation. A
simulator build and embedded `.appex` are not evidence for keyboard switching,
secure-field fallback, Full Access behavior, process eviction, or iPad floating
layout.

A generic physical-device build currently stops at signing because no
repository-wide `DEVELOPMENT_TEAM` is configured. This is intentional: the next
pass must select the same operator-local team for the containing app and
extension and provision the shared App Group rather than committing a personal
team identifier.

## Next Device Pass

On a configured development-team build, enable HoldType in Keyboard Settings,
publish the sample, then validate the `a`, Space, Delete, Insert latest, and
Globe controls in Notes before expanding to the M0B host-field matrix.
