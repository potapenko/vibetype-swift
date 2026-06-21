---
id: VT-030
title: Permissions Umbrella
status: blocked
priority: P1
lane: permissions
dependencies:
  - VT-031
  - VT-032
  - VT-033
  - VT-034
  - VT-149
allowed_paths:
  - backlog/**
  - docs/specs/features/privacy-and-permissions.md
---

# VT-030 - Permissions Umbrella

Status: blocked

## Goal

Close out the MVP permission behavior after microphone and accessibility child
tasks land.

## Child Tasks

- VT-031 microphone permission status
- VT-032 accessibility permission status
- VT-033 permission blocked menu state
- VT-034 Settings permissions and privacy section
- VT-149 permission surfaces runtime verification and repair

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`

## Blocker Evidence

- The selected scope is an umbrella closeout with allowed paths limited to
  backlog metadata and `docs/specs/features/privacy-and-permissions.md`.
- The implementer runbook requires a concrete product delta before a selected
  task can be marked `done`.
- The permissions child tasks have landed, but this selected scope cannot
  change Swift code, tests, runtime configuration, or QA evidence for the
  visible permission surfaces.

## Resolution Path

- Blocker category: no product delta possible from selected scope.
- Follow-up task: VT-149
  (`backlog/vt-149-permission-surfaces-runtime-repair.md`).
- Unblock condition: VT-149 verifies or repairs the built macOS menu and
  Settings permission surfaces with bounded runtime evidence or records the
  exact runtime/tooling blocker.
- Current run cannot finish this directly because VT-030's allowed paths do
  not permit Swift, test, runtime QA report, or app configuration changes.
