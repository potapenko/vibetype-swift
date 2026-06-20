# macOS QA

This directory is the lightweight QA layer for VibeType's native macOS app.
It adapts the optional browser-QA pattern from `spec-first-bootstrap` to a
menu bar SwiftUI/AppKit product.

## Purpose

Use this layer when a task changes user-visible macOS behavior:

- menu bar item and menu contents
- Settings screens
- permission-state UI
- recording or transcription status shown to the user
- floating indicator behavior
- active-app text handoff and clipboard/paste behavior
- any new or changed button, toggle, field, screen, panel, or menu action

## Principles

- Specs define the product contract.
- Unit and fake-backed tests prove deterministic service logic.
- Computer Use smoke proves that the built app can be launched and operated by
  a user through the real macOS UI.
- QA evidence records what was checked; it does not replace specs or tests.

## Required Decision

Each implementation run with a product delta must classify runtime QA:

- `required`: the task changes visible UI or an end-to-end user interaction.
- `not_applicable`: the task is model/service-only and is covered by tests or
  build evidence.
- `blocked`: the app or UI surface cannot be launched or inspected within the
  bounded run.

When runtime QA is `required`, the agent must launch or relaunch the built app,
use Computer Use to open the affected UI, perform the changed action, inspect
the result, and report the observed behavior.

When runtime QA is `blocked`, the agent must record the exact blocker, the
last successful build/test evidence, and the next shortest command or action to
resume.

## Suggested Structure

```text
docs/qa/
  macos/
    README.md
    AGENTS.run.md
    templates/
      case.template.md
      report.template.md
  runs/
    <task-id>-<date>-<short-slug>.md
```

Create durable case or run files only when useful. For small passing smokes,
the automation final report may carry the evidence.
