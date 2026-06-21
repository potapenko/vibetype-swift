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

The product code and focused validation smoke were implemented, and the
required macOS Xcode build now succeeds. The task remains blocked only because
the required visible Settings runtime QA cannot be inspected from the current
automation tool surface.

Evidence from 2026-06-21:

- Passed: `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library $(rg --files vibetype Shared -g '*.swift' | sort)`
- Passed: direct app-module emit with `xcrun swiftc -emit-module -enable-testing`
- Passed: run-owned smoke harness for custom language validation and request
  builder behavior printed `vt025 smoke passed`
- Passed: `git diff --check`
- Blocked: `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build` timed out during early Xcode build-service/external-tool probing and ended with `** BUILD INTERRUPTED **`
- Blocked: direct focused test-source typecheck could not load Swift Testing
  outside Xcode: `no such module 'Testing'`

Fresh closeout evidence from 2026-06-22:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json` completed
  with no matched, terminated, remaining, or removed processes/artifacts.
- Passed: `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build` reached `** BUILD SUCCEEDED **`.
- Blocked: required Settings runtime QA could not inspect the model, language,
  custom language, and prompt fields because the exposed Computer Use surface
  for this thread provided only `click` and no screenshot, snapshot, or
  accessibility-tree reader.

## Resolution Path

Blocker category: macOS Settings runtime QA tooling.

Follow-up: operator/tooling surface, no repository task required yet.

Unblock condition: rerun this closeout in a thread where Computer Use or an
equivalent macOS UI inspection surface can capture Settings window state, then
open Settings and verify the transcription model, language picker, custom
language field, and prompt field.

This run could not finish the task directly because the build blocker was
cleared, but the available Computer Use tool could only click and could not
read or capture the visible Settings surface required by the QA contract.
