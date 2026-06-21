---
id: VT-061
title: Clipboard Snapshot And Copy
status: done
priority: P1
lane: text-output
parent: VT-060
dependencies:
  - VT-000
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-061-clipboard-snapshot-copy.md
---

# VT-061 - Clipboard Snapshot And Copy

Status: done

## Goal

Add a Swift-native clipboard boundary for saving the current clipboard and
copying transcript text.

## Scope

- Use `NSPasteboard`.
- Snapshot enough state to restore plain text when possible.
- Do not send paste key events in this task.

## Acceptance

- Copy Last Transcript can place text on the clipboard.
- Existing clipboard text can be captured before replacement.
- Tests use a fake boundary where practical.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker Evidence

- 2026-06-20: Clipboard implementation and unit-level verification are present.
- Required full scheme verification failed after the unit tests passed because
  `vibetypeUITests-Runner` could not initialize off-console:
  `User interaction required. Can't authenticate off console`.
- Narrow verification passed:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
- `git diff --check` passed.

## Resolution Path

- Blocker category: full scheme UI-test runner cannot authenticate
  off-console.
- Unblock condition: rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`; if they still pass, apply the
  `verification-strategy.md` policy that accepts narrow target evidence when
  only the UI-test runner needs off-console interaction.
- A blocker-resolution pass may then mark this task done without additional
  source edits because the clipboard boundary and unit-level verification are
  already present.

## Completion Evidence

- 2026-06-21 17:03 CEST: Blocker-resolution pass verified the existing
  clipboard boundary and fake-backed tests with
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
- `git diff --check` passed.
- Applied `verification-strategy.md` narrow-evidence policy because the only
  known full-scheme blocker was the off-console UI-test runner.
