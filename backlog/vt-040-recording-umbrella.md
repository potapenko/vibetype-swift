---
id: VT-040
title: Recording Umbrella
status: blocked
priority: P1
lane: recording
dependencies:
  - VT-041
  - VT-042
  - VT-043
  - VT-044
  - VT-045
  - VT-122
allowed_paths:
  - backlog/**
  - docs/specs/features/microphone-text-input.md
---

# VT-040 - Recording Umbrella

Status: blocked

## Goal

Close out MVP microphone recording once the small service slices are complete.

## Child Tasks

- VT-041 recorder protocol and fake
- VT-042 start recording to a temporary file
- VT-043 stop recording and return an audio artifact
- VT-044 cancel and cleanup current recording
- VT-045 recording timeout guard

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Blocker

This umbrella cannot be completed by the implementer automation as selected
because its allowed paths only permit backlog and microphone spec edits. The
current runbook requires a concrete product delta for a `done` implementer
result, not a Markdown-only closure of already-completed recording service
slices.

## Resolution Path

- Blocker category: no product delta possible from selected scope.
- Follow-up: VT-122 at `backlog/vt-122-controller-start-stop-recording-flow.md`.
- Unblock condition: VT-122 wires the controller start/stop path through the
  recording boundary with fake-backed tests, giving the recording umbrella an
  actual app behavior delta to close against.
- Current-run limit: this task's selected `allowed_paths` do not include Swift
  source or tests, so the implementer cannot safely produce that delta while
  obeying the selected scope.
