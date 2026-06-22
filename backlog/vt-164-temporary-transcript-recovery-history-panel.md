---
id: VT-164
title: Temporary Transcript Recovery History Panel
status: blocked
priority: P1
lane: history
parent: VT-130
dependencies:
  - VT-123
  - VT-131
  - VT-133
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/transcript-history.md
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/text-output-workflow.md
  - docs/specs/features/menu-bar-app-shell.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-130-transcript-history-umbrella.md
  - backlog/vt-164-temporary-transcript-recovery-history-panel.md
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# VT-164 - Temporary Transcript Recovery History Panel

Status: blocked
Priority: P1
Lane: history
Dependencies: VT-123, VT-131, VT-133
Expected outputs: updated specs, session recovery history state, native history panel, menu/settings entry points, focused tests
Verification: `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`; `git diff --check`

## Goal

Add a privacy-first transcript recovery history surface so users can recover a
recent successful dictation when automatic insertion into the active app fails
or the target input changes.

## Scope

- Update transcript history specs from persistent-first history to
  session-only recovery history for this MVP slice.
- Keep at most the 20 most recent accepted, non-empty transcripts.
- Add accepted transcripts after transcription succeeds and before output
  handoff can discard recoverability.
- Add a native Transcript History window opened from the menu bar.
- Add row actions to save a history row into the VibeType Clipboard and insert
  a history row through the existing active-app insertion boundary.
- Add a Clear History action and clear recovery history on app termination.
- Add Settings copy/control that makes the privacy behavior clear.
- Add focused tests for disabled history, append, retention, clear, and output
  failure recovery.

## Non-goals

- Do not add raw audio retention, retry-from-audio, failed-session history, or
  discarded recording recovery.
- Do not add cloud sync, accounts, semantic notes, search, tags, folders, or
  OpenWhispr Electron/React architecture.
- Do not use the macOS system clipboard as history storage.
- Do not make durable disk-backed transcript persistence part of this slice.

## Acceptance

- History is off by default unless the updated spec explicitly keeps it as
  session-only and privacy-safe.
- When enabled, accepted non-empty transcripts appear newest-first in the
  history panel.
- History keeps no more than 20 entries.
- Failed active-app insertion does not remove the accepted transcript from
  recovery history.
- Clear History removes current recovery entries without deleting settings,
  Keychain secrets, audio cleanup state, or Last Transcript.
- Quitting the app clears current recovery entries.
- Default logs do not include transcript text.

## Implementation Notes

- Updated transcript history specs to define session-only recovery history,
  enabled by default because transcript text is kept in memory only.
- Added `TranscriptRecoveryHistoryStore` as the app-owned in-memory recovery
  history surface with max-20 retention and clear support.
- Connected accepted dictation controller output to recovery history before
  active-app output handoff.
- Added a native Transcript History window, menu item, clear action, row save
  action, and row insert action through the existing active-app insertion
  boundary.
- Added Settings copy/control for keeping recovery history and clearing current
  entries.
- Added focused tests for settings defaults, recovery store behavior,
  controller output-failure recovery, menu title, and recovered insertion.

## Verification Notes

- Passed: `git diff --check`.
- Passed: `xcrun swiftc -typecheck -parse-as-library $(find vibetype Shared -name '*.swift' -print | sort)`.
  It emitted only pre-existing warnings for `MenuBarView` `onChange` and
  `SpecialClipboardHotkeyService` `hotKeyID`.
- Blocked: `timeout 600 xcodebuild -project vibetype.xcodeproj -scheme
  vibetype -destination 'platform=macOS' test` reached Xcode external-tool
  probing and ended with `** BUILD INTERRUPTED **` / exit 124.
- Recovery: `python3 scripts/local_tooling_recover.py --apply --json`
  terminated stale `SWBBuildService` pid 2043 and removed project DerivedData.
- Blocked after recovery: the same `timeout 600 xcodebuild ... test` retry
  again reached early external-tool probing and ended with
  `** BUILD INTERRUPTED **` / exit 143.
- Recovery retry: `python3 scripts/local_tooling_recover.py --apply --json`
  removed project DerivedData and found no stale Xcode processes.
- Blocked final narrowed attempt: `timeout 300 xcodebuild -project
  vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS,arch=arm64'
  -derivedDataPath tmp/vt164-deriveddata test` reached external-tool probing
  and ended with `** BUILD INTERRUPTED **` / exit 124.
- Tooling: XcodeBuildMCP checked, but the exposed tool surface only provided
  simulator-oriented build/test tools, not macOS build/test.

## Resolution Path

Blocker category: local Xcode build/test tooling timeout before Swift compiler
diagnostics, test discovery, or test execution.

Existing infrastructure evidence: `VT-148` and
`docs/qa/runs/xcode-build-service-health-2026-06-21.md` cover this
automation-recoverable Xcode build-service timeout class, so this task cites
that path instead of creating a duplicate tooling task.

Unblock condition: rerun local tooling recovery, then rerun
`xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination
'platform=macOS' test`. If it reaches compiler/test execution and passes, set
this task to `done` with the fresh verification evidence. If it times out again
before compiler diagnostics, continue automatic local Xcode tooling repair and
append the fresh bounded command result here.
