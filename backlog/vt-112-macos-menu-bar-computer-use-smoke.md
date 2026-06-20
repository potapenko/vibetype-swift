---
id: VT-112
title: macOS Menu Bar Computer Use Smoke
status: backlog
priority: P2
lane: testing
parent: VT-110
dependencies:
  - VT-012
  - VT-013
allowed_paths:
  - docs/qa/**
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-112-macos-menu-bar-computer-use-smoke.md
---

# VT-112 - macOS Menu Bar Computer Use Smoke

Status: backlog

## Goal

Create the first bounded macOS runtime smoke evidence for the real menu bar
app surface.

## Scope

- Build and launch the freshly built macOS app.
- Use Computer Use to verify that the app exposes a menu bar item, opens its
  menu, and opens Settings.
- Save a concise task-scoped QA report under `docs/qa/macos/`.
- Do not require real microphone input, OpenAI credentials, permission prompts,
  or an unbounded manual session.

## Acceptance

- A short QA report records the build command, app launch path, Computer Use
  scenario, observed menu bar/Settings behavior, and pass/fail/blocker result.
- The smoke uses bounded stop conditions and does not require real microphone,
  OpenAI, or permission changes.
- If Computer Use or app launch is blocked, the report captures the exact
  blocker and last successful build/test evidence.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- Bounded Computer Use smoke against the launched app, or a concrete blocker
  report under `docs/qa/macos/`
- `git diff --check`
