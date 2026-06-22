---
id: VT-163
status: in-progress
priority: P1
lane: testing
dependencies: []
allowed_paths:
  - backlog/vt-163-xcode-ui-automation-default-test-route.md
  - vibetype.xcodeproj/xcshareddata/xcschemes/vibetype.xcscheme
  - vibetypeUITests/**
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# VT-163 - Xcode UI Automation Default Test Route

Status: in-progress
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
