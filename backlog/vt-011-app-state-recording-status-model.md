---
id: VT-011
title: App State Recording Status Model
status: done
priority: P0
lane: swift-app-shell
parent: VT-010
dependencies:
  - VT-000
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-011-app-state-recording-status-model.md
---

# VT-011 - App State Recording Status Model

Status: done

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

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
- `git diff --check`

## Blocker Evidence

2026-06-20:

- The state model implementation is present and the unit-test target passes:
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`.
- The required full scheme test command fails before VT-011 assertions because
  `vibetypeUITests-Runner` cannot initialize for UI testing in this off-console
  automation environment: `User interaction required. Can't authenticate off console`.
- `git diff --check` passes.

## Completion Evidence

2026-06-21:

- Verified the existing `DictationStatus` model exposes idle, recording,
  transcribing, success, and failure states for menu code without real
  microphone or network services.
- Verified the menu reads `DictationStatus` for status text, recording action
  title, action enabled state, last transcript display, and copy eligibility.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests` passed.
- The focused unit target is the accepted evidence for this model-only task
  because `docs/specs/features/verification-strategy.md` allows narrow target
  evidence when the full scheme is blocked only by the macOS UI-test runner
  needing off-console authentication.
