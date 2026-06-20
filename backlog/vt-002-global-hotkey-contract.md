---
id: VT-002
status: in-progress
priority: P0
lane: specs
dependencies:
allowed_paths:
  - docs/specs/**
verification:
  - git diff --check
---

# Global Hotkey Contract Spec

Status: in-progress
Priority: P0
Lane: specs
Dependencies: none
Expected outputs: feature spec update, backlog update if needed, verification result
Verification: git diff --check

## Goal

Define global hotkey behavior before implementing `GlobalHotkeyService`.

## Scope

- Decide the default shortcut contract.
- Define hold-to-record versus toggle behavior.
- Define repeated key down/up handling and race prevention.
- Define collision, failure, and permission behavior.
- Define how the hotkey appears in settings and menu state.

## Non-goals

- Do not implement keyboard hooks.
- Do not add a full shortcut customization UI unless the spec requires it.
- Do not copy Electron hotkey architecture from OpenWhispr.

## Acceptance

- A concise spec exists under `docs/specs/features/`.
- The spec states the MVP default and fallback behavior.
- The spec makes parallel recordings impossible at product level.
- Verification command passes.

## Notes

- Read `docs/openwhispr_swiftui_codex_tz.md`.
- OpenWhispr hotkey behavior may be used as reference evidence, but the target
  implementation must remain native macOS Swift.
