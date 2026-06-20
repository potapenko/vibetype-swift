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

Create the first bounded macOS runtime smoke checklist for Computer Use.

## Scope

- Document how to verify that the app launches, exposes a menu bar item, opens
  its menu, and opens Settings.
- Record what evidence should be kept under `docs/qa/`.
- Do not implement product code or run an unbounded manual session.

## Acceptance

- A short QA checklist exists for menu bar smoke.
- The checklist defines a bounded stop condition and blocker format.
- The checklist does not require real microphone, OpenAI, or permissions.

## Verification

- `git diff --check`
