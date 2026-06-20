---
id: VT-101
title: Backlog Groomer Prompt Dry Run Check
status: in-progress
priority: P2
lane: workflow
parent: VT-100
dependencies:
allowed_paths:
  - docs/specs/features/backlog-grooming-automation.md
  - backlog/vt-101-backlog-groomer-prompt-dry-run-check.md
---

# VT-101 - Backlog Groomer Prompt Dry Run Check

Status: in-progress

## Goal

Review the backlog groomer automation contract after the first scheduled run
and patch the prompt/spec if it creates tasks that are too large or too vague.

## Scope

- Inspect the first groomer-created diff or commit.
- Tighten the groomer spec if needed.
- Do not implement product code.

## Acceptance

- Groomer output remains small-task oriented.
- Parent and child task grouping is preserved.
- The implementer selector still returns a ready task.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
