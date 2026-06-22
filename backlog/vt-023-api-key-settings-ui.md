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
- 2026-06-22 11:37 CEST: blocker-resolution sweep retried
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build -quiet`; the macOS
  build completed successfully.
- The sweep launched the fresh debug app from project DerivedData, but Computer
  Use returned `timeoutReached` before exposing a reliable Settings inspection
  surface.
- The sweep did not save or remove an API key through the live Settings UI
  because `SettingsView` uses the default production Keychain service
  `com.potapenko.vibetype.openai` / `openai-api-key`; exercising remove-state
  could delete an operator's real saved key.
- The launched debug `vibetype.app` process was terminated after the bounded UI
  attempt.

## Resolution Path

- Blocker category: runtime Settings inspection and live Keychain safety.
- Follow-up task: `VT-151`
  (`backlog/vt-151-api-key-settings-closeout.md`).
- Unblock condition: rerun the Settings runtime closeout when Computer Use can
  expose the VibeType menu/window, and either use an isolated test Keychain
  namespace or get explicit operator approval before exercising remove-state on
  the production Keychain item.
- Build no longer blocks this task; a future closeout should not route back to
  `VT-148` unless a fresh bounded build fails again.
