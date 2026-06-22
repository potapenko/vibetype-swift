---
id: VT-161
status: in-progress
priority: P1
lane: hotkey
dependencies:
allowed_paths:
  - docs/specs/features/global-hotkey.md
  - vibetype/Services/GlobalHotkeyService.swift
  - vibetypeTests/GlobalHotkeyServiceTests.swift
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# VT-161 - Hotkey Default Shortcut Preferences

Status: in-progress
Priority: P1
Lane: hotkey
Dependencies: none
Expected outputs: global hotkey spec, default shortcut model update, focused tests
Verification: xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test; git diff --check

## Goal

Make the dictation hotkey contract match the preferred personal workflow:
Right Command hold-to-record by default, with Globe/Fn hold-to-record available
as an alternate shortcut option for keyboards that have it.

## Scope

- Update `docs/specs/features/global-hotkey.md` for the default and alternate
  dictation shortcuts.
- Update the Swift hotkey model constants and display text.
- Update focused hotkey tests for the new default and alternate shortcut.

## Non-goals

- Full shortcut editing UI.
- Native event-tap implementation for right-side modifier or Globe/Fn delivery.
- Changing the VibeType Clipboard paste shortcut.

## Acceptance

- The spec no longer names `Option+Space` as the MVP default.
- The default configuration displays `Right Command - Hold to record`.
- The alternate configuration displays `Globe/Fn - Hold to record`.
- Focused hotkey tests cover both shortcut values.
