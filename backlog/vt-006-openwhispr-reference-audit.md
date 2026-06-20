---
id: VT-006
status: in-progress
priority: P1
lane: reference
dependencies:
allowed_paths:
  - references/**
  - docs/**
  - backlog/**
verification:
  - git diff --check
---

# OpenWhispr Reference Behavior Audit

Status: in-progress
Priority: P1
Lane: reference
Dependencies: none
Expected outputs: reference behavior notes, follow-up tasks if needed, verification result
Verification: git diff --check

## Goal

Audit the copied OpenWhispr reference for behavior that should inform the
native Swift MVP without porting its Electron/React architecture.

## Scope

- Inspect hotkey activation, recording lifecycle, paste behavior, settings,
  permissions, and recording/transcribing UI states.
- Write concise notes under `references/` or `docs/`.
- Create small follow-up backlog tasks only for useful behavior gaps.

## Non-goals

- Do not copy Electron, React, Node.js, local model, meeting, notes, account,
  cloud sync, billing, telemetry, or updater code into the app.
- Do not implement Swift features in this audit task.

## Acceptance

- Reference notes identify useful MVP behavior and explicitly rejected scope.
- Notes cite concrete files in `references/openwhispr-main/`.
- Verification command passes.

## Notes

- Start with `references/openwhispr-main/CLAUDE.md`,
  `references/openwhispr-main/main.js`,
  `references/openwhispr-main/src/hooks/`, and
  `references/openwhispr-main/resources/macos-*.swift`.
