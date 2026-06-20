---
id: VT-113
title: iOS Keyboard Feasibility Spec
status: done
priority: P2
lane: ios
parent: VT-110
dependencies:
allowed_paths:
  - docs/specs/features/**
  - backlog/vt-113-ios-keyboard-feasibility-spec.md
---

# VT-113 - iOS Keyboard Feasibility Spec

Status: done

## Goal

Create the first iOS keyboard product feasibility spec before adding an iOS
target.

## Scope

- Capture Apple's custom keyboard constraints that affect dictation.
- Decide what belongs in the containing app versus keyboard extension for MVP.
- Define what shared SwiftUI screens may be reused from macOS.
- Do not add an iOS target or Swift implementation.

## Acceptance

- A concise spec exists under `docs/specs/features/`.
- The spec covers next-keyboard, secure-field, open-access, network, and
  microphone constraints.
- Follow-up implementation tasks can depend on the split.

## Verification

- `git diff --check`
