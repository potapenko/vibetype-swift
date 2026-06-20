---
id: VT-073
title: Hold To Record Decision Slice
status: backlog
priority: P3
lane: hotkey
parent: VT-070
dependencies:
  - VT-002
allowed_paths:
  - docs/specs/features/**
  - backlog/vt-073-hold-to-record-decision-slice.md
---

# VT-073 - Hold To Record Decision Slice

Status: backlog

## Goal

Decide whether the MVP supports hold-to-record or only tap-to-toggle.

## Scope

- Update the hotkey spec with the MVP decision.
- Compare against OpenWhispr activation modes only as reference behavior.
- Do not implement hotkey code.

## Acceptance

- Spec states the activation mode for MVP.
- Deferred behavior is explicitly listed if hold-to-record is postponed.
- Implementation tasks can depend on the decision.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
