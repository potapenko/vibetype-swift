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

### 2026-06-21 VT-152 Closeout Retry

- Passed: `python3 scripts/local_tooling_recover.py --apply --json` completed
  successfully, matched no stale processes, and removed no artifacts.
- Passed: `/opt/homebrew/bin/timeout 300 xcodebuild -project
  vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  completed with `** BUILD SUCCEEDED **`.
- Build product:
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-cgljxvuvdfxmqbeiqfwkdshvjovc/Build/Products/Debug/vibetype.app`.
- Runtime QA: blocked. The active Computer Use surface exposed only
  `mcp__computer_use.click`, with no screenshot, semantic snapshot,
  accessibility tree, or element discovery tool. The Settings toggles could
  not be inspected safely, and no coordinate click was attempted because it
  would not produce reliable Settings evidence.
- Durable QA note:
  `docs/qa/runs/settings-toggles-closeout-2026-06-21.md`.

## Resolution Path

- Blocker category: macOS Settings runtime inspection unavailable. The prior
  local Xcode build-service blocker was cleared by the 2026-06-21 VT-152 retry.
- Existing evidence to reuse: VT-112
  (`backlog/done/vt-112-macos-menu-bar-computer-use-smoke.md`) and
  `docs/qa/macos/vt-112-2026-06-21-menu-bar-smoke.md` record the same missing
  Computer Use screenshot/snapshot/accessibility-tree capability.
- Unblock condition: run a bounded Settings smoke when Computer Use, or an
  equivalent macOS UI-reading tool, exposes screenshot, semantic snapshot,
  accessibility tree, or element discovery. Verify the five MVP Behavior
  toggles in the built Settings window, then move this task to done.
- This run could not finish the task directly because the current tool surface
  could not read or verify the Settings window after the build succeeded.
