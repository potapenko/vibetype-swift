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

Blocked by Build iOS Apps / XcodeBuildMCP transport failure.

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

Fresh evidence from the 2026-06-22 blocker-resolution sweep:

- VT-117 added the first minimal iOS containing-app target and shared
  `vibetype-iOS` scheme.
- `/opt/homebrew/bin/timeout 120 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype-iOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  build -quiet` completed successfully against a concrete iPhone 17 Pro
  simulator.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build -quiet` completed
  successfully.
- XcodeBuildMCP first returned empty session defaults, then `list_sims` and a
  follow-up `session_show_defaults` failed with `Transport closed`, so the
  required Build iOS Apps baseline flow could not be completed.

## Resolution Path

- Blocker category: Build iOS Apps / XcodeBuildMCP transport failure.
- Follow-up task: `VT-117`
  (`backlog/vt-117-ios-containing-app-target-skeleton.md`) is still blocked
  only on the required MCP build/run flow, not missing repository target
  source.
- Unblock condition: when XcodeBuildMCP transport is healthy, set session
  defaults for project `vibetype.xcodeproj`, scheme `vibetype-iOS`, and a
  concrete iOS Simulator such as `iPhone 17 Pro`, then rerun the simulator
  baseline command path from `docs/agent-tooling.md` and save any useful
  screenshot evidence under `docs/qa/`.
- No macOS product source edits belong in this simulator baseline task.

## Verification

- `git diff --check`
