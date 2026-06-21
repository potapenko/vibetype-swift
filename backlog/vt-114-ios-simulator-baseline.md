---
id: VT-114
title: iOS Simulator Baseline
status: blocked
priority: P3
lane: ios
parent: VT-110
dependencies:
  - VT-113
  - VT-117
allowed_paths:
  - vibetype/**
  - docs/qa/**
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-114-ios-simulator-baseline.md
---

# VT-114 - iOS Simulator Baseline

Status: blocked

## Goal

Establish the first XcodeBuildMCP / Build iOS Apps simulator baseline after an
iOS target exists.

## Scope

- Discover or configure the iOS target and simulator when available.
- Run a simulator build or test.
- Capture a screenshot or UI snapshot only if the app surface exists.
- Do not create the iOS target unless a selected implementation task explicitly
  authorizes it.

## Acceptance

- The repository has a documented simulator verification command or blocker.
- Any screenshot evidence is saved under `docs/qa/` when durable evidence is
  useful.
- The task does not disturb the macOS backlog queue.

## Blocker

Blocked by missing iOS product target.

Evidence from the 2026-06-21 automation pass:

- Xcode lists only the `vibetype`, `vibetypeTests`, and `vibetypeUITests`
  targets.
- `vibetype.xcodeproj/project.pbxproj` uses `SDKROOT = macosx` and
  has no `IPHONEOS_DEPLOYMENT_TARGET` or iOS app target.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype
  -showdestinations` reports only macOS destinations for the `vibetype`
  scheme.
- XcodeBuildMCP session defaults were empty; `list_sims` failed to return
  enabled simulators in this environment, and a direct `xcrun simctl list
  devices available -j` probe was interrupted after a bounded wait.

Next implementation task: VT-117 must add the first minimal iOS containing-app
target before this simulator baseline can be retried.

## Resolution Path

- Blocker category: iOS simulator/build environment.
- Follow-up task: `VT-117`
  (`backlog/vt-117-ios-containing-app-target-skeleton.md`) adds the first
  minimal iOS containing-app target.
- Unblock condition: after `VT-117` is complete and a concrete iOS Simulator
  device is available to Xcode/XcodeBuildMCP, rerun the simulator baseline
  command path from `docs/agent-tooling.md` and save any durable blocker or
  screenshot evidence under `docs/qa/`.
- No macOS product source edits belong in this simulator baseline task.

## Verification

- `git diff --check`
