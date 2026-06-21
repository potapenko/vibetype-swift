---
id: VT-012
title: Start Stop Menu Label Binding
status: done
priority: P0
lane: swift-app-shell
parent: VT-010
dependencies:
  - VT-011
allowed_paths:
  - vibetype/**
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-012-start-stop-menu-label-binding.md
---

# VT-012 - Start Stop Menu Label Binding

Status: done

## Goal

Bind the menu's primary dictation action label to app state so the menu can
show `Start Recording` or `Stop Recording` at the right time.

## Scope

- Update the menu item label from the state model.
- Add a placeholder state toggle only if needed for local verification.
- Keep service behavior out of scope.

## Acceptance

- Idle state shows a start action.
- Recording state shows a stop action.
- Transcribing or blocked states cannot start parallel work.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`

## Completion Evidence

2026-06-21:

- Bound the menu's primary recording action to `DictationStatus` placeholder
  transitions so idle shows `Start Recording`, placeholder recording shows
  `Stop Recording`, and transcribing remains a disabled/no-op state.
- Kept real recorder, microphone, and transcription behavior out of scope; the
  placeholder recording detail explicitly states that microphone input is not
  captured in this build.
- Updated the menu bar shell spec with the temporary non-capturing
  Start/Stop placeholder contract.
- Verification passed:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests/DictationStatusTests`;
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`;
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`;
  `git diff --check`.
- Runtime QA was required for the changed menu interaction, but blocked because
  the active Computer Use tool surface exposed only a click primitive and no
  screenshot or accessibility snapshot reader to inspect the macOS menu.
