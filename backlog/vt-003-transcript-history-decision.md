---
id: VT-003
status: backlog
priority: P1
lane: specs
dependencies:
allowed_paths:
  - docs/specs/**
verification:
  - git diff --check
---

# Transcript History Decision Spec

Status: backlog
Priority: P1
Lane: specs
Dependencies: none
Expected outputs: feature spec or explicit non-goal update, verification result
Verification: git diff --check

## Goal

Decide whether the optional last-20 transcript history belongs in the MVP.

## Scope

- Define whether history is enabled by default.
- Define local-only storage, fields, retention, clearing, and privacy behavior.
- Define how history interacts with last transcript and copy actions.
- Update related specs if history is deferred.

## Non-goals

- Do not implement persistence.
- Do not introduce SQLite unless a future spec explicitly requires it.
- Do not add cloud sync or accounts.

## Acceptance

- The MVP history decision is explicit in specs.
- Privacy implications are clear.
- Verification command passes.

## Notes

- Read `docs/specs/features/privacy-and-permissions.md`.
- Read `docs/specs/features/text-output-workflow.md`.
