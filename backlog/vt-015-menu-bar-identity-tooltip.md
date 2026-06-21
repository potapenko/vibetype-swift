---
id: VT-015
title: Menu Bar Identity And Tooltip
status: blocked
priority: P2
lane: swift-app-shell
parent: VT-010
dependencies:
  - VT-000
allowed_paths:
  - docs/specs/features/menu-bar-app-shell.md
  - vibetype/vibetypeApp.swift
  - vibetype/Assets.xcassets/**
  - backlog/vt-015-menu-bar-identity-tooltip.md
---

# VT-015 - Menu Bar Identity And Tooltip

Status: blocked

## Goal

Make the native menu bar item identity explicit and accessible.

## Reference Evidence

OpenWhispr's Electron tray keeps a dedicated tray icon, tooltip, and fallback
icon path in `references/openwhispr-main/src/helpers/tray.js`. VibeType should
translate only the product need: a recognizable native macOS menu bar item.

## Scope

- Confirm or update the menu bar label/icon contract in
  `docs/specs/features/menu-bar-app-shell.md`.
- Keep the implementation native SwiftUI/AppKit.
- If `MenuBarExtra` can express the chosen identity cleanly, update it there.
- If a tooltip or accessibility label requires leaving the current simple
  `MenuBarExtra` path, record the limitation in the spec and keep the smallest
  follow-up task rather than switching architecture in this slice.
- Do not copy Electron asset lookup, canvas fallback, packaging paths, or
  cross-platform tray behavior.

## Acceptance

- The menu bar item has a stable VibeType identity contract.
- The implementation or spec explains the chosen label/icon/tooltip behavior.
- Any unresolved native AppKit status-item work is captured as a small
  follow-up task.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`

## Blocker Evidence

2026-06-20:

- Implemented the native SwiftUI menu bar identity and updated the menu bar
  app shell spec, but the required Xcode build gate could not complete on the
  current host.
- Initial `xcodebuild -project vibetype.xcodeproj -scheme vibetype
  -destination 'platform=macOS' build` stalled in build description/external
  tool probing and then reported `No space left on device` while writing
  DerivedData attachments/logs.
- `df -h /Users` showed the data volume at 100% capacity, with only about
  113 MiB free before project-specific DerivedData cleanup and about 178 MiB
  free after a bounded retry.
- Removed only the generated project-specific Xcode DerivedData directory
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-gkapclbsegetweejyiilhpjsxaak`
  and retried the build once; the retry again did not reach compilation before
  the bounded cutoff and was interrupted.
- Narrow evidence passed:
  `xcrun swiftc -typecheck -parse-as-library $(rg --files vibetype -g '*.swift' | sort)`
  and `git diff --check`.
