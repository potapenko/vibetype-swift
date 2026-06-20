# Floating Indicator

## Goal

Define the optional floating status surface for VibeType recording and
transcription sessions.

The indicator gives the user immediate confidence that the menu bar app is
recording or processing while keeping the currently active app focused.

## Scope

This spec covers:

- indicator visibility across recording, transcribing, done, and error states
- default placement and display duration
- non-interference with the active app
- behavior when the floating indicator setting is disabled
- fallback behavior when the indicator cannot be shown

## Non-goals

- final visual styling
- implementation details for `NSPanel`, `NSWindow`, or SwiftUI view structure
- transcript editing, history, or review workflows
- notification-center behavior

## User-visible behavior

- The floating indicator is enabled by default through the
  `showFloatingIndicator` setting.
- When enabled, it appears while a session is recording.
- While recording, the indicator uses short recording copy such as
  `Recording`.
- After recording stops and transcription is in progress, the indicator stays
  visible and changes to short processing copy such as `Transcribing`.
- A successful session may show a brief done state such as `Done` after output
  handoff completes.
- The done state should dismiss automatically after about two seconds.
- A failed session may show a brief product-language error summary.
- The error indicator should dismiss automatically after about six seconds or
  when a new session starts, while the durable error remains available in the
  menu or settings surface.
- The indicator should not show the full transcript by default.
- The default placement is near the top center of the active display, below the
  macOS menu bar and inside the visible screen area.
- The indicator may adjust placement to stay on screen and avoid covering
  system UI.
- If `showFloatingIndicator` is disabled, no floating indicator should appear
  for recording, transcribing, done, or error states.
- Disabling the indicator must not disable menu status, recording,
  transcription, clipboard, or paste behavior.

## Invariants

- The floating indicator must not steal focus.
- The floating indicator must not make VibeType the active app during normal
  recording, transcribing, done, or error display.
- The floating indicator must not intercept keyboard input meant for the active
  app.
- The floating indicator must not be the only place where an error is exposed.
- Core menu bar controls must remain usable if the indicator is hidden,
  disabled, or fails to appear.
- The indicator must not display API keys, raw audio paths, provider payloads,
  or verbose debug details.

## Edge cases and failure policy

- If recording starts again before a prior done or error indicator dismisses,
  the indicator should switch immediately to the new recording state.
- If transcription starts after recording stops, the indicator should update in
  place rather than flashing through idle.
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

- `idle`: hidden
- `recording`: visible with recording copy when enabled
- `transcribing`: visible with processing copy when enabled
- `done`: brief visible confirmation when enabled, then hidden
- `error`: brief visible summary when enabled, then hidden with durable error
  surfaced elsewhere

The `showFloatingIndicator` setting is local UserDefaults-backed app state.

## Verification mapping

- Unit or model coverage should verify state-to-indicator visibility decisions
  once an indicator model exists.
- macOS runtime smoke should verify that the indicator appears for recording or
  transcribing and does not steal focus once the platform surface exists.
- Build or runtime verification should confirm that disabling the setting hides
  the indicator without disabling menu status or session behavior.

## Unknowns requiring confirmation

- Final visual style, size, and iconography.
- Whether the user can drag or reposition the indicator.
- Whether success and error durations should be user-configurable.
