---
id: VT-133
title: Transcript History Store
status: backlog
priority: P2
lane: history
parent: VT-130
dependencies:
  - VT-132
allowed_paths:
  - vibetype/vibetype/Models/**
  - vibetype/vibetype/Services/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/transcript-history.md
  - backlog/vt-133-transcript-history-store.md
---

# VT-133 - Transcript History Store

Status: backlog

## Goal

Add a local transcript history store that appends accepted entries, keeps the
newest 20, and can clear persistent history.

## Scope

- Add a small store boundary with load, append, and clear operations.
- Use UserDefaults or a small local JSON file; keep the choice simple and
  native.
- Keep at most the 20 newest accepted entries.
- Add fake-backed tests for append, retention, load, clear, and empty
  transcript rejection.

## Non-goals

- Do not add cloud sync, accounts, deletion APIs, or OpenWhispr service calls.
- Do not add search, folders, notes, semantic indexing, or raw audio retention.
- Do not connect the store to the dictation controller yet.

## Acceptance

- Appending a 21st entry drops the oldest entry.
- Clearing removes only transcript history entries.
- Store failures are surfaced as recoverable errors instead of being silently
  ignored.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
