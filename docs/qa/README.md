# QA Evidence

This directory is for durable verification notes, smoke-check evidence, and
short manual QA reports.

Product behavior belongs in `docs/specs/`. Agent workflow belongs in
`AGENTS.md` and `BACKLOG_DEVELOPMENT.md`. QA files here record what was checked
and what happened.

## Evidence Rules

- Keep evidence short and task-scoped.
- Include the task id, command or tool used, result, and blocker if any.
- Do not store API keys, raw dictated text, raw audio, authorization headers, or
  full provider responses.
- Prefer fake-backed tests for services and state machines.
- Use runtime screenshots only for user-visible UI tasks.
- Keep all runtime checks bounded; do not wait indefinitely for permissions,
  network calls, audio capture, simulators, or app launch.

## Tool Roles

- `xcodebuild` or XcodeBuildMCP: build and test Apple targets.
- Computer Use: inspect the running macOS app when a task changes menu bar,
  settings, permission UI, floating indicator, or active-app handoff behavior.
- Build iOS Apps / XcodeBuildMCP: build, test, run, snapshot, and screenshot
  future iOS app and keyboard-extension surfaces in Simulator.

## Suggested Report Shape

```text
# VT-000 QA

Date:
Task:
Build/Test:
Runtime Tool:
Scenario:
Result:
Evidence:
Blocker:
```
