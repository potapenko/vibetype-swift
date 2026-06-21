---
id: VT-147
title: iOS Keyboard Inline Settings Panel
status: backlog
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-141
  - VT-144
  - VT-145
allowed_paths:
  - vibetype/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/settings-and-secret-storage.md
  - docs/qa/**
  - backlog/vt-147-ios-keyboard-inline-settings-panel.md
verification:
  - git diff --check
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype-iOS -destination 'platform=iOS Simulator' build
---

# VT-147 - iOS Keyboard Inline Settings Panel

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-141, VT-144, VT-145
Expected outputs: compact keyboard settings panel, simulator evidence or blocker
Verification: git diff --check; iOS simulator build/screenshot or documented blocker

## Goal

Add a compact settings panel inside the keyboard interface for settings that
make sense without leaving the host text context.

## Scope

- Implement a keyboard-height settings panel reachable from the keyboard chrome.
- Include only compact controls that are safe and useful inside the keyboard,
  such as language, dictation mode, punctuation style, and a shortcut to deep
  app settings.
- Keep credentials, microphone permission education, Open Access setup, model
  provider configuration, and destructive history actions in the containing app
  unless the product contract explicitly allows a compact read-only state.
- Provide clear actions for staying in the keyboard, opening containing app
  settings, and turning off an active session when applicable.

## Non-goals

- Do not save API keys from the keyboard.
- Do not expose full macOS Settings UI inside the keyboard extension.
- Do not add destructive transcript-history clearing from the keyboard.

## Acceptance

- Inline settings fit inside the keyboard surface without covering the
  next-keyboard control.
- Deep settings actions hand off to the containing app with clear copy.
- Simulator screenshot evidence or a bounded blocker note records the visual
  result.

## Notes

- This is the VibeType version of the reference settings handoff screen: compact
  local settings stay inline, complex setup opens the app.
