---
id: VT-031
title: Microphone Permission Status
status: backlog
priority: P1
lane: permissions
parent: VT-030
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-031-microphone-permission-status.md
---

# VT-031 - Microphone Permission Status

Status: backlog

## Goal

Add a Swift-native way to read and request microphone permission for the MVP.

## Scope

- Use AVFoundation permission APIs.
- Return explicit allowed, denied, not determined, or unavailable states.
- Keep actual recording out of this task.

## Acceptance

- Permission state can be queried without starting recording.
- Request flow is bounded and callback-driven.
- Tests use fakes if real permission prompts are not practical.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
