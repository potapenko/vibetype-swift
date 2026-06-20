---
id: VT-062
title: Accessibility Gated Paste Event
status: backlog
priority: P1
lane: text-output
parent: VT-060
dependencies:
  - VT-032
  - VT-061
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-062-accessibility-gated-paste-event.md
---

# VT-062 - Accessibility Gated Paste Event

Status: backlog

## Goal

Add auto-paste behavior using a macOS Cmd+V event only when accessibility
permission allows it.

## Scope

- Send paste through a Swift-native event boundary.
- Block or fall back to copy-only when accessibility is missing.
- Do not implement clipboard restore in this task.

## Acceptance

- Paste attempts are permission-gated.
- Missing accessibility permission does not lose transcript text.
- Tests can verify the boundary without posting real key events.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
