---
id: VT-116
title: QA Evidence Template
status: backlog
priority: P3
lane: testing
parent: VT-110
dependencies:
allowed_paths:
  - docs/qa/**
  - backlog/vt-116-qa-evidence-template.md
---

# VT-116 - QA Evidence Template

Status: backlog

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
