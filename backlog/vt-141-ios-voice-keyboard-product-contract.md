---
id: VT-141
title: iOS Voice Keyboard Product Contract
status: backlog
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-113
allowed_paths:
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-141-ios-voice-keyboard-product-contract.md
verification:
  - git diff --check
---

# VT-141 - iOS Voice Keyboard Product Contract

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-113
Expected outputs: iOS keyboard spec update, verification result
Verification: git diff --check

## Goal

Refine the iOS keyboard feasibility spec into an explicit voice-keyboard MVP
contract.

## Scope

- Define the keyboard-visible states: unavailable/setup needed, idle/start,
  listening, confirming, transcribing, accepted text ready, error, and compact
  settings.
- Decide which settings may live inside the keyboard interface and which must
  open the containing app.
- Preserve the existing privacy boundary: provider calls, microphone consent,
  API key storage, and durable settings stay outside the keyboard extension
  unless a later spec explicitly changes that.
- Capture the Wispr Flow reference pattern: keyboard starts a bounded voice
  session, may hand off to the containing app, and returns to the host text
  context.

## Non-goals

- Do not add Swift implementation.
- Do not add a keyboard extension target.
- Do not promise direct microphone capture inside the keyboard extension.

## Acceptance

- `ios-keyboard-feasibility.md` states the product contract for voice-keyboard
  session start, listening, accept/cancel, settings, and unavailable states.
- The spec distinguishes compact inline keyboard settings from deep containing
  app setup.
- The verification mapping names the first simulator and keyboard-extension
  checks needed for implementation tasks.

## Notes

- Reference article:
  `https://9to5mac.com/2025/06/30/wispr-flow-is-an-ai-that-transcribes-what-you-say-right-from-the-iphone-keyboard/`
