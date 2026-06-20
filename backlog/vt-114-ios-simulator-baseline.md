---
id: VT-114
title: iOS Simulator Baseline
status: in-progress
priority: P3
lane: ios
parent: VT-110
dependencies:
  - VT-113
allowed_paths:
  - vibetype/**
  - docs/qa/**
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-114-ios-simulator-baseline.md
---

# VT-114 - iOS Simulator Baseline

Status: in-progress

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

## Verification

- `git diff --check`
