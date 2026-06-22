# Global Hotkey

## Goal

Define how VibeType starts and stops dictation from a macOS-wide shortcut
without allowing hidden recording or parallel recording sessions.

## Scope

This spec covers:

- default dictation shortcut
- hold-to-record and toggle-mode fallback behavior
- repeated key events and race prevention
- shortcut registration failure and collision behavior
- menu and Settings display for the active shortcut

## Non-goals

- final shortcut customization UI
- multiple named hotkey slots
- Electron, React, Node.js, or cross-platform shortcut architecture
- voice-agent, meeting, notes, or local-model hotkeys

## User-visible behavior

- The MVP default dictation shortcut is `Right Command` as a single-key
  hold-to-record shortcut.
- The alternate dictation shortcut option is `Globe/Fn` as a single-key
  hold-to-record shortcut for keyboards that expose that key.
- The app must not use `Command+Space` as the default because that commonly
  belongs to Spotlight.
- The app must not use `Option+Space` or `Control+Space` as the default
  dictation shortcut.
- The shortcut should use hold-to-record when the native macOS implementation
  can observe both key down and key up reliably.
- The MVP configuration prefers hold-to-record for both the default shortcut
  and the Globe/Fn alternate; toggle mode is only the fallback when the native
  event path cannot safely deliver key-up events.
- The native implementation must distinguish `Right Command` from generic
  Command before presenting it as the active shortcut.
- In hold-to-record mode:
  - key down starts one recording session when the app is idle and microphone
    permission is available;
  - key up stops that same recording session and starts transcription;
  - key repeat or a second key down while the key is already held must be
    ignored.
- If reliable key-up handling is not available for the MVP implementation, the
  app may fall back to toggle mode.
- In toggle mode:
  - the first shortcut press starts recording;
  - the next shortcut press stops recording and starts transcription;
  - key-up events do not stop recording;
  - repeated key-down events from the same physical press must not start and
    stop recording immediately.
- While transcription is running, the shortcut must not start another recording.
  The menu and any indicator should show the transcribing state instead.
- If the shortcut is unavailable at launch because registration fails or the
  key combination is already owned by the system or another app, VibeType must
  keep menu controls usable and show a clear hotkey-unavailable status.
- If the implementation supports a safe automatic fallback or alternate
  shortcut, the first candidate after `Right Command` is `Globe/Fn`; the active
  shortcut shown to the user must update to the fallback or alternate value.
- If no shortcut can be registered, Start Recording and Stop Recording from the
  menu remain the supported manual path.
- The Settings window should show the active shortcut and activation mode as
  read-only MVP information, such as `Right Command - Hold to record`,
  `Globe/Fn - Hold to record`, or `Right Command - Toggle`.
- The menu should expose the active shortcut near the Start Recording or Stop
  Recording action when practical.
- Full shortcut editing is deferred, but future editing must validate and
  register a candidate before persisting it.

## Invariants

- A shortcut action must never create parallel recordings.
- Recording can start only from an explicit user action and only when required
  microphone permission is available.
- Failed shortcut registration must not prevent manual menu recording.
- A failed shortcut change must leave the previous working shortcut active when
  one exists.
- The app must not claim that hold-to-record is active when it is actually
  using toggle mode.
- Shortcut handling must not log dictated text, raw audio, API keys, or full
  provider responses.

## Edge cases and failure policy

- If key up arrives without a matching active hotkey-started recording, ignore
  it.
- If key down arrives while recording from the menu, ignore the shortcut or
  treat it as a no-op; do not attach the existing session to a new key token.
- If the app is recording and the shortcut service is stopped or loses its
  event stream, the app should fail or stop the current session visibly rather
  than continue hidden recording.
- If microphone permission is denied, a shortcut press should show the same
  blocked state as the menu start action and must not enter recording.
- Accessibility permission is not required to start recording. If it is missing
  after transcription, output follows the copy-to-clipboard fallback defined by
  the text output workflow spec.
- If registration fails for both default and fallback shortcuts, Settings should
  show that no global hotkey is active.

## Route / state / data implications

The app state must distinguish:

- active shortcut value
- activation mode: hold or toggle
- shortcut registration status: registered, fallback-registered, unavailable
- whether a hotkey press token currently owns the active recording session

Shortcut configuration is local app setting data. Until shortcut editing exists,
the app may use the spec-defined default and fallback values without persisting
custom user input.

## Verification mapping

- Spec-only changes require `git diff --check`.
- Native implementation should add fake-backed tests for hold-mode key down/up,
  toggle-mode press handling, repeat suppression, transcribing-state rejection,
  registration failure, and fallback registration.
- Runtime smoke is required only when a task changes the visible running app
  surface or actual macOS hotkey registration.

## Source evidence

- Product brief: `docs/openwhispr_swiftui_codex_tz.md`
- Existing specs: `microphone-text-input.md`, `menu-bar-app-shell.md`,
  `settings-and-secret-storage.md`, and `text-output-workflow.md`
- OpenWhispr reference behavior: hotkey registration, tap/push activation
  modes, registration rollback, fallback suggestions, and key down/up handling
  in `references/openwhispr-main/src/helpers/hotkeyManager.js`,
  `references/openwhispr-main/main.js`, and
  `references/openwhispr-main/src/stores/settingsStore.ts`
