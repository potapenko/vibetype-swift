---
id: VT-091
title: Tray Menu Reference Audit
status: in-progress
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-091-tray-menu-reference-audit.md
  - backlog/**
---

# VT-091 - Tray Menu Reference Audit

Status: in-progress

## Goal

Audit OpenWhispr tray and app menu behavior and create any missing small
VibeType menu tasks.

## Scope

- Inspect `references/openwhispr-main/src/helpers/tray.js`.
- Inspect `references/openwhispr-main/src/helpers/menuManager.js`.
- Add or refine backlog tasks only.
- Do not implement Swift code.

## Acceptance

- Menu behavior gaps are either covered by existing tasks or new small tasks.
- Any new tasks reference Swift-native implementation boundaries.
- No Electron behavior is copied as a dependency.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
