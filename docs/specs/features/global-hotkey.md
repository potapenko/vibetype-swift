# Global Hotkey

## Goal

Define how HoldType starts and stops dictation from a macOS-wide shortcut
without allowing hidden recording or parallel recording sessions.

## Scope

This spec covers:

- default dictation shortcut
- hold-to-record behavior
- repeated key events and race prevention
- shortcut registration failure and collision behavior
- menu and Settings display for the active shortcut
- app clipboard paste shortcut
- post-transcription output intent for the translation shortcut
- immediate Fixes palette shortcut

## Non-goals

- final shortcut customization UI
- multiple named hotkey slots
- Electron, React, Node.js, or cross-platform shortcut architecture
- voice-agent, meeting, notes, or local-model hotkeys

## User-visible behavior

- The MVP default dictation shortcut is `Right Command` as a single-key
  hold-to-record shortcut.
- The current MVP has no automatic alternate shortcut or toggle-mode fallback.
- The app must not use `Command+Space` as the default because that commonly
  belongs to Spotlight.
- The app must not use `Option+Space` or `Control+Space` as the default
  dictation shortcut.
- The native macOS implementation must observe both key down and key up
  reliably before it reports the shortcut as registered.
- The native implementation must distinguish `Right Command` from generic
  Command before presenting it as the active shortcut.
- In hold-to-record mode:
  - key down starts one recording session when the app is idle and microphone
    permission is available;
  - key up stops that same recording session and starts transcription;
  - if key up arrives while the key-down start action is still completing, the
    release must be remembered and stop that recording as soon as start
    succeeds;
  - key repeat or a second key down while the key is already held must be
    ignored.
- If reliable key-up handling is unavailable, registration is unavailable and
  the manual menu controls remain usable. HoldType does not silently change the
  interaction to toggle mode.
- While transcription is running, the shortcut must not start another recording.
  The menu and any indicator should show the transcribing state instead.
- If the shortcut is unavailable at launch because registration fails or the
  key combination is already owned by the system or another app, HoldType must
  keep menu controls usable and show a clear hotkey-unavailable status.
- If no shortcut can be registered, Transcribe and Stop Recording from
  the menu remain the supported manual path.
- The Settings window should show the active shortcut and activation mode as
  read-only MVP information: `Right Command - Hold to record`.
- The menu should expose the active shortcut near the Transcribe action when
  practical.
- Full shortcut editing is deferred, but future editing must validate and
  register a candidate before persisting it.
- The Paste Last Result shortcut is `Control+Command+V`.
- `Control+Command+V` is not a dictation shortcut. It inserts the current Last
  Result text into the current active app when Keep last result is enabled.
- Turning Keep last result off must disable the `Control+Command+V` Paste Last
  Result behavior.
- If no Last Result is available, `Control+Command+V` should safely no-op and
  report that no last result is available when a visible surface is available.
- Paste Last Result should run after the shortcut is released, so the synthetic
  insertion event is not affected by still-held shortcut modifiers.
- Synthetic text insertion for Paste Last Result must clear keyboard modifier
  flags on the generated text events.
- Paste Last Result must not write transcript text to the macOS system
  clipboard.
- The immediate Fixes palette shortcut is `Option+J`.
- `Option+J` captures the current compatible external text target and opens the
  palette governed by `text-fixes.md`. It does not start recording or reuse the
  current-line behavior of another product.
- The shortcut must be suppressed from the target app only when HoldType has
  accepted the invocation. Failed or unavailable registration must not make
  ordinary `Option+J` typing disappear silently.
- If `Option+J` conflicts with another owner, HoldType keeps dictation and menu
  controls usable and reports only the Fixes shortcut as unavailable.
- When enabled in Settings, `Right Command+Option` may act as a hold-to-record
  dictation shortcut that requests configured translation after transcription
  under `post-transcription-actions.md`.
- `Right Command+Option` must not replace the normal `Right Command` dictation
  shortcut. It is a separate output intent for the current recording session.
- The translation intent must not depend on pressing the keys in one exact
  order. Pressing Option before `Right Command`, pressing Option at the same
  time as `Right Command`, or adding Option while an active `Right Command`
  hold-to-record session is starting or recording should all request
  translation for that session.
- Once Option has requested translation for the current `Right Command` session,
  releasing Option before `Right Command` must not downgrade that session back to
  normal dictation.
- If native dictation hotkey listening requires Input Monitoring permission,
  Settings must expose that permission state and a bounded next action.

## Invariants

- A shortcut action must never create parallel recordings.
- Recording can start only from an explicit user action and only when required
  microphone permission is available.
- Failed shortcut registration must not prevent manual menu recording.
- The app must not claim that the hotkey is active when registration is
  unavailable.
- Shortcut handling must not log dictated text, raw audio, API keys, or full
  provider responses.
- Fixes shortcut handling must capture the target before HoldType takes focus
  and must not log source text, prompts, or results.

## Edge cases and failure policy

- If key up arrives without a matching active hotkey-started recording, ignore
  it.
- If key up is remembered during an in-flight start action but that start later
  fails or is blocked by setup, discard the remembered stop and show only the
  start failure.
- If key down arrives while recording from the menu, ignore the shortcut or
  treat it as a no-op; do not attach the existing session to a new key token.
- If the app is recording and the shortcut service is stopped or loses its
  event stream, the app should fail or stop the current session visibly rather
  than continue hidden recording.
- If microphone permission is denied, a shortcut press should show the same
  blocked state as the menu start action and must not enter recording.
- Accessibility permission is not required to start recording. If it is missing
  after transcription, automatic insertion and Paste Last Result follow
  the recovery behavior defined by the text output workflow spec without using
  the macOS system clipboard.
- Input Monitoring permission may be required for native global hotkey
  listening, depending on the implementation path. Missing Input Monitoring
  must not imply hidden recording, open required Settings recovery by itself, or
  prevent menu-driven recording controls.
- If registration fails, Settings should show that no global hotkey is active.
- A Fixes registration failure does not downgrade, disable, or change the
  separate Right Command dictation registration.

## Route / state / data implications

The app state must distinguish:

- active shortcut value
- fixed hold-to-record activation mode
- shortcut registration status: registered or unavailable
- whether a hotkey press token currently owns the active recording session
- the output intent attached to the active hotkey-started recording session
- the independent `Option+J` Fixes registration status

The fixed shortcut is local runtime configuration. Until shortcut editing
exists, the app uses the spec-defined default and persists no custom hotkey
input.

## Verification mapping

- Spec-only changes require `git diff --check`.
- Native implementation should add fake-backed tests for hold-mode key down/up,
  repeat suppression, transcribing-state rejection, and registration failure.
- Runtime smoke is required only when a task changes the visible running app
  surface or actual macOS hotkey registration.

## Source evidence

- Product brief: `docs/openwhispr_swiftui_codex_tz.md`
- Existing specs: `microphone-text-input.md`, `menu-bar-app-shell.md`,
  `settings-and-secret-storage.md`, and `text-output-workflow.md`
- OpenWhispr reference behavior: hotkey registration and key down/up handling
  in `references/openwhispr-main/src/helpers/hotkeyManager.js`,
  `references/openwhispr-main/main.js`, and
  `references/openwhispr-main/src/stores/settingsStore.ts`
