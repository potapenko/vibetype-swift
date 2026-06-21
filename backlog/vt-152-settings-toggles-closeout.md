---
id: VT-152
title: Settings Toggles Blocker Closeout
status: blocked
priority: P2
lane: settings
dependencies:
  - VT-013
  - VT-021
  - VT-148
allowed_paths:
  - backlog/vt-024-mvp-settings-toggles.md
  - backlog/vt-152-settings-toggles-closeout.md
  - docs/qa/runs/**
verification:
  - python3 scripts/local_tooling_recover.py --apply --json
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
  - git diff --check
---

# VT-152 - Settings Toggles Blocker Closeout

Status: blocked
Priority: P2
Lane: settings
Dependencies: VT-013, VT-021, VT-148
Expected outputs: VT-024 closeout update, verification/runtime QA result
Verification: local tooling recovery, macOS build, git diff --check

## Goal

Close the stale verification/runtime blocker on `VT-024` so the settings
umbrella can progress.

## Scope

- Run local tooling recovery before retrying Xcode verification.
- Rerun the `VT-024` macOS build gate from the current checkout.
- If a launchable product is produced and a Computer Use inspection surface is
  available, open Settings and verify the MVP toggles listed in `VT-024`.
- If build and any required runtime QA pass, update only `VT-024` and this task
  to record completion.
- If build or runtime QA remains blocked, keep `VT-024` blocked and append the
  fresh bounded evidence.

## Non-goals

- Do not add or remove settings fields, persistence behavior, source code, or
  specs in this closeout task.
- Do not add advanced OpenWhispr settings.

## Acceptance

- `VT-024` is either marked done with current build/runtime evidence or carries
  fresh blocker evidence and the next automatic recovery action.
- Runtime QA is recorded as pass, not applicable with reason, or blocked with
  the exact tool/app blocker.
- No unrelated backlog or source files are modified.

## Tooling Assumptions

- Use standard `xcodebuild` for the macOS build gate.
- Use Computer Use only for bounded visible Settings verification after a
  fresh app product exists and an inspection surface is available.

## Result

- Ran local tooling recovery before retrying the `VT-024` build gate.
- Recovery succeeded, matched no stale processes, and removed no generated
  artifacts.
- Retried `/opt/homebrew/bin/timeout 300 xcodebuild -project
  vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`.
- The build completed with `** BUILD SUCCEEDED **` and produced a launchable
  app at
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-cgljxvuvdfxmqbeiqfwkdshvjovc/Build/Products/Debug/vibetype.app`.
- Updated `VT-024` with the fresh build-pass and runtime-QA blocker evidence.
- Added durable QA note
  `docs/qa/runs/settings-toggles-closeout-2026-06-21.md`.

## Runtime QA

- Result: blocked.
- Reason: the active Computer Use surface exposed only
  `mcp__computer_use.click`, with no screenshot, semantic snapshot,
  accessibility tree, or element discovery tool. Opening Settings by coordinate
  click would not produce reliable evidence for the MVP toggles, so no app
  launch or coordinate click was attempted.

## Resolution Path

- Blocker category: macOS Settings runtime inspection unavailable.
- Existing evidence to reuse: VT-112
  (`backlog/done/vt-112-macos-menu-bar-computer-use-smoke.md`) and
  `docs/qa/macos/vt-112-2026-06-21-menu-bar-smoke.md` already record the same
  Computer Use capability gap for menu bar and Settings inspection.
- Unblock condition: rerun the Settings closeout when Computer Use, or an
  equivalent macOS UI-reading tool, exposes screenshot, semantic snapshot,
  accessibility tree, or element discovery. Then open Settings and verify the
  five MVP Behavior toggles listed in `VT-024`.
