# Backlog Grooming Automation

## Goal

Keep `backlog/` populated with small, implementation-ready tasks derived from:

- `docs/openwhispr_swiftui_codex_tz.md`
- current Swift repository state
- specs under `docs/specs/`
- reference OpenWhispr source under `references/openwhispr-main/`

The groomer turns product intent and reference behavior into agent-sized tasks.
It does not implement product code.

## Behavior

Each run should:

1. Read the repository workflow contract.
2. Read the MVP brief and existing specs.
3. Inspect current Swift source shape.
4. Inspect only the relevant reference source files.
5. Add or refine backlog tasks for missing behavior.
6. Prefer parent umbrella tasks plus small child tasks for large areas.
7. Keep task files short, scoped, and verifiable.
8. Run
   `python3 scripts/backlog_next.py --json`
   after edits.
9. Commit only backlog/spec/workflow edits made by the groomer.

## Task Size

Child tasks should usually have one observable output and fit a short agent
checkpoint. Examples:

- add one menu item
- create one service protocol
- add one settings field
- write one fake-backed unit test
- map one permission state

If a task needs more than one screen, service, or behavior contract, create a
parent task and split it into children.

## Reference Rules

OpenWhispr is a behavior reference, not an implementation dependency.

The groomer may translate reference scenarios into Swift-native tasks, such as:

- Electron tray menu behavior into `MenuBarExtra` or AppKit status item tasks
- clipboard paste helpers into `NSPasteboard` and `CGEvent` tasks
- React settings screens into SwiftUI settings sections
- JavaScript recording locks into Swift state-machine tasks

The groomer must not introduce Electron, React, Node, Tauri, Rust runtime code,
or local model dependencies.

## First Iteration Bias

The earliest implementation task should make the app visible as a menu bar app
with a new menu item before deeper services are built.

This gives the implementer a concrete native shell to extend and keeps the
first checkpoint visible.

## Non-Goals

- Do not implement Swift behavior.
- Do not rewrite the product brief.
- Do not delete existing tasks.
- Do not mark tasks complete unless the task work was actually done.
- Do not generate huge tasks that combine UI, services, permissions, and
  network behavior.
