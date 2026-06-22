# Privacy And Permissions

## Goal

Define the first privacy and permission contract for a microphone-based text
input app.

VibeType handles spoken work content and sends audio to OpenAI for
transcription, so the product must make microphone capture, remote processing,
Keychain storage, and any transcript persistence explicit.

## Scope

This spec covers:

- microphone consent
- Accessibility consent for active-app paste automation
- Input Monitoring consent when native global-hotkey listening requires it
- recording visibility
- OpenAI remote-service disclosure
- local persistence defaults
- debug logging boundaries
- user content handling before a dedicated storage spec exists

## Non-goals

- legal privacy-policy wording
- account, billing, or team administration
- concrete encryption implementation details
- provider-specific API contracts
- microphone device selection or system-audio capture settings
- persistent raw-audio retention controls

## User-visible behavior

- The app must request microphone permission through the platform's normal
  permission flow before recording.
- The app must explain Accessibility permission when automatic insertion or
  VibeType Clipboard paste requires keyboard event simulation or control of the
  active app.
- The app must explain Input Monitoring permission when the native global
  hotkey implementation listens for key presses outside VibeType.
- The app must not imply that recording is active unless microphone capture has
  actually started.
- The product must disclose that audio is sent to OpenAI when OpenAI
  transcription is used.
- Settings must include a concise OpenAI audio-processing disclosure near the
  relevant transcription or privacy controls.
- API keys must be stored locally in macOS Keychain, not in UserDefaults or
  plain text files.
- The MVP must not require accounts, subscriptions, telemetry, analytics,
  server-side state, or cloud sync.
- The default product contract is no retained audio. Transcript recovery
  history is session-only, local-only, enabled by default, and governed by
  `transcript-history.md`.
- Debug logging must not include raw dictated text, raw audio payloads, tokens,
  credentials, or full provider responses in the default product log stream.
- If a user denies microphone permission, the app should remain usable enough
  to explain what is blocked and how to retry.
- The menu bar must surface microphone permission state before recording starts.
  Missing or denied microphone permission must block recording and show the
  shortest available next action, such as requesting access or opening the
  Microphone pane in System Settings.
- Settings should show microphone, Accessibility, and Input Monitoring status
  using product language and provide a bounded next action such as requesting
  permission or opening the relevant System Settings pane.
- Microphone permission state must be represented as one of four product
  states:
  - `allowed`: recording may start after an explicit user action.
  - `denied`: recording is blocked until the user changes system permission.
  - `not determined`: the app may request permission through the platform flow.
  - `unavailable`: recording is blocked because audio input is not available.
- Querying microphone permission must not start recording or create an audio
  file.
- The production microphone request flow should use the platform callback
  rather than polling. Automated verification should use a fake permission
  boundary instead of requiring a real system prompt.
- Accessibility permission state must be represented as one of two product
  states:
  - `trusted`: automatic insertion and VibeType Clipboard paste may control the
    active app.
  - `not trusted`: automatic insertion and VibeType Clipboard paste must not
    simulate insertion into the active app.
- Querying Accessibility permission must use the non-prompting status check by
  default. The app may provide a separate action to open the Accessibility pane
  in System Settings.
- Input Monitoring permission state must be represented as one of three product
  states:
  - `allowed`: native global hotkey listening may observe the needed key
    events outside VibeType.
  - `denied`: native global hotkey listening may be blocked until the user
    changes system permission.
  - `not determined`: the app may request permission through the platform flow.
- The MVP settings surface must not expose analytics, cloud-backup, local-model
  management, system-audio capture, or persistent raw-audio retention controls
  copied from the reference app.

## Invariants

- No microphone capture without explicit user action and permission.
- No hidden background recording.
- No remote provider other than OpenAI without a product-level decision and
  user-visible disclosure.
- No persistent audio without an explicit spec.
- Default logs must be short, scannable, and free of sensitive dictated content.
- API keys must never be logged.

## Edge cases and failure policy

- If permission is denied or restricted by device policy, the app should show a
  recoverable blocked state instead of repeatedly prompting.
- If Accessibility permission is not trusted, the app should explain that
  automatic insertion and VibeType Clipboard paste are blocked and provide a
  way to open the relevant System Settings pane when possible.
- If Accessibility permission is not trusted, transcription itself should remain
  available when other requirements are met. The app must not fall back to the
  macOS system clipboard.
- If OpenAI is unavailable, the app should fail the current
  attempt with a visible error and allow a later retry.
- If debug logging is temporarily enabled for investigation, the developer
  should turn it back off after verification.
- If a crash or interruption happens during recording, the app must not retain
  audio as an undocumented recovery artifact.
- If Accessibility permission is denied, automatic insertion and VibeType
  Clipboard paste should show a clear status or error when a visible surface is
  available.
- If Input Monitoring permission is denied, the app should explain that global
  dictation hotkey listening may be blocked and provide a way to open the
  relevant System Settings pane when possible.

## Route / state / data implications

- Permission state is part of the product state model and must be visible to
  flows that start recording.
- Accessibility trust state is part of the product state model and must be
  visible to flows that decide whether automatic insertion or VibeType
  Clipboard paste can insert text into the active app.
- Input Monitoring state is part of the product state model for native global
  hotkey flows that need to listen for keyboard events outside the app.
- Provider configuration is product behavior because it changes model,
  language, prompt, latency, and error behavior.
- Settings may be stored in UserDefaults, but the API key belongs in Keychain.
- Local storage of audio needs separate spec coverage before implementation.
  Transcript recovery history storage is governed by `transcript-history.md`.

## Verification mapping

- Add permission-state tests or manual QA for first launch, denied permission,
  permission granted after denial, and unavailable microphone when implementation
  exists.
- Add tests or review checks that default logs do not include raw dictated
  content.

## Unknowns requiring confirmation

- Whether the app needs a formal onboarding screen before first recording.
- Whether temporary debug audio retention is allowed in debug builds.
- Exact wording and placement for OpenAI audio-processing disclosure.
