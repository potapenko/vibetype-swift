---
id: VT-060
title: Text Output Umbrella
status: blocked
priority: P1
lane: text-output
dependencies:
  - VT-061
  - VT-062
  - VT-063
  - VT-064
allowed_paths:
  - backlog/**
  - docs/specs/features/text-output-workflow.md
---

# VT-060 - Text Output Umbrella

Status: blocked

## Goal

Close out copy and auto-paste behavior after child tasks land.

## Child Tasks

- VT-061 clipboard snapshot and copy
- VT-062 accessibility-gated paste event
- VT-063 clipboard restore after paste
- VT-064 last transcript menu integration

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Resolution Path

Blocker category: no product delta possible from selected scope.

This umbrella closeout is ready because VT-061, VT-062, VT-063, and VT-064 are
done, but its selected scope only allows backlog and text-output spec edits.
The implementer automation cannot mark it done with a Markdown-only closeout.

The smallest remaining product change is already represented by VT-123
(`backlog/vt-123-controller-success-output-flow.md`): wire a successful
controller transcript through the existing text output handoff so accepted text
can be copied or pasted through the native service boundary. VT-060 can be
revisited after that implementation task lands, or a blocker resolver can close
this umbrella if no additional text-output code slice is needed.
