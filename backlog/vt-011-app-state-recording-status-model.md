---
id: VT-011
title: App State Recording Status Model
status: backlog
priority: P0
lane: swift-app-shell
parent: VT-010
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-011-app-state-recording-status-model.md
---

# VT-011 - App State Recording Status Model

Status: backlog

## Goal

Create the small state model the menu bar UI will use for idle, recording,
transcribing, completed, and error states.

## Scope

- Add a Swift type for app or dictation status.
- Keep it independent from real microphone and network services.
- Add a tiny test or preview-safe usage if the project test shape supports it.

## Acceptance

- Menu code can read the current state without hard-coded string branches.
- The state model has explicit cases for idle, recording, transcribing, success,
  and failure.
- No real recording or network code is added.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
