---
id: VT-010
title: Menu Bar MVP Umbrella
status: blocked
priority: P0
lane: swift-app-shell
dependencies:
  - VT-000
  - VT-015
  - VT-011
  - VT-012
  - VT-013
  - VT-014
allowed_paths:
  - backlog/**
  - docs/specs/features/menu-bar-app-shell.md
---

# VT-010 - Menu Bar MVP Umbrella

Status: blocked

## Goal

Close out the native menu bar MVP shell after its child tasks are implemented.

## Scope

- Review the completed menu bar child tasks together.
- Confirm the menu matches the MVP product spec.
- Patch only small gaps in docs or backlog discovered during closeout.

## Child Tasks

- VT-000 first visible menu bar item
- VT-015 menu bar identity and tooltip
- VT-011 app state model
- VT-012 start/stop label binding
- VT-013 settings menu opens a window
- VT-014 last transcript menu placeholders

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Result

- 2026-06-22: Blocked by the implementer product-first rule. This umbrella
  closeout is limited to backlog/spec paths, so the selected scope cannot
  produce app behavior, Swift source, executable tests, build/runtime
  configuration, or a verified product bug fix in the current run.
- Archived completed child tasks `VT-015` and `VT-150` before claim so the
  active selector sees only current queue work.
- 2026-06-22: `VT-158` produced a concrete product delta by adding executable
  menu-surface state coverage (`MenuBarPresentation` and
  `MenuBarPresentationTests`) for identity, permission copy, recording action
  labels/enabled states, transcript display/copy state, Settings, and Quit.
  The umbrella remains blocked because required Xcode build/test verification
  timed out before compiler output or unit-test execution, and runtime menu QA
  could not run without a fresh build product and a macOS menu interaction
  tool.
- 2026-06-22 01:12 CEST: Blocker resolver reran local tooling recovery and
  the required VT-158 gates. Recovery first terminated stale VibeType
  `xcodebuild`, `SWBBuildService`, and clang probe processes. The macOS build
  and focused `vibetypeTests` retry still exited 143 with
  `** BUILD INTERRUPTED **` at Xcode external-tool probing before compiler
  diagnostics or unit-test execution. `VT-158` remains the single follow-up
  task for this executable closeout blocker.
- 2026-06-22 02:16 CEST: Blocker resolver reran mandatory local tooling
  recovery before selection, which terminated stale VibeType `timeout`,
  child `xcodebuild`, `SWBBuildService`, and clang probe processes. The macOS
  build retry exited 143 with `** BUILD INTERRUPTED **` at the same early
  clang probe. Recovery after that retry found no remaining stale processes or
  generated artifacts. The focused `vibetypeTests` retry then exited 124 with
  `** BUILD INTERRUPTED **` before test discovery or execution, and final
  recovery again found no stale remnants. `VT-158` remains the single
  follow-up task for this executable closeout blocker.
- 2026-06-22 03:17 CEST: Blocker resolver reran mandatory local tooling
  recovery before selection, which removed `scripts/__pycache__` and
  terminated stale VibeType `timeout`, child `xcodebuild`,
  `SWBBuildService`, and clang probe processes. The macOS build retry reached
  the same early clang probe and exited 143 with `** BUILD INTERRUPTED **`
  before compiler diagnostics. Recovery after the build retry found no stale
  remnants. The focused `vibetypeTests` retry reached the same probe and
  exited 143 with `** BUILD INTERRUPTED **` before test discovery or
  execution, and final recovery again found no stale remnants. `VT-158`
  remains the single follow-up task for this executable closeout blocker.
- 2026-06-22 04:17 CEST: Blocker resolver reran mandatory local tooling
  recovery before selection, which removed generated `scripts/__pycache__`
  and project-scoped DerivedData and found no stale Xcode processes. The macOS
  build retry again reached Xcode's early `clang -v -E -dM ... /dev/null`
  external-tool probe and exited 143 with `** BUILD INTERRUPTED **` before
  compiler diagnostics. Recovery after the build retry found no remaining
  stale processes or artifacts. The focused `vibetypeTests` retry reached the
  same probe and exited 143 with `** BUILD INTERRUPTED **` before test
  discovery or execution. Final recovery removed regenerated project-scoped
  DerivedData and found no stale processes. `VT-158` remains the single
  follow-up task for this executable closeout blocker.
- 2026-06-22 05:18 CEST: Blocker resolver reran mandatory local tooling
  recovery before selection, which removed project-scoped DerivedData and
  found no stale Xcode processes. The macOS build retry again reached Xcode's
  early `clang -v -E -dM ... /dev/null` external-tool probe and exited 124
  with `** BUILD INTERRUPTED **` before compiler diagnostics. Recovery after
  the build retry found no remaining stale processes or artifacts. The focused
  `vibetypeTests` retry reached the same probe and exited 143 with
  `** BUILD INTERRUPTED **` before test discovery or execution. Final recovery
  found no stale processes or artifacts. `VT-158` remains the single follow-up
  task for this executable closeout blocker.
- 2026-06-22 06:20 CEST: Blocker resolver reran mandatory local tooling
  recovery before blocked selection and found no stale processes or generated
  artifacts. The macOS build retry again reached Xcode's early
  `clang -v -E -dM ... /dev/null` external-tool probe and exited 124 with
  `** BUILD INTERRUPTED **` before compiler diagnostics. Recovery after the
  build retry removed generated `scripts/__pycache__` and project-scoped
  DerivedData, with no stale Xcode processes left. The focused `vibetypeTests`
  retry reached the same probe and exited 124 with `** BUILD INTERRUPTED **`
  before test discovery or execution. Final recovery terminated stale run-owned
  timeout-wrapped and child `xcodebuild` processes and reported no remaining
  stale processes. `VT-158` remains the single follow-up task for this
  executable closeout blocker.
- 2026-06-22 07:15 CEST: Blocker resolver reran mandatory local tooling
  recovery before blocked selection, which removed generated `scripts/__pycache__`
  and project-scoped DerivedData and found no stale Xcode processes. The active
  XcodeBuildMCP surface still exposed no matching macOS build/test action for
  the selected verification, so the resolver used bounded shell `xcodebuild`.
  The macOS build retry again reached Xcode's early
  `clang -v -E -dM ... /dev/null` external-tool probe and exited 143 with
  `** BUILD INTERRUPTED **` before compiler diagnostics. Recovery after the
  build retry found no remaining stale processes or generated artifacts. The
  focused `vibetypeTests` retry reached the same probe and exited 143 with
  `** BUILD INTERRUPTED **` before test discovery or execution. Final recovery
  removed regenerated project-scoped DerivedData and found no stale processes.
  `VT-158` remains the single follow-up task for this executable closeout
  blocker.

## Resolution Path

- Blocker category: local Xcode build/test tooling timeout before compiler or
  unit-test execution; runtime menu QA also requires a build product and a
  macOS UI interaction surface that can operate the menu bar extra.
- Follow-up: `VT-158` in `backlog/vt-158-menu-bar-mvp-runtime-closeout.md`
  now owns the executable closeout evidence and current blocker details.
- Existing infrastructure evidence: `VT-148`
  (`backlog/done/vt-148-xcode-build-service-health.md`) records the same
  automation-recoverable Xcode build-service timeout class.
- Unblock condition: rerun local tooling recovery, then rerun the VT-158 build
  and focused unit-test gates until Xcode reaches compiler output and executes
  `vibetypeTests`; perform bounded menu runtime QA if a macOS UI interaction
  tool is available.
- Latest resolver retry could not mark this umbrella done because the new
  executable menu coverage still could not be verified through the required
  Xcode gates after local tooling recovery and bounded build/test retries.
