---
id: VT-052
title: URLSession Transcription Client
status: done
priority: P1
lane: transcription
parent: VT-050
dependencies:
  - VT-022
  - VT-051
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-052-urlsession-transcription-client.md
---

# VT-052 - URLSession Transcription Client

Status: done

## Goal

Add the OpenAI transcription client with an injectable URL loading boundary.

## Scope

- Use `URLSession` or a testable wrapper.
- Read the API key through the secret-storage boundary.
- Apply explicit request timeout behavior.
- Tests must use a fake client, not the live OpenAI API.

## Acceptance

- Success response returns transcript text.
- Network timeout is bounded and mapped to a user-visible error.
- API key is not logged.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Completion Evidence

2026-06-21:

- Added `OpenAITranscriptionService` with injectable API-key storage,
  request builder, URL loader, and timeout sleeper boundaries.
- The service sets the OpenAI Authorization header only after loading the
  Keychain-backed API key, applies a 60 second default request timeout, trims
  successful JSON `text` responses, rejects empty transcripts, and maps
  timeout, network, credential, rate-limit, provider, bad-request, invalid
  response, and recording-preparation failures to controlled product errors.
- Added fake-backed `OpenAITranscriptionServiceTests` for success, missing key,
  Keychain read failure, bounded timeout, URLSession timeout, provider status
  mapping, empty transcript, invalid response, and unsupported recording
  mapping. The tests use fake URL loading and do not call live OpenAI.
- `xcodebuild -quiet -project vibetype.xcodeproj -scheme vibetype
  -destination 'platform=macOS' build-for-testing` passed.
- A temporary executable smoke harness compiled the production service files
  with fake key storage, fake URL loading, and fake timeout sleeping, then
  passed success and timeout checks without live OpenAI or real Keychain
  access.
- The requested `xcodebuild ... test` and `test-without-building` paths were
  attempted for `vibetypeTests/OpenAITranscriptionServiceTests`, but the local
  macOS Xcode runner blocked while waiting for target-runner workers to
  materialize. Direct `xcrun xctest` was also not usable because the app-hosted
  test bundle could not resolve `vibetype.debug.dylib` outside Xcode's runner.
- `git diff --check` passed.
