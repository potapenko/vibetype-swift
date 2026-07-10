# Spec Index

Use this file to choose the smallest product spec slice for a task. Read the
matching feature spec, then verify exact source ownership with `rg --files`.

| Area | Spec | Read When |
| --- | --- | --- |
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
| iOS feasibility | `features/ios-keyboard-feasibility.md` | Platform boundary, device spike, go/no-go gate, containing-app/extension split |
| iOS keyboard UX | `features/ios-keyboard-experience.md` | Typing parity, voice states, insertion safety, iPhone/iPad behavior |
| iOS shared state | `features/ios-keyboard-shared-state.md` | App Group record, expiry, privacy boundary, insertion eligibility |
| iOS containing app | `features/ios-containing-app-experience.md` | iPhone/iPad navigation, setup, Voice, Library, History, Settings, practice flow |
| iOS settings/secrets | `features/ios-settings-and-secret-storage.md` | iOS defaults, persistence, migrations, Keychain, truthful setup status |
| iOS voice/audio | `features/ios-voice-session-and-audio.md` | Foreground recording, Quick Session, audio lifecycle, journaling, M0C |
| iOS history/storage | `features/ios-history-and-storage.md` | Durable local history, failed retry, pending journal, recording cache |
| iOS privacy | `features/ios-privacy-and-permissions.md` | Microphone, provider and Quick Session consent, Full Access, privacy manifests |
| iOS diagnostics | `features/ios-diagnostics.md` | Redacted runtime events, app-owned diagnostics, explicit local export |
| iOS keyboard settings | `features/ios-keyboard-settings-snapshot.md` | One-way non-secret preference snapshot, fallback, M0B read gate |
| iOS output actions | `features/ios-output-actions.md` | Latest result, Copy/Share, insertion eligibility, acknowledgement, recovery |
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
