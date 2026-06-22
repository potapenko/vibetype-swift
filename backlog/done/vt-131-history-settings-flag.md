---
id: VT-131
title: History Settings Flag
status: done
priority: P2
lane: history
parent: VT-130
dependencies:
  - VT-021
allowed_paths:
  - vibetype/Models/AppSettings.swift
  - vibetypeTests/AppSettingsTests.swift
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-131-history-settings-flag.md
---

# VT-131 - History Settings Flag

Status: done

## Goal

Add the persisted `saveTranscriptHistory` setting that gates all future
history writes.

## Scope

- Add `saveTranscriptHistory` to `AppSettings` and `AppSettingsStore`.
- Default it to `false`.
- Persist it through the same non-secret settings path as other toggles.
- Add or update fake `UserDefaults` tests for default-off and save/load.

## Non-goals

- Do not add transcript history storage.
- Do not add a settings UI control.
- Do not write or clear history entries.

## Acceptance

- New installs load transcript history as disabled.
- Saving and loading settings preserves the flag.
- No API key, prompt text, transcript text, or history entry is stored by this
  setting task.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker Evidence

- Product delta implemented: `AppSettings` now has `saveTranscriptHistory`,
  defaults it to `false`, and persists it through `AppSettingsStore`.
- Test coverage updated in `AppSettingsTests` for default-off and save/load
  persistence.
- Required verification
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  timed out with `** BUILD INTERRUPTED **` during early Xcode build-service
  setup before test execution.
- Focused verification
  `/opt/homebrew/bin/timeout 240 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests/AppSettingsTests`
  hit the same early Xcode setup timeout before test execution.
- Narrow compiler evidence passed:
  `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library $(rg --files vibetype Shared -g '*.swift' | sort)`
  with only the pre-existing `MenuBarView.onChange` deprecation warning.
- `git diff --check` passed.

## Resolution Path

Blocker category: Xcode build/test service timeout before test execution.

Follow-up: `VT-148` (`backlog/vt-148-xcode-build-service-health.md`).

Unblock condition: `VT-148` confirms the local macOS Xcode build/test service
can reach test execution again, then rerun VT-131's required
`xcodebuild ... test` verification or focused `AppSettingsTests` verification
and move this task to `done` if it passes.

The current run could not finish directly because both full and focused Xcode
test commands were interrupted by bounded timeouts before any test diagnostics
or failures were produced.

## Completion Evidence

- 2026-06-22 11:23 CEST: local tooling recovery succeeded, terminated stale
  `SWBBuildService` pid 3403, and removed run-generated `scripts/__pycache__`
  plus project-scoped DerivedData.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' test
  -only-testing:vibetypeTests` reached and passed the focused macOS unit-test
  target, including `AppSettingsTests`.
- `git diff --check` passed.
- No source edits were needed; the previously implemented
  `saveTranscriptHistory` flag, persistence behavior, and default-off tests now
  have current verification evidence.
