# Spec Index

Use this file to choose the smallest product spec slice for a task. Read the
matching feature spec, then verify exact source ownership with `rg --files`.

| Area | Spec | Read When |
| --- | --- | --- |
| iOS V1.1 release | `features/ios-v1-release.md` | Current iOS product, Voice, History, Settings, Library, privacy, or release-scope work; read the keyboard handoff spec with it for keyboard-originated dictation |
| iOS V1.1 voice state | `features/ios-v1-voice-state-persistence.md` | Current Pending, Latest Result, Retry/Discard, relaunch recovery, or replacement of legacy iOS persistence |
| iOS keyboard handoff and delivery | `features/ios-keyboard-handoff-and-delivery.md` | Canonical microphone tap, app opening, app-owned capture, return to host, request reconnection, exactly-once insertion, and app-only release fallback; this narrow contract wins conflicts with no-launch or manual-session clauses elsewhere |
| Menu bar shell | `features/menu-bar-app-shell.md` | Menu bar lifecycle, primary controls, app shell state, status text |
| Microphone input | `features/microphone-text-input.md` | Recording flow, microphone permission, audio capture, empty capture behavior |
| OpenAI transcription | `features/openai-transcription.md` | Transcription request/response behavior, model settings, timeout/error policy |
| Text handoff | `features/text-output-workflow.md` | Clipboard, paste, insertion, accepted transcript behavior |
| Permissions/privacy | `features/privacy-and-permissions.md` | Consent, permission gates, setup blocking, privacy boundaries |
| Settings/secrets | `features/settings-and-secret-storage.md` | Settings UI, persistence, Keychain, API key setup |
| Global hotkey | `features/global-hotkey.md` | Shortcut registration, conflict handling, shortcut settings |
| Floating indicator | `features/floating-indicator.md` | Recording/transcribing indicator presentation and lifecycle |
| Post-processing actions | `features/post-transcription-actions.md` | Output intent, correction/translation dispatch after transcription |
| Text correction | `features/text-correction.md` | Correction prompt, correction toggle, corrected transcript behavior |
| Voice emoji commands | `features/voice-emoji-commands.md` | Built-in spoken emoji aliases, Dictionary placement, local emoji replacement |
| Transcript history | `features/transcript-history.md` | History storage, display, recovery, retention |
| Diagnostics | `features/diagnostics-and-crash-reports.md` | Logs, crash/diagnostic reports, operator-facing error evidence |
| Software updates | `features/software-updates.md` | Native macOS app update checks, prompts, release artifacts, appcast behavior |
| App Store distribution | `features/app-store-distribution.md` | macOS distribution channel decision, App Store viability, direct-download trust |
| Landing page hosting | `features/landing-page-hosting.md` | DigitalOcean App Platform static site, custom domain, GitHub Pages appcast coexistence |
| Landing page localization | `features/landing-page-localization.md` | Supported languages, locale routes, switching, detection, RTL, localized metadata |
| UI functionality coverage | `features/ui-functionality-coverage.md` | Current UI/task coverage inventory, visible-surface task mapping |
| Platform testing | `features/platform-testing-strategy.md` | Choosing build/test/runtime QA, MCP, Computer Use, or manual evidence |
| Verification | `features/verification-strategy.md` | Verification baseline, test scope, evidence quality |
| Backlog grooming | `features/backlog-grooming-automation.md` | Backlog task creation/refinement behavior |
| Blocked tasks | `features/blocked-task-resolution-automation.md` | Blocked-task resolver behavior and resolution contracts |
| Automation recovery | `features/automation-prompt-recovery.md` | Installed automation/runbook recovery behavior |
| iOS feasibility evidence (historical) | `features/ios-keyboard-feasibility.md` | Earlier launch/microphone findings; current signed-device background-session gate is in the V1.1 release contract and `docs/ios-keyboard-dictation-mvp-plan.md` |
| iOS keyboard UX | `features/ios-keyboard-experience.md` | Active Brand Stage Adaptive composition, editing controls, voice/error-area presentation, Latest fallback, accessibility, and appearance; use the handoff spec for microphone behavior and recovery routing |
| iOS shared state (legacy) | `features/ios-keyboard-shared-state.md` | Historical Phase-0 App Group and automatic-delivery evidence; current snapshot is in the V1.1 release contract |
| iOS containing app (legacy) | `features/ios-containing-app-experience.md` | Historical expanded iPhone/iPad, Quick Session, and navigation contract; current scope is in V1.1 |
| iOS settings/secrets | `features/ios-settings-and-secret-storage.md` | iOS defaults, persistence, migrations, Keychain, truthful setup status |
| iOS voice/audio reference | `features/ios-voice-session-and-audio.md` | Foreground recorder and audio invariants; keyboard-originated launch and request lifecycle are governed by the handoff spec |
| iOS history/storage (legacy) | `features/ios-history-and-storage.md` | Historical P5H durable History, failed retry, pending journal, and recording-cache decisions; not current V1.1 scope |
| iOS privacy (legacy) | `features/ios-privacy-and-permissions.md` | Historical Quick Session and disclosure contract; use V1.1 plus the keyboard handoff spec for current permission and App Group behavior |
| iOS provider consent (legacy schema) | `features/ios-provider-consent-record.md` | Historical strict schema; V1.1 keeps provider-stage authorization in one standalone record |
| iOS diagnostics | `features/ios-diagnostics.md` | Redacted runtime events, app-owned diagnostics, explicit local export |
| iOS keyboard settings (deferred) | `features/ios-keyboard-settings-snapshot.md` | Historical typing-preference snapshot; V1.1 Brand Stage uses bundled presentation defaults |
| iOS output actions (legacy) | `features/ios-output-actions.md` | Historical insertion and acknowledgement evidence; current keyboard delivery is governed by the handoff spec |
| iOS accepted output delivery (legacy) | `features/ios-accepted-output-delivery-record.md` | Historical capability train; use V1.1 compact Pending, Latest, and History instead |
| iOS accepted History foundation (deferred) | `features/ios-accepted-history-foundation.md` | Historical app-private policy, accepted-row, outbox, and generation-cutover contract; do not continue for V1.1 |
| iOS failed History and retry audio (deferred) | `features/ios-failed-history-and-retry-audio.md` | Historical failed-row and retry-audio contract; explicitly excluded from V1.1 |
| iOS usage estimate | `features/ios-usage-estimate.md` | Local successful-transcription estimate, 30-day summary/chart, pricing gaps, Reset |

## Source Hints

- App shell and menu bar: `HoldType/HoldTypeApp.swift`,
  `HoldType/MenuBarView.swift`, `HoldType/MenuBarPresentation.swift`.
- Settings: `HoldType/SettingsView.swift`, `HoldType/Settings/`,
  `HoldType/Models/AppSettings.swift`.
- Runtime and recording: `HoldType/Services/DictationRuntime.swift`,
  `HoldType/Services/DictationSessionController*.swift`,
  `HoldType/Services/AudioRecorderService.swift`.
- OpenAI services: `HoldType/Services/OpenAI*Service.swift`,
  `HoldType/Services/OpenAITranscriptionRequestBuilder.swift`.
- Permissions and setup: `HoldType/Services/PermissionsService.swift`,
  `HoldType/Services/AppSetupController.swift`,
  `HoldType/Services/RecordingSetupPreflight.swift`.
- Text insertion and history: `HoldType/Services/TextInsertionService.swift`,
  `HoldType/Services/Transcript*Store.swift`, `HoldType/TranscriptHistoryView.swift`.
- Tests: start with `HoldTypeTests/*<area>*Tests.swift`, then search by type or
  service name.
