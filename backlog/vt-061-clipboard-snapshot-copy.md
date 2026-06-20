---
id: VT-061
title: Clipboard Snapshot And Copy
status: in-progress
priority: P1
lane: text-output
parent: VT-060
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-061-clipboard-snapshot-copy.md
---

# VT-061 - Clipboard Snapshot And Copy

Status: in-progress

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

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
