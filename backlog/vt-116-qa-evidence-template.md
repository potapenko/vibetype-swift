---
id: VT-116
title: QA Evidence Template
status: done
priority: P3
lane: testing
parent: VT-110
dependencies:
allowed_paths:
  - docs/qa/**
  - backlog/vt-116-qa-evidence-template.md
---

# VT-116 - QA Evidence Template

Status: done

## Goal

Create a reusable QA evidence template for task-scoped runtime checks.

## Scope

- Add a concise Markdown template under `docs/qa/`.
- Include fields for task id, build/test command, tool, scenario, result,
  evidence path, and blocker.
- Do not add screenshots or run app checks in this task.

## Acceptance

- Future Computer Use and iOS simulator tasks have a consistent evidence file
  shape.
- The template warns against storing secrets, raw audio, raw dictated text, or
  provider payloads.

## Verification

- `git diff --check`

## Blocker Evidence

- This selected scope is template-only: it can add or edit Markdown under
  `docs/qa/`, but it cannot change app behavior, Swift source, executable
  tests, build/runtime configuration, or a product bug fix.
- The task explicitly says not to add screenshots or run app checks, so it
  cannot be converted into bounded runtime QA evidence inside this scope.
- The repository already has macOS QA templates under
  `docs/qa/macos/templates/`, so completing this task as another Markdown
  template would not satisfy the implementer runbook's product-first contract.

## Resolution Path

- Blocker category: `no product delta possible from selected scope`.
- Follow-up: `VT-112` in `backlog/vt-112-macos-menu-bar-computer-use-smoke.md`
  is the concrete product/runtime follow-up for this QA lane.
- Current follow-up state: VT-112 is now `done`; it saved task-scoped menu-bar
  smoke evidence under `docs/qa/macos/`.
- Unblock condition: future runtime QA tasks should use the existing
  task-scoped QA evidence shape. Do not requeue VT-116 for implementer product
  work unless a later task explicitly needs a new reusable template.
- Current-run limit: VT-116 only permits template/docs work and forbids the app
  check needed to produce runtime product evidence.

## Completion Evidence

- 2026-06-22 11:37 CEST: blocker-resolution sweep confirmed follow-up
  `VT-112` remains archived `done`; it saved task-scoped menu-bar smoke
  evidence under `docs/qa/macos/`.
- The repository already has the task-scoped QA evidence shape this task asked
  for, and future runtime QA tasks can reuse it.
- No new QA template or app run was needed in this closeout.
- `git diff --check` is the closeout verification for this docs-only task.
