---
id: VT-025
title: Transcription Settings Fields UI
status: blocked
priority: P2
lane: settings
parent: VT-020
dependencies:
  - VT-013
  - VT-021
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/openai-transcription.md
  - backlog/vt-025-transcription-settings-fields-ui.md
---

# VT-025 - Transcription Settings Fields UI

Status: blocked

## Goal

Expose the MVP transcription settings in the native Settings window.

## Scope

- Add Settings controls for transcription model, language mode, custom language
  code, and prompt or vocabulary hint.
- Bind controls to the existing non-secret settings model and store.
- Keep the UI OpenAI-file-transcription focused.
- Show validation or fallback behavior for empty model and invalid custom
  language values according to the specs.

## Non-goals

- Do not add live OpenAI calls, remote model-list loading, or provider tests.
- Do not add local model downloads, self-hosted endpoint configuration, or
  multi-provider settings.
- Do not add API key storage or API key UI; those stay in VT-022 and VT-023.
- Do not add recording, transcription upload, or paste behavior.

## Acceptance

- Settings lets the user edit model, language, custom language, and prompt
  values.
- Values persist through the existing settings store.
- OpenAI-only MVP scope is clear; unsupported OpenWhispr provider/local-model
  controls are absent.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`

## Blocker

The product code and focused validation smoke were implemented, but the
required macOS Xcode build could not complete in this environment.

Evidence from 2026-06-21:

- Passed: `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library $(rg --files vibetype Shared -g '*.swift' | sort)`
- Passed: direct app-module emit with `xcrun swiftc -emit-module -enable-testing`
- Passed: run-owned smoke harness for custom language validation and request
  builder behavior printed `vt025 smoke passed`
- Passed: `git diff --check`
- Blocked: `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build` timed out during early Xcode build-service/external-tool probing and ended with `** BUILD INTERRUPTED **`
- Blocked: direct focused test-source typecheck could not load Swift Testing
  outside Xcode: `no such module 'Testing'`

## Resolution Path

Blocker category: local Xcode build-service health.

Follow-up: `VT-148` at `backlog/vt-148-xcode-build-service-health.md`.

Unblock condition: a bounded macOS `xcodebuild` build or unit-test command
reaches compiler diagnostics or test execution again. After that, rerun this
task's required build verification and, because Settings UI changed, perform
bounded macOS runtime QA through Computer Use if an inspection surface is
available.

This run could not finish the task directly because the required Xcode command
timed out before compiler diagnostics despite direct Swift compiler evidence
passing.
