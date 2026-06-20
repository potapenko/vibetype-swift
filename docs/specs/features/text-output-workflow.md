# Text Output Workflow

## Goal

Define how generated text becomes useful after a microphone transcription
session.

The MVP is optimized for fast dictation into the currently active macOS app,
with copy-to-clipboard fallback when direct insertion is unavailable or
disabled.

## Scope

This spec covers:

- last transcript visibility
- output handoff actions
- auto-paste behavior
- copy-to-clipboard fallback
- clipboard restoration behavior
- failure behavior around output delivery

## Non-goals

- final editor UI design
- rich formatting, templates, or command language
- review-first editing workflow
- integration with a specific host application beyond active-app paste
- custom keyboard extension behavior

## User-visible behavior

- A successful transcription must be visible as the last transcript in the menu
  bar UI or settings surface.
- The menu must provide a Copy Last Transcript action.
- If `autoPaste` is enabled and Accessibility permission is available, the app
  should insert the transcript into the current active app at the cursor.
- MVP auto-paste uses the clipboard plus simulated Cmd+V.
- If `autoPaste` is disabled and `copyToClipboard` is enabled, the transcript
  should be copied to clipboard.
- If Accessibility permission is missing, auto-paste should fall back to copy
  to clipboard and show a clear status or error.
- If `restorePreviousClipboard` is enabled, the app may restore the prior
  clipboard after a short delay.
- If output delivery fails, the last transcript should remain visible or
  recoverable in the current session.

## Invariants

- Auto-paste must target the current active app at the cursor, not an internal
  hidden destination.
- Failed handoff must not discard the transcript.
- Copy and paste actions must not log transcript content by default.
- Clipboard, accessibility, or host-app automation must be treated as
  user-visible behavior, not hidden implementation detail.
- Auto-paste must have a settings-controlled off switch.

## Edge cases and failure policy

- If transcription output is empty, the app should show a clear error instead
  of copying or pasting empty text as a successful result.
- If the clipboard or host app is unavailable, the app should show a recoverable
  output error.
- If the previous clipboard cannot be restored, the app should not hide that
  failure when restore behavior was enabled.
- If the active app changes between recording start and paste time, the paste
  should follow the product's current-active-app rule unless a future spec pins
  the target at recording start.

## Route / state / data implications

- The app stores the last transcript in current app state and may expose it in
  the menu or settings.
- Output handoff may require platform permissions such as clipboard access,
  accessibility control, or keyboard event simulation.
- Persistent drafts or history require a separate storage spec.

## Verification mapping

- Add tests or manual QA for successful paste, copy-only mode, missing
  Accessibility fallback, empty output, clipboard restoration, and handoff
  failure when implementation exists.

## Unknowns requiring confirmation

- Whether `autoPaste` should default to on or off.
- Whether `copyToClipboard` should always happen even when auto-paste succeeds.
- Exact delay and failure behavior for restoring the previous clipboard.
- Whether the app needs command phrases for punctuation, formatting, or editing.
- Whether target app should be captured at recording start or paste time.
