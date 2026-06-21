---
id: VT-150
title: Menu Bar Identity Blocker Closeout
status: backlog
priority: P0
lane: swift-app-shell
dependencies:
  - VT-000
allowed_paths:
  - backlog/vt-015-menu-bar-identity-tooltip.md
  - backlog/vt-150-menu-bar-identity-closeout.md
  - docs/qa/runs/**
verification:
  - python3 scripts/local_tooling_recover.py --apply --json
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
  - git diff --check
---

# VT-150 - Menu Bar Identity Blocker Closeout

Status: backlog
Priority: P0
Lane: swift-app-shell
Dependencies: VT-000
Expected outputs: VT-015 closeout update, verification result
Verification: local tooling recovery, macOS build, git diff --check

## Goal

Close the stale verification blocker on `VT-015` so the menu bar MVP umbrella
has an executable path again.

## Scope

- Run `python3 scripts/local_tooling_recover.py --apply --json` before retrying
  Xcode verification.
- Rerun the `VT-015` macOS build gate from the current checkout.
- If the build and `git diff --check` pass, update only `VT-015` and this task
  to record completion.
- If the build still fails before useful compiler diagnostics, keep `VT-015`
  blocked and add the fresh bounded recovery/build evidence to its blocker
  notes.

## Non-goals

- Do not change Swift app code, Xcode project settings, specs, assets, or menu
  behavior in this closeout task.
- Do not add new OpenWhispr reference translation.
- Do not rerun broad runtime QA unless the verification result shows new source
  behavior changed in this task.

## Acceptance

- `VT-015` is either marked done with current build evidence or has a fresh
  blocker note with recovery JSON and the bounded command result.
- The task preserves the existing native SwiftUI/AppKit menu-bar scope.
- No unrelated backlog or source files are modified.

## Tooling Assumptions

- Use standard `xcodebuild` for the macOS build gate.
- Local Xcode/DerivedData/tooling recovery is automation-owned, not a user
  cleanup chore.
