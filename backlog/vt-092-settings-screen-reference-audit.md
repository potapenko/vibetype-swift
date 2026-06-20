---
id: VT-092
title: Settings Screen Reference Audit
status: backlog
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-092-settings-screen-reference-audit.md
  - backlog/**
---

# VT-092 - Settings Screen Reference Audit

Status: backlog

## Goal

Audit OpenWhispr settings screens and create missing small tasks for MVP
settings sections.

## Scope

- Inspect `references/openwhispr-main/src/components/SettingsPage.tsx`.
- Focus on API key, model, language, hotkey, microphone, and permissions.
- Treat advanced dictionary, snippets, and analytics behavior as out of scope
  unless the MVP spec already requires it.

## Acceptance

- Missing MVP settings work is represented as small child tasks.
- Unsupported advanced reference features are not added as implementation tasks.
- Docs remain product-level.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
