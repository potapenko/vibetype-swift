---
id: VT-134
title: Append Accepted Transcript History
status: backlog
priority: P2
lane: history
parent: VT-130
dependencies:
  - VT-123
  - VT-131
  - VT-133
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/transcript-history.md
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-134-append-accepted-transcript-history.md
---

# VT-134 - Append Accepted Transcript History

Status: backlog

## Goal

Connect successful dictation sessions to local history writes when
`saveTranscriptHistory` is enabled.

## Scope

- Append only accepted, non-empty transcripts after transcription succeeds.
- Skip history writes when the setting is disabled.
- Preserve Last Transcript even if output handoff later fails.
- Surface history storage failure as a recoverable local-storage error without
  discarding the accepted transcript.
- Use fakes for controller, history store, transcription, and output tests.

## Non-goals

- Do not add live microphone, OpenAI, Keychain, or paste side effects to tests.
- Do not add a history list UI.
- Do not save failed, cancelled, empty, or partial sessions.

## Acceptance

- A successful session with history enabled writes one history entry.
- A successful session with history disabled writes none.
- Failed, cancelled, or empty sessions do not write history.
- Output failure does not erase the accepted transcript or the history decision.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
