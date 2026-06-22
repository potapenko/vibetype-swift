---
id: VT-064
title: Last Transcript Menu Integration
status: in-progress
priority: P2
lane: text-output
parent: VT-060
dependencies:
  - VT-014
  - VT-054
  - VT-061
allowed_paths:
  - vibetype/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-064-last-transcript-menu-integration.md
---

# VT-064 - Last Transcript Menu Integration

Status: in-progress

## Goal

Connect normalized transcript state to the menu's Last Transcript and Copy Last
Transcript entries.

## Scope

- Show a compact last transcript preview or state.
- Enable Copy Last Transcript only when text exists.
- Do not add transcript history in this task.

## Acceptance

- Empty state is clear.
- Copy action uses the clipboard boundary.
- Long transcript text does not make the menu unusable.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
