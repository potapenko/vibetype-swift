# Menu Bar App Shell

## Goal

Define the first app-shell contract for VibeType as a small native macOS menu
bar dictation utility.

The app should be available from the menu bar, expose core dictation actions,
and show recording/transcribing status without requiring a full document-style
window.

## Scope

This spec covers:

- menu bar presence
- core menu items
- settings window entry point
- last transcript visibility
- basic recording/transcribing/done/error status
- floating indicator as an optional MVP polish surface

## Non-goals

- final visual design
- App Store packaging or notarization
- auto-updater behavior
- account, billing, cloud sync, or telemetry surfaces

## User-visible behavior

- The app should run as a macOS menu bar app.
- The menu bar status item should remain available while the app is running.
- The menu should include Start Recording or Stop Recording depending on the
  current state.
- Before recording exists, Start Recording may be a visible placeholder, but it
  must clearly state that recording is not available yet.
- The menu should include Settings, Last Transcript, Copy Last Transcript, and
  Quit.
- Quit must terminate the app cleanly.
- The app should show status changes during recording and transcription.
- Settings should be available from the menu bar.
- A floating indicator may be shown during recording and transcription when the
  setting is enabled.
- The floating indicator must not steal focus or interfere with the active app.
- Detailed floating indicator behavior is defined in
  `features/floating-indicator.md`.

## Invariants

- The app must not require Electron, React, Node.js, WebView UI, Tauri, or Rust
  for the first MVP.
- Menu state must reflect recording and transcribing state accurately.
- Errors must not be silent; they should be visible in menu status, settings, or
  an optional notification.
- No accounts, subscriptions, server-side app state, analytics, or telemetry are
  part of the MVP.

## Edge cases and failure policy

- If recording is already active, another Start Recording action must not create
  a parallel recording.
- If transcription is active, recording actions should be disabled or ignored in
  a way the user can understand.
- If settings cannot open, the app should show a clear recoverable error.
- If the floating indicator cannot be shown, core menu bar controls should
  still work.

## Route / state / data implications

Core visible states are:

- idle
- recording
- transcribing
- done
- error

Settings window state is separate from recording state. Opening or closing
settings must not start, stop, or cancel recording by itself.

## Verification mapping

- Add UI or manual app-run checks for menu presence, Start/Stop label changes,
  Settings opening, Last Transcript display, Copy Last Transcript, Quit, and
  state display when implementation exists.

## Unknowns requiring confirmation

- Final app name and menu bar label/icon.
