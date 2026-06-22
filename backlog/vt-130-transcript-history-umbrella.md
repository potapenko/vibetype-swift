---
id: VT-130
title: Transcript History Umbrella
status: backlog
priority: P2
lane: history
dependencies:
  - VT-131
  - VT-132
  - VT-133
  - VT-134
  - VT-135
  - VT-164
allowed_paths:
  - backlog/**
  - docs/specs/features/transcript-history.md
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/text-output-workflow.md
---

# VT-130 - Transcript History Umbrella

Status: backlog

## Goal

Close out opt-in, local-only transcript history once the settings, store,
controller append, and clear-history slices are complete.

## Child Tasks

- VT-131 history settings flag
- VT-132 transcript history entry model
- VT-133 transcript history store
- VT-134 append accepted transcript to history
- VT-135 clear transcript history settings action
- VT-164 temporary transcript recovery history panel

## Source Evidence

- `docs/specs/features/transcript-history.md`
- `docs/specs/features/settings-and-secret-storage.md`
- `docs/specs/features/text-output-workflow.md`
- `references/openwhispr-main/src/stores/transcriptionStore.ts`
- `references/openwhispr-main/src/components/HistoryView.tsx`
- `references/openwhispr-main/src/components/ui/TranscriptionItem.tsx`

## Non-goals

- Do not add OpenWhispr cloud transcription APIs.
- Do not add accounts, sync, notes, semantic search, or raw audio retention.
- Do not make transcript history enabled by default.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
