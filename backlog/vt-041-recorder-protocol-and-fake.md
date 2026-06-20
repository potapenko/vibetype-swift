---
id: VT-041
title: Recorder Protocol And Fake
status: in-progress
priority: P1
lane: recording
parent: VT-040
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-041-recorder-protocol-and-fake.md
---

# VT-041 - Recorder Protocol And Fake

Status: in-progress

## Goal

Create the recorder service boundary before adding AVFoundation details.

## Scope

- Define the recorder protocol or interface.
- Add a fake implementation suitable for tests and controller work.
- Model start, stop, cancel, and current status.

## Acceptance

- App/controller code can depend on the protocol.
- Fake recorder can simulate success and failure.
- No real microphone capture is added.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
