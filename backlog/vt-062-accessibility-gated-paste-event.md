---
id: VT-062
title: Accessibility Gated Paste Event
status: backlog
priority: P1
lane: text-output
parent: VT-060
dependencies:
  - VT-032
  - VT-061
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-062-accessibility-gated-paste-event.md
---

# VT-062 - Accessibility Gated Paste Event

Status: backlog

## Goal

Add auto-paste behavior using a macOS Cmd+V event only when accessibility
permission allows it.

## Scope

- Send paste through a Swift-native event boundary such as `CGEvent` Cmd+V.
- Write the transcript to the clipboard before posting the paste event.
- Use a short bounded clipboard-settle delay and a bounded paste timeout.
- Block or fall back to copy-only when accessibility is missing.
- Keep the transcript on the clipboard when paste fails or times out.
- Do not use Electron, Node.js, or AppleScript helpers for the Swift paste path.
- Do not implement clipboard restore in this task.

## Acceptance

- Paste attempts are permission-gated.
- Missing accessibility permission does not lose transcript text.
- Paste timeout or event failure leaves copy-only fallback available.
- Tests can verify the boundary without posting real key events.

## Source Evidence

- OpenWhispr's `clipboard.js` writes the transcript to the clipboard before
  attempting macOS paste, checks Accessibility trust, keeps a copy-only fallback
  when trust is missing, and bounds paste helper waits.
- `references/openwhispr-main/resources/macos-fast-paste.swift` shows the native
  macOS primitive for this app: check `AXIsProcessTrusted()`, then post Cmd+V
  with `CGEvent`.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
