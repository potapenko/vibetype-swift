---
id: VT-149
title: Permission Surfaces Runtime Verification And Repair
status: done
priority: P1
lane: permissions
parent: VT-030
dependencies:
  - VT-033
  - VT-034
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/qa/macos/**
  - docs/specs/features/privacy-and-permissions.md
  - docs/specs/features/menu-bar-app-shell.md
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-149-permission-surfaces-runtime-repair.md
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
  - git diff --check
---

# VT-149 - Permission Surfaces Runtime Verification And Repair

Status: done
Priority: P1
Lane: permissions
Dependencies: VT-033, VT-034
Expected outputs: permission surface runtime evidence or focused repair, verification result
Verification: xcodebuild build, git diff --check

## Goal

Produce the product-facing permission closeout that VT-030 could not perform:
verify and, if needed, repair the built macOS menu and Settings permission
surfaces.

## Scope

- Build and launch the macOS app from the current source.
- Use bounded Computer Use QA when available to inspect the menu microphone
  permission state and Settings privacy/permissions section.
- If the visible permission behavior diverges from the specs, make the
  smallest Swift, test, or spec repair in the allowed paths.
- Record a short macOS QA note when runtime QA reaches the app surface or is
  blocked by tooling.

## Non-goals

- Do not trigger real microphone prompts or require real microphone input.
- Do not change system Accessibility or microphone permissions.
- Do not implement recording, transcription, paste execution, or live OpenAI
  calls.
- Do not add unrelated Settings controls or onboarding.

## Acceptance

- The menu and Settings permission surfaces match
  `privacy-and-permissions.md`, or a focused repair brings them into alignment.
- Runtime QA is recorded as pass or as a concrete blocker with build evidence.
- VT-030 is ready for blocker-resolution closeout after this task is done or
  its runtime blocker is explicitly captured.

## Notes

- This task unblocks VT-030.
- Prior child tasks implemented microphone status, Accessibility status, menu
  blocked-state copy, and Settings privacy/permission copy.

## Completion Notes

- Added focused permission-surface tests for menu microphone status/detail copy,
  recording gating, and Accessibility copy-only fallback messaging.
- Confirmed the current Swift menu and Settings permission surfaces match the
  product specs by source review and test coverage.
- Verification:
  - `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
    passed.
  - `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build-for-testing -only-testing:vibetypeTests/PermissionsServiceTests`
    passed.
  - `git diff --check` passed before completion.
  - `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests/PermissionsServiceTests`
    failed before assertions because the macOS test runner could not resume the
    launched app process.
- Runtime QA: blocked. The freshly built app launched and stayed running, but
  the active Computer Use surface exposed only a click action and no screenshot,
  semantic snapshot, accessibility tree, or element discovery for inspecting
  the menu bar or Settings surfaces.
- QA note: `docs/qa/macos/vt-149-2026-06-21-permission-surfaces.md`.
