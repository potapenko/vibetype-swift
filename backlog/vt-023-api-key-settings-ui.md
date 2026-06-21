---
id: VT-023
title: API Key Settings UI
status: in-progress
priority: P1
lane: settings
parent: VT-020
dependencies:
  - VT-013
  - VT-022
allowed_paths:
  - vibetype/**
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-023-api-key-settings-ui.md
---

# VT-023 - API Key Settings UI

Status: in-progress

## Goal

Add the native settings field for entering and saving the OpenAI API key.

## Scope

- Add a secure API key field to the settings view.
- Save through the Keychain service.
- Show saved or missing state without revealing the full key.

## Acceptance

- The user can enter and save a key.
- The full key is not echoed after save.
- No key appears in default logs.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
