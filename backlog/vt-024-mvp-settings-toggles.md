---
id: VT-024
title: MVP Settings Toggles
status: blocked
priority: P2
lane: settings
parent: VT-020
dependencies:
  - VT-013
  - VT-021
allowed_paths:
  - vibetype/**
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-024-mvp-settings-toggles.md
---

# VT-024 - MVP Settings Toggles

Status: blocked

## Goal

Expose the core MVP settings toggles in the native settings UI.

## Scope

- Add controls for auto-paste, copy to clipboard, restore clipboard, sound, and
  floating indicator.
- Bind controls to the settings model.
- Keep advanced OpenWhispr settings out of this task.

## Acceptance

- Each MVP toggle has a native control.
- Values survive app relaunch if persistence exists.
- UI does not include unsupported advanced settings.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`

## Implementation Notes

- Added native Settings toggles for auto-paste, copy to clipboard, restore
  clipboard, start/stop sound, and the floating recording indicator.
- The controls load from and save to `AppSettingsStore`, so changes use the
  existing UserDefaults-backed non-secret settings model.
- No unsupported advanced OpenWhispr settings were added.

## Verification Notes

- Blocked: `xcodebuild -project vibetype.xcodeproj -scheme vibetype
  -destination 'platform=macOS' -derivedDataPath
  /tmp/vibetype-swift-vt024-deriveddata build` timed out after 300 seconds and
  ended with `** BUILD INTERRUPTED **` while Xcode was still in early build
  service / external-tool work.
- Passed: `xcrun swiftc -typecheck -parse-as-library` over app and shared Swift
  sources completed with only the pre-existing `MenuBarView` `onChange`
  deprecation warning.
- Passed: `git diff --check`.
- Runtime QA: blocked because the changed Settings surface requires a freshly
  built app, but the macOS build product was not produced within the bounded
  run. Active Computer Use also exposed only a click primitive, with no
  screenshot or semantic inspection surface.

## Resolution Path

- Blocker category: local Xcode build-service timeout before a macOS app
  product could be produced.
- Follow-up: VT-148 (`backlog/vt-148-xcode-build-service-health.md`).
- Unblock condition: the macOS `vibetype` scheme can complete a bounded build
  again, after which this task can be rerun to confirm the Settings toggles in
  the built app and move the task from blocked to done.
- This run could not finish the task directly because the selected verification
  command timed out before compiler diagnostics or a launchable app product.
