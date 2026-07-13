# Brownfield Discovery

Status: current context map for the macOS MVP checkout.

This file is a small orientation aid. It is not exhaustive source inventory and
must not replace targeted `rg` / `rg --files` discovery before edits.

## Summary

`holdtype-swift` keeps the Xcode project at the repository root next to
spec-first documentation, backlog tasks, automation runbooks, scripts, and
reference material.

The active product phase is the native macOS menu bar MVP. iOS companion,
simulator, and keyboard-extension work are future v2 scope unless a direct user
request or v2-labeled task opts in.

## Targets And Schemes

- Xcode project: `HoldType.xcodeproj`
- Main macOS app target: `HoldType`
- iOS containing app target: `HoldType-iOS`
- Unit test target: `HoldTypeTests`
- iOS unit test target: `HoldTypeIOSTests`
- UI test target: `HoldTypeUITests`
- Primary scheme: `HoldType`

## Source Map

- `HoldType/HoldTypeApp.swift`
  - macOS app entry point, app state wiring, menu bar extra, and settings
    windows.
- `HoldType/MenuBarView.swift`
  - menu bar controls and dictation status presentation.
- `HoldType/SettingsView.swift` and `HoldType/Settings/`
  - settings navigation, permissions, OpenAI key, transcription, translation,
    text correction, diagnostics, cache, and related settings sections.
- `HoldType/FloatingIndicatorView.swift` and
  `HoldType/FloatingIndicatorPanelController.swift`
  - recording/transcribing indicator UI and panel hosting.
- `HoldType/Models/`
  - persisted settings, setup status, dictation status, output intent, usage
    estimates, and transcript/history models.
- `HoldType/Services/`
  - microphone recording, transcription request building, OpenAI transcription,
    text correction, translation, text insertion, permissions, Keychain,
    hotkeys, diagnostics, recording cache, setup preflight, transcript history,
    runtime orchestration, and active text context.
- `Shared/`
  - shared setup/status presentation and containing-app startup seams; the
    obsolete keyboard-session spike was removed after Brand Stage cutover.
- `HoldTypeTests/`
  - focused unit coverage for services, settings view models, setup status,
    hotkeys, text insertion, OpenAI request handling, history, and diagnostics.
- `HoldTypeIOS/`, `HoldTypeIOSTests/`, `HoldTypeUITests/`
  - exploratory or future-version surfaces unless a direct request targets
    them.

## Product Specs

Start with `docs/specs/index.md` to choose a feature spec. Read only the
feature spec that governs the behavior being changed. Do not read every spec by
default.

The initial MVP brief in `docs/openwhispr_swiftui_codex_tz.md` is fallback
evidence only. Use it when a current spec does not settle a behavior.

## Backlog And Automation

Normal direct-chat work does not use backlog mode. Backlog selection,
claiming, archiving, and scheduled automation rules live in
`BACKLOG_DEVELOPMENT.md` and the relevant runbook.

Use compact selector readback by default:

```sh
python3 scripts/backlog_next.py --compact-json
```

Use full `--json` only when detailed queue diagnostics are needed.

## Reference Material

`references/openwhispr-main/` is behavior evidence only. Do not scan it broadly
or port Electron, React, Node.js, local model downloader, updater, account,
billing, cloud sync, or telemetry behavior into this Swift app unless a future
spec explicitly changes scope.

## Verification Baseline

For Swift behavior changes:

```sh
xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination 'platform=macOS' build
git diff --check
```

When tests or test-covered behavior change:

```sh
xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination 'platform=macOS' test
git diff --check
```

For docs/spec/runbook-only changes, `git diff --check` is usually enough unless
the edited commands or scripts should be exercised.
