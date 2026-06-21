---
id: VT-054
title: Transcript Trim Empty Result
status: blocked
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-052
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-054-transcript-trim-empty-result.md
---

# VT-054 - Transcript Trim Empty Result

Status: blocked

## Goal

Normalize transcription output before it reaches clipboard or paste workflows.

## Scope

- Trim whitespace.
- Treat empty output as a controlled no-text result.
- Store only the normalized last transcript.

## Acceptance

- Empty transcript does not overwrite useful clipboard content.
- Last transcript stores normalized text.
- Tests cover whitespace-only output.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Result

- Added `AcceptedTranscript` normalization so accepted transcript text is
  trimmed once and whitespace-only output is rejected before text-output
  surfaces can copy it.
- `OpenAITranscriptionService` now parses provider `text` through the shared
  accepted-transcript boundary and still maps empty output to
  `emptyTranscript`.
- `DictationStatus` exposes only normalized non-empty last transcript text to
  menu/detail/copy surfaces, so whitespace-only success state cannot enable
  Copy Last Transcript or replace useful clipboard content with blank text.
- Updated the text-output spec to require trimmed Last Transcript / Copy Last
  Transcript behavior.
- Added focused `DictationStatusTests` coverage for trimmed success text and
  whitespace-only success text.

## Blocker Evidence

- 2026-06-21 CEST: implementation and focused tests were added, but required
  Xcode verification did not complete in this automation pass.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  timed out with `BUILD INTERRUPTED` after reaching early Xcode build-service
  setup / external-tool probing.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  hit the same bounded timeout before test execution.
- Narrow sanity evidence passed:
  `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library $(rg --files vibetype Shared -g '*.swift' | sort)`.
- `git diff --check` passed.

## Resolution Path

- Blocker category: local Xcode test/build service hang.
- Follow-up task: `VT-148` (`backlog/vt-148-xcode-build-service-health.md`).
- Unblock condition: after the local Xcode build service returns progress,
  rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`.
- If focused tests pass, a blocker-resolution pass may mark this task done
  without additional source edits because the normalization model, service
  wiring, menu/copy guard, spec update, and focused tests are already present.
- If Xcode still blocks before test execution, record the fresh bounded Xcode
  blocker and keep the `swiftc` check only as narrow sanity evidence.
