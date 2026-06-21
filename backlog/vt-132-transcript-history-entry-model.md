---
id: VT-132
title: Transcript History Entry Model
status: blocked
priority: P2
lane: history
parent: VT-130
dependencies:
  - VT-003
allowed_paths:
  - vibetype/Models/**
  - vibetypeTests/**
  - docs/specs/features/transcript-history.md
  - backlog/vt-132-transcript-history-entry-model.md
---

# VT-132 - Transcript History Entry Model

Status: blocked

## Goal

Create the small local value model for accepted transcript history rows.

## Scope

- Add a codable/equatable history entry model with local id, creation date,
  transcript text, model, language, and optional audio duration.
- Keep prompt text, raw audio paths, API keys, provider payloads, and headers
  out of the model.
- Add unit coverage for creating an entry from accepted transcript metadata.

## Non-goals

- Do not persist entries yet.
- Do not add a settings UI or history list.
- Do not store failed, cancelled, empty, or partial transcription attempts.

## Acceptance

- The model contains only fields allowed by `transcript-history.md`.
- Whitespace-only transcript text is rejected or normalized before an entry can
  be created.
- The model can be encoded and decoded by tests without external services.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker evidence

- 2026-06-20 22:01 CEST: implementation and focused tests were added, but
  required Xcode verification could not complete in this automation pass.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  was interrupted after a bounded wait because Xcode blocked while waiting for
  test workers/materialization and test-log finalization.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  hit the same bounded-wait blocker.
- `xcodebuild -derivedDataPath /tmp/vibetype-vt132-deriveddata-1781985521 -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  also blocked in early build setup; process inspection showed the run-owned
  `xcodebuild` waiting on `clang -v -E -dM ... /dev/null` for over a minute.
- Narrow sanity evidence passed:
  `xcrun swiftc -typecheck -parse-as-library vibetype/Models/TranscriptHistoryEntry.swift`.
