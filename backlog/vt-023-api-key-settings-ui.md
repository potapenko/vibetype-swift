---
id: VT-023
title: API Key Settings UI
status: blocked
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

Status: blocked

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

## Result

- Added a native Settings OpenAI section with a secure API key entry.
- Saving writes through `KeychainService`, clears the visible field, and shows
  only saved, missing, or error state.
- The saved key can be replaced by entering a new key or removed from Settings.
- Updated the settings and secret-storage spec to preserve the no-echo
  Keychain-only behavior.

## Blocker Evidence

- 2026-06-21 CEST: implementation and spec update were added, but required
  Xcode build verification did not complete in this automation pass.
- `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build` timed out with
  `BUILD INTERRUPTED` after stalling during Xcode build-service external-tool
  probing.
- Narrow evidence passed:
  `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library
  $(rg --files vibetype Shared -g '*.swift' | sort)`.
- `git diff --check` passed.
- Runtime QA was blocked because the freshly changed app could not be built
  within the bounded run.
- 2026-06-21 22:52 CEST: closeout task `VT-151` reran the required recovery
  and macOS build retry from the current checkout. Recovery succeeded and
  removed only project-specific DerivedData
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-cgljxvuvdfxmqbeiqfwkdshvjovc`;
  no stale processes were matched or terminated.
- The bounded retry
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build` again reached
  `CreateBuildDescription` and the external clang probe, then ended with
  `** BUILD INTERRUPTED **` before compiler diagnostics or app product output.
- Runtime QA remains blocked because no fresh launchable app product was
  produced for Settings inspection.

## Resolution Path

- Blocker category: local Xcode build service hang.
- Follow-up task: `VT-148`
  (`backlog/vt-148-xcode-build-service-health.md`).
- Unblock condition: after the local Xcode build service reaches macOS build or
  test execution again, rerun
  `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination
  'platform=macOS' build` plus `git diff --check`.
- Next automatic recovery action: run
  `python3 scripts/local_tooling_recover.py --apply --json` before the next
  bounded retry, then rerun this build gate only after local Xcode health has
  changed or a blocker-resolution pass is selected.
- If the build passes, a blocker-resolution pass should launch the freshly
  built app, open Settings, verify the secure API key save/clear/remove states,
  and then mark this task done without additional source edits unless runtime
  QA finds a defect.
