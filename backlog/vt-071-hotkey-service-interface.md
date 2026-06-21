---
id: VT-071
title: Hotkey Service Interface
status: blocked
priority: P2
lane: hotkey
parent: VT-070
dependencies:
  - VT-000
  - VT-002
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-071-hotkey-service-interface.md
---

# VT-071 - Hotkey Service Interface

Status: blocked

## Goal

Add a Swift-native service boundary for global hotkey registration.

## Scope

- Define the hotkey service API and fake implementation.
- Represent the default dictation shortcut display.
- Do not register real global events in this task unless it is already trivial.

## Acceptance

- Controller code can subscribe to a hotkey action through the boundary.
- Tests can trigger the hotkey through a fake.
- The default shortcut is visible as data.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Blocker Evidence

- 2026-06-20: Implemented the service boundary and fake-backed tests, but
  Xcode verification did not complete in this local session.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  blocked in Xcode target-runner materialization/finalization and was
  interrupted after bounded waits.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  hit the same target-runner blocker.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' -derivedDataPath /tmp/vibetype-swift-vt071-derived build`
  also stopped returning progress after build graph creation and was
  interrupted after bounded waits.
- Narrow checks completed: app source `swiftc -typecheck` passed, app module
  `swiftc -emit-module -enable-testing` passed, and `git diff --check` passed.
- 2026-06-22: `VT-157` reran the focused verification from the current
  checkout after
  `python3 scripts/local_tooling_recover.py --apply --json`.
- Recovery removed generated project DerivedData at
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-cgljxvuvdfxmqbeiqfwkdshvjovc`
  and found no stale Xcode/test processes before retry.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode build-description external-tool probing, did not reach compiler
  diagnostics, test discovery, or test execution, and ended with
  `** BUILD INTERRUPTED **`.
- Post-timeout recovery removed generated `scripts/__pycache__` and found no
  remaining stale run-owned Xcode/test processes.
- Fresh QA note:
  `docs/qa/runs/hotkey-service-closeout-2026-06-22.md`.

## Resolution Path

- Blocker category: local Xcode test/build service hang.
- Unblock condition: after the local Xcode build service returns progress,
  rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  and `git diff --check`.
- If focused tests pass, a blocker-resolution pass may mark this task done
  without additional source edits because the hotkey service boundary, default
  shortcut data, and fake-backed test seam are already present.
- If Xcode still blocks before test execution, record the fresh bounded Xcode
  blocker and keep using the existing `swiftc` checks only as narrow sanity
  evidence.
- Existing infrastructure evidence: `VT-148`
  (`backlog/done/vt-148-xcode-build-service-health.md`) records the same
  automation-recoverable Xcode external-tool probe timeout class.
