---
id: VT-149
title: Permission Surfaces Runtime Verification And Repair
status: backlog
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

Status: backlog
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
