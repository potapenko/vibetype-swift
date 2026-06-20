---
id: VT-004
status: in-progress
priority: P1
lane: specs
dependencies:
allowed_paths:
  - docs/specs/**
verification:
  - git diff --check
---

# Floating Indicator Contract Spec

Status: in-progress
Priority: P1
Lane: specs
Dependencies: none
Expected outputs: feature spec update, verification result
Verification: git diff --check

## Goal

Define the floating recording/transcribing indicator before implementing an
`NSPanel` or other AppKit interop surface.

## Scope

- Define visible states, placement, focus behavior, copy, and dismissal timing.
- Define disabled setting behavior.
- Define error and done transitions.
- Define non-interference with the active app.

## Non-goals

- Do not implement the panel.
- Do not finalize visual design beyond product-level behavior.

## Acceptance

- A concise spec exists or the existing menu shell spec is updated.
- The spec states that the indicator must not steal focus.
- Verification command passes.

## Notes

- Read `docs/specs/features/menu-bar-app-shell.md`.
- Read `docs/specs/features/microphone-text-input.md`.
