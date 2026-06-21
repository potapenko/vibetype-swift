---
id: VT-034
title: Settings Permissions And Privacy Section
status: done
priority: P2
lane: permissions
parent: VT-030
dependencies:
  - VT-013
  - VT-031
  - VT-032
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/privacy-and-permissions.md
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-034-settings-permissions-privacy-section.md
---

# VT-034 - Settings Permissions And Privacy Section

Status: done

## Goal

Add the native Settings section that explains microphone, Accessibility, and
OpenAI transcription privacy state.

## Scope

- Show microphone permission status and the next action when recording is
  blocked.
- Show Accessibility trust status and the next action when auto-paste is
  blocked.
- Include concise disclosure that audio is sent to OpenAI for transcription.
- Use existing permission services or fakes; keep platform prompts bounded.

## Non-goals

- Do not add recording, paste, or transcription execution.
- Do not add microphone device selection, system-audio capture setup, or Linux
  paste-tool troubleshooting.
- Do not add accounts, analytics, cloud backup, persistent raw-audio retention,
  or destructive audio cleanup controls.

## Acceptance

- Settings shows microphone and Accessibility state without implying recording
  has started.
- Blocked states provide a clear next action.
- The OpenAI audio-processing disclosure is visible in Settings.
- Unsupported advanced OpenWhispr privacy/data controls are absent.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`

## Completion Notes

- Added a Settings privacy and permissions section with microphone status,
  Accessibility status, bounded next actions, and the OpenAI audio-processing
  disclosure.
- Added fake-backed permission-copy tests for the Settings status/action text.
- Verification:
  - `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
    passed.
  - `git diff --check` passed.
  - Full `xcodebuild ... test` compiled and ran `vibetypeTests`, including the
    new permission tests, but the `vibetypeUITests` runner failed to initialize
    automation mode with AppleEvent/UI automation timeout.
- Runtime QA: blocked. The freshly built app launched, but Computer Use
  `get_app_state` timed out with AppleEvent `-1712` before the Settings window
  could be inspected.
