# Floating Indicator

## Goal

Define the optional floating recording surface for VibeType dictation sessions.

The indicator gives the user immediate confidence that the menu bar app is
recording while keeping the currently active app focused.

## Scope

This spec covers:

- indicator visibility during active microphone capture
- indicator visibility during transcription handoff
- default placement
- non-interference with the active app
- behavior when the floating indicator setting is disabled
- fallback behavior when the indicator cannot be shown

## Non-goals

- implementation details for `NSPanel`, `NSWindow`, or SwiftUI view structure
- transcript editing, history, or review workflows
- notification-center behavior

## User-visible behavior

- The floating indicator is enabled by default through the
  `showFloatingIndicator` setting.
- When enabled, it appears while a session is actively recording and may remain
  visible while the completed audio is being transcribed.
- While recording, the indicator is a compact cyan visual mark with subtle pulse
  animation.
- While transcribing, the indicator switches to a compact purple waiting visual
  with motion distinct from the recording state.
- When recording is cancelled, fails before capture, completes successfully, or
  fails after transcription starts, the indicator disappears immediately.
- The indicator should not show text by default.
- The indicator should not show the full transcript by default.
- The default placement is near the bottom-right corner of the active display,
  inside the visible screen area.
- The indicator may adjust placement to stay on screen and avoid covering
  system UI.
- If `showFloatingIndicator` is disabled, no floating indicator should appear
  during recording.
- Disabling the indicator must not disable menu status, recording,
  transcription, clipboard, or paste behavior.

## Invariants

- The floating indicator must not steal focus.
- The floating indicator must not make VibeType the active app during normal
  recording display.
- The floating indicator must not intercept keyboard input meant for the active
  app.
- Core menu bar controls must remain usable if the indicator is hidden,
  disabled, or fails to appear.
- The indicator must not display API keys, raw audio paths, provider payloads,
  or verbose debug details.

## Edge cases and failure policy

- If recording starts again quickly after a prior session, the indicator should
  appear for the new recording state without showing stale completion or error
  states.
- If transcription starts after recording stops, the indicator may switch to the
  transcribing visual without showing transcript content.
- If the active display changes during a session, the indicator may stay on the
  display where the session began or move to the current active display, as
  long as it remains visible and non-disruptive.
- If the indicator cannot be created or displayed, the app should continue the
  session and rely on menu status for visible feedback.
- If permission or setup blocks recording before capture starts, the indicator
  may stay hidden and the menu/settings error surface remains authoritative.

## Route / state / data implications

The indicator reflects existing app session state. It does not own recording,
transcription, paste, clipboard, settings, or permission state.

Product states map to the indicator as follows:

| App state | Indicator visibility | Display |
| --- | --- | --- |
| `idle` | hidden | none |
| `recording` | visible when enabled | compact cyan recording indicator |
| `transcribing` | visible when enabled | compact purple waiting indicator |
| `done` | hidden | none |
| `error` | hidden | none |

The `showFloatingIndicator` setting is local UserDefaults-backed app state.

## Verification mapping

- Unit or model coverage should verify state-to-indicator visibility decisions.
- macOS runtime smoke should verify that the indicator appears for recording
  and does not steal focus once the platform surface exists.
- Build or runtime verification should confirm that disabling the setting hides
  the indicator without disabling menu status or session behavior.

## Unknowns requiring confirmation

- Whether the user can drag or reposition the indicator.
