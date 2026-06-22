---
id: VT-163
status: done
priority: P1
lane: testing
dependencies:
allowed_paths:
  - backlog/vt-163-xcode-ui-automation-default-test-route.md
  - vibetype.xcodeproj/xcshareddata/xcschemes/vibetype.xcscheme
  - vibetypeUITests/**
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# VT-163 - Xcode UI Automation Default Test Route

Status: done
Priority: P1
Lane: testing
Dependencies: none
Expected outputs: shared macOS scheme that keeps default tests unit-only, UI test configuration cleanup
Verification: `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`, `git diff --check`

## Goal

Stop the normal macOS `vibetype` test route from launching placeholder UI
automation tests and triggering macOS Automation Mode banners during ordinary
unit-test verification.

## Scope

- Add or update the shared macOS `vibetype` scheme so its default Test action
  runs `vibetypeTests` only.
- Keep `vibetypeUITests` available for explicit UI-test runs.
- Remove unnecessary UI-configuration fanout from placeholder launch UI tests
  so explicit UI test runs do not cycle system appearance variants by default.

## Non-Goals

- Do not remove the UI test target.
- Do not change product behavior.
- Do not alter Codex automation schedules.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test` passed after local Xcode tooling recovery removed stale project-scoped DerivedData and one stale `SWBBuildService`.
- Fresh result bundle: `Test-vibetype-2026.06.22_18-24-26-+0200.xcresult`.
- Fresh result bundle contained `Unit test bundle: vibetypeTests` only, with no `vibetypeUITests` bundle.
- `log show` for `com.apple.dt.automationmode` after the successful run showed no Automation Mode state changes.
