---
id: VT-053
title: Transcription Error Mapping
status: blocked
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-052
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-053-transcription-error-mapping.md
---

# VT-053 - Transcription Error Mapping

Status: blocked

## Goal

Map common transcription failures to compact app states and operator-readable
messages.

## Scope

- Handle missing API key, invalid API key, rate limit, network timeout, empty
  audio, and server error.
- Keep logs short and avoid payload dumps.
- Do not add retry loops in this task.

## Acceptance

- Each common failure has a stable enum or error case.
- Menu/settings UI can display a compact message.
- Tests cover at least the error mapping table.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Result

- Added stable `OpenAITranscriptionServiceError` user-facing messages and
  operator log categories for transcription failure states.
- Mapped recording-preparation failures to specific messages, including a
  no-audio message for empty captured audio.
- Expanded fake-backed transcription service tests for URL loading failures,
  provider HTTP status codes, empty audio before upload, and stable
  message/category output.
- Updated the OpenAI transcription spec to preserve compact error messages and
  log categories without payload, prompt, audio, transcript, or secret logging.

## Blocker Evidence

- 2026-06-21 CEST: implementation and focused test coverage were added, but
  required Xcode verification could not complete in this automation pass.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' -derivedDataPath
  /tmp/vibetype-swift-vt053-deriveddata test
  -only-testing:vibetypeTests/OpenAITranscriptionServiceTests` timed out with
  `BUILD INTERRUPTED` before test execution.
- `/opt/homebrew/bin/timeout 180 xcodebuild -quiet -project
  vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS'
  -derivedDataPath /tmp/vibetype-swift-vt053-deriveddata build-for-testing
  -only-testing:vibetypeTests/OpenAITranscriptionServiceTests` timed out with
  `BUILD INTERRUPTED` before compiler diagnostics or test-bundle output.
- Direct Swift Testing file typecheck was not usable outside Xcode because the
  `TestingMacros` plugin was unavailable to plain `swiftc`.
- Narrow evidence passed:
  `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library
  $(rg --files vibetype Shared -g '*.swift' | sort)`.
- Narrow smoke evidence passed: a run-owned `/tmp` harness compiled the
  production transcription service files and exercised provider status mapping,
  URL error mapping, empty-audio rejection before upload, and stable compact
  messages/log categories without live OpenAI or real Keychain access.
- `git diff --check` passed.

## Resolution Path

- Blocker category: local Xcode build/test service hang.
- Follow-up task: `VT-148`
  (`backlog/vt-148-xcode-build-service-health.md`).
- Unblock condition: after the local Xcode build service reaches macOS test
  execution again, rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination
  'platform=macOS' test -only-testing:vibetypeTests/OpenAITranscriptionServiceTests`
  plus `git diff --check`.
- If focused tests pass, a blocker-resolution pass may mark this task done
  without additional source edits because the error presentation boundary,
  mapping tests, service behavior, and spec update are already present.
