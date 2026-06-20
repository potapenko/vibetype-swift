---
id: VT-014
title: Last Transcript Menu Placeholders
status: done
priority: P1
lane: text-output
parent: VT-010
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-014-last-transcript-menu-placeholders.md
---

# VT-014 - Last Transcript Menu Placeholders

Status: done

## Goal

Add native menu placeholders for Last Transcript and Copy Last Transcript.

## Scope

- Add menu items for last transcript visibility and copying.
- Disable or clearly no-op these actions until transcript storage exists.
- Do not implement transcription, paste, or clipboard behavior in this task.

## Acceptance

- Menu contains a Last Transcript area or item.
- Copy Last Transcript is unavailable or safe when no transcript exists.
- The menu behavior matches the spec's empty-state expectations.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
