---
id: VT-022
title: Keychain API Key Storage
status: backlog
priority: P1
lane: settings
parent: VT-020
dependencies:
  - VT-021
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-022-keychain-api-key-storage.md
---

# VT-022 - Keychain API Key Storage

Status: backlog

## Goal

Add the MVP Keychain service for saving, loading, and clearing the OpenAI API
key.

## Scope

- Use macOS Keychain APIs.
- Keep the service injectable or fakeable for tests.
- Do not log the API key.
- Do not add network calls.

## Acceptance

- API key storage does not use UserDefaults.
- Empty or missing key is represented clearly.
- Tests avoid depending on a real user key.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
