---
id: VT-101
title: Backlog Groomer Prompt Dry Run Check
status: done
priority: P2
lane: workflow
parent: VT-100
dependencies:
allowed_paths:
  - docs/specs/features/backlog-grooming-automation.md
  - backlog/vt-101-backlog-groomer-prompt-dry-run-check.md
---

# VT-101 - Backlog Groomer Prompt Dry Run Check

Status: done

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

## Review Notes

- Reviewed the first groomer-created commit, `258b360` (`backlog: groom
  dictation controller tasks`), which created a controller umbrella and focused
  children for service boundary, start/stop, success output, and failure/cancel
  flows.
- Checked the later history groomer commit, `3f5caf7`, as a second sample; it
  also preserved umbrella plus child grouping for settings, model, store,
  append, and clear slices.
- Tightened `docs/specs/features/backlog-grooming-automation.md` with an
  explicit generated-diff self-review gate so future groomer runs split tasks
  that combine too many implementation layers.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
