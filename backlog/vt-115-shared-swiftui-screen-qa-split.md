---
id: VT-115
title: Shared SwiftUI Screen QA Split
status: backlog
priority: P2
lane: testing
parent: VT-110
dependencies:
  - VT-013
  - VT-024
  - VT-113
allowed_paths:
  - docs/specs/features/**
  - docs/qa/**
  - backlog/vt-115-shared-swiftui-screen-qa-split.md
---

# VT-115 - Shared SwiftUI Screen QA Split

Status: backlog

## Goal

Define which SwiftUI screens should be shared across macOS and future iOS
surfaces, and how each platform should verify them.

## Scope

- Focus on Settings and onboarding-like screens.
- Separate reusable product behavior from platform-specific chrome.
- Do not refactor SwiftUI code in this task.

## Acceptance

- A spec or QA note states which screens are shared candidates.
- The note distinguishes macOS Computer Use smoke from iOS simulator smoke.
- Follow-up implementation tasks can use the split.

## Verification

- `git diff --check`
