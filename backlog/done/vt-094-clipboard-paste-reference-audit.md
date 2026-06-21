---
id: VT-094
title: Clipboard Paste Reference Audit
status: done
priority: P2
lane: reference-audit
parent: VT-090
dependencies:
allowed_paths:
  - docs/specs/features/text-output-workflow.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-094-clipboard-paste-reference-audit.md
  - backlog/**
---

# VT-094 - Clipboard Paste Reference Audit

Status: done

## Goal

Audit OpenWhispr clipboard and paste helpers and translate missing behavior into
small Swift-native tasks.

## Scope

- Inspect `references/openwhispr-main/src/helpers/clipboard.js`.
- Inspect `references/openwhispr-main/resources/macos-fast-paste.swift`.
- Focus on copy, auto-paste, accessibility gating, delays, and restore.
- Do not implement Swift code in this audit task.

## Acceptance

- Clipboard and paste MVP behavior is fully represented by tasks or specs.
- New tasks use `NSPasteboard`, accessibility trust checks, and native events.
- No Node/Electron clipboard dependency is introduced.

## Audit Notes

- `references/openwhispr-main/src/helpers/clipboard.js` writes the transcript to
  the clipboard before any paste attempt, gates macOS paste on Accessibility
  trust, uses a copy-only fallback when trust or paste execution fails, and
  restores the previous clipboard only after a successful paste.
- The reference's macOS helper posts Cmd+V with `CGEvent` after
  `AXIsProcessTrusted()`. VibeType should preserve that native boundary and
  avoid Electron, Node.js, or AppleScript paste helpers.
- Existing task VT-062 now carries the missing native paste delay, timeout, and
  failure fallback requirements.
- Existing task VT-063 now carries the missing restore-after-success-only and
  copy-only fallback requirements.
- No new backlog task was needed; the existing text-output children cover copy,
  paste, restore, and last-transcript integration.

## Verification

- `python3 scripts/backlog_next.py --json`
- `git diff --check`
