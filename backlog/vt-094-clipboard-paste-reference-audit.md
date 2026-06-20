---
id: VT-094
title: Clipboard Paste Reference Audit
status: in-progress
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/text-output-workflow.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-094-clipboard-paste-reference-audit.md
  - backlog/**
---

# VT-094 - Clipboard Paste Reference Audit

Status: in-progress

## Goal

Audit OpenWhispr clipboard and paste helpers and translate missing behavior into
small Swift-native tasks.

## Scope

- Inspect `references/openwhispr-main/src/helpers/clipboard.js`.
- Inspect `references/openwhispr-main/resources/macos-fast-paste.swift`.
- Focus on copy, auto-paste, accessibility gating, delays, and restore.
- Do not implement Swift code in this audit task.

## Acceptance

- Clipboard and paste MVP behavior is fully represented by tasks or specs.
- New tasks use `NSPasteboard`, accessibility trust checks, and native events.
- No Node/Electron clipboard dependency is introduced.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
