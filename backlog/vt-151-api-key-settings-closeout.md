---
id: VT-151
title: API Key Settings Blocker Closeout
status: blocked
priority: P1
lane: settings
dependencies:
  - VT-013
  - VT-022
  - VT-148
allowed_paths:
  - backlog/vt-023-api-key-settings-ui.md
  - backlog/vt-151-api-key-settings-closeout.md
  - docs/qa/runs/**
verification:
  - python3 scripts/local_tooling_recover.py --apply --json
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
  - git diff --check
---

# VT-151 - API Key Settings Blocker Closeout

Status: blocked
Priority: P1
Lane: settings
Dependencies: VT-013, VT-022, VT-148
Expected outputs: VT-023 closeout update, verification/runtime QA result
Verification: local tooling recovery, macOS build, git diff --check

## Goal

Close the stale verification/runtime blocker on `VT-023` without widening the
settings implementation scope.

## Scope

- Run local tooling recovery before retrying Xcode verification.
- Rerun the `VT-023` macOS build gate from the current checkout.
- If a launchable product is produced and a Computer Use inspection surface is
  available, open Settings and verify the secure API key saved/missing/remove
  states described in `VT-023`.
- If build and any required runtime QA pass, update only `VT-023` and this task
  to record completion.
- If build or runtime QA remains blocked, keep `VT-023` blocked and append the
  fresh bounded evidence.

## Non-goals

- Do not change Settings UI, Keychain behavior, source code, specs, or Xcode
  project settings in this closeout task.
- Do not inspect live secrets or log API keys.
- Do not add unsupported provider, account, cloud, or telemetry settings.

## Acceptance

- `VT-023` is either marked done with current build/runtime evidence or carries
  fresh blocker evidence and the next automatic recovery action.
- Runtime QA is recorded as pass, not applicable with reason, or blocked with
  the exact tool/app blocker.
- No unrelated backlog or source files are modified.

## Tooling Assumptions

- Use standard `xcodebuild` for the macOS build gate.
- Use Computer Use only for bounded visible Settings verification after a
  fresh app product exists and an inspection surface is available.

## Result

- Ran local tooling recovery before retrying the build gate.
- Recovery succeeded, matched no stale processes, and removed only
  project-specific DerivedData:
  `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/vibetype-cgljxvuvdfxmqbeiqfwkdshvjovc`.
- Retried
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build`.
- The build reached Xcode build-description/external-tool probing and ended
  with `** BUILD INTERRUPTED **` before compiler diagnostics or app product
  output.
- Updated `VT-023` with the fresh bounded blocker evidence.
- 2026-06-22 11:37 CEST: blocker-resolution sweep retried
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj
  -scheme vibetype -destination 'platform=macOS' build -quiet`; the macOS
  build completed successfully.
- The sweep launched the fresh debug app from project DerivedData, but Computer
  Use returned `timeoutReached` before exposing a reliable Settings inspection
  surface.
- The sweep terminated the launched debug `vibetype.app` process after the
  bounded UI attempt.

## Runtime QA

- Result: blocked.
- Reason: a fresh launchable macOS app product was produced, but Computer Use
  did not expose a reliable Settings inspection surface. The sweep also did not
  save or remove an API key through the live Settings UI because that UI uses
  the production Keychain service `com.potapenko.vibetype.openai` /
  `openai-api-key`, and exercising remove-state could delete an operator's real
  saved key.

## Resolution Path

- Blocker category: runtime Settings inspection and live Keychain safety.
- Follow-up task: none yet; this closeout is already the narrow follow-up for
  `VT-023`.
- Unblock condition: rerun the Settings runtime closeout when Computer Use can
  expose the VibeType menu/window, and either use an isolated test Keychain
  namespace or get explicit operator approval before exercising remove-state on
  the production Keychain item.
- Build no longer blocks this closeout; do not route back to `VT-148` unless a
  fresh bounded build fails again.
