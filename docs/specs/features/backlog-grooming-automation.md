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
3. Read `docs/specs/features/ui-functionality-coverage.md`.
4. Inspect current Swift source shape.
5. Inspect only the relevant reference source files.
6. Add or refine backlog tasks for missing behavior.
7. Update the UI/functionality coverage map when a surface, flow, reference
   mapping, task status, or known gap changes.
8. Prefer parent umbrella tasks plus small child tasks for large areas.
9. Keep task files short, scoped, and verifiable.
10. Review the generated diff before committing and split or tighten any task
   that is broader than one agent checkpoint.
11. Run
   `python3 scripts/backlog_next.py --json`
   after edits.
12. Commit only backlog/spec/workflow edits made by the groomer.

## Completed Task Archive

Completed tasks should not permanently crowd the active queue.

The archive agent moves verified `done` task files from top-level `backlog/` to
`backlog/done/`. The move preserves the Markdown record and keeps the task id
available to selectors as dependency evidence.

The archive agent must:

- run `scripts/backlog_archive_done.py` in dry-run or apply mode;
- move only clean task files whose front matter and visible status are both
  `done`;
- skip `backlog`, `ready`, `in-progress`, and `blocked` tasks;
- skip status mismatches, destination collisions, unavailable Git status, and
  uncommitted source task changes;
- rerun normal and blocked selectors after an apply run;
- commit only the moved task files and archive-tooling changes it owns.

Normal selectors read `backlog/done/*.md` only as dependency records. Archived
done tasks must not be selectable implementation work.

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

Before committing, the groomer should re-read each new or materially changed
child task and confirm that it has:

- one primary observable output
- explicit dependencies and allowed paths
- concrete acceptance criteria
- verification that matches the task layer
- non-goals when adjacent product scope is easy to accidentally include

If a child task mixes UI, service work, permissions, network behavior, or
persistence in one implementation slice, split it or make it an umbrella before
the groomer commit is created.

## Coverage Map

The groomer must keep `docs/specs/features/ui-functionality-coverage.md` as the
durable bridge between product surfaces, OpenWhispr behavior evidence, current
Swift files, backlog task ids, and verification needs.

When auditing reference behavior, "covered by existing tasks" is only a valid
completion reason when each cited behavior maps to one of:

- a `done` task with current implementation evidence;
- a dependency-ready task selected or selectable by `scripts/backlog_next.py`;
- a blocked task with a concrete resolver path and the first unblock action
  recorded in the coverage map.

A blocked task is not sufficient coverage by itself. If useful reference
behavior maps only to blocked or dependency-pending tasks, the groomer must
record that gap and either refine the unblock path or add one small task that
makes the next product delta executable.

The map is not a substitute for specs or task completion. It is a navigation
artifact that prevents audits from declaring broad UI behavior covered while
the visible app still contains placeholders or disconnected service seams.

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
