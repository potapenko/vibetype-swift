# Text Output Workflow

## Goal

Define how generated text becomes useful after a microphone transcription
session.

The MVP is optimized for fast dictation that inserts successful transcripts
into the active macOS app automatically. An app-owned VibeType Clipboard keeps
the last accepted transcript recoverable on demand.

## Scope

This spec covers:

- last transcript visibility
- relationship to optional transcript history
- output handoff actions
- automatic active-app insertion
- VibeType Clipboard save behavior
- VibeType Clipboard paste shortcut
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
- Last Transcript and Save Last Transcript must use text after trimming leading
  and trailing whitespace and newlines.
- The menu may show a compact preview for long transcripts, but Save Last
  Transcript must still save the full normalized transcript text.
- Before any successful transcription exists, the menu must show a clear
  empty-state placeholder instead of hiding the Last Transcript area.
- The menu may provide a Save Last Transcript to VibeType Clipboard action.
- Save Last Transcript must be disabled or safely no-op when no non-empty last
  transcript is available.
- If automatic insertion is enabled, every accepted transcript should be
  inserted into the current active app at the cursor after transcription
  succeeds.
- Automatic insertion must use the same native, Accessibility-gated
  text-insertion boundary as the recovery paste path. It must not depend on
  Electron, Node.js, AppleScript paste helpers, or a macOS system clipboard
  fallback.
- If `saveTranscriptsToAppClipboard` is enabled, every accepted transcript is
  saved to the VibeType Clipboard after transcription succeeds and before the
  automatic insertion attempt completes, so a failed insertion remains
  recoverable.
- The VibeType Clipboard is app-owned current-session state. It is not the
  macOS system clipboard and must not overwrite `NSPasteboard.general`.
- `Control+Command+V` should insert the current VibeType Clipboard text into
  the current active app at the cursor when the setting is enabled.
- Turning `saveTranscriptsToAppClipboard` off disables new transcript saves and
  disables the VibeType Clipboard paste shortcut. It does not disable automatic
  insertion.
- Turning automatic insertion off must leave VibeType Clipboard recovery
  available when `saveTranscriptsToAppClipboard` is enabled.
- If Accessibility permission is missing, automatic insertion and
  `Control+Command+V` must not simulate text insertion into the active app and
  must not fall back to the macOS system clipboard.
- If the automatic insertion or recovery paste event fails or times out, the
  transcript should remain in the VibeType Clipboard when that setting is
  enabled and the app should show a recoverable output status when a visible
  surface is available.
- If output delivery fails, the last transcript should remain visible or
  recoverable in the current session.
- Last Transcript is current-session state and does not require persistent
  transcript history to be enabled.
- Optional transcript recovery history is governed by `transcript-history.md`.
  Enabling history must not change the VibeType Clipboard save or paste
  behavior for the current transcript.

## Invariants

- Automatic insertion and VibeType Clipboard paste must target the current
  active app at the cursor, not an internal hidden destination.
- Failed handoff must not discard the transcript.
- Copy and paste actions must not log transcript content by default.
- Clipboard, accessibility, or host-app automation must be treated as
  user-visible behavior, not hidden implementation detail.
- Automatic insertion and VibeType Clipboard save/paste must each have a
  settings-controlled off switch.
- The app must not use the macOS system clipboard as transcript storage,
  fallback storage, or restoreable state for this workflow.

## Edge cases and failure policy

- If transcription output is empty or whitespace-only after trimming, the app
  should show a clear error instead of saving or pasting empty text as a
  successful result.
- If the VibeType Clipboard is empty, the paste shortcut should safely no-op and
  report that no app clipboard text is available when a visible surface is
  available.
- If the host app is unavailable or text insertion fails, the app should show a
  recoverable output error when a visible surface is available and preserve the
  VibeType Clipboard recovery value when enabled.
- Paste delays and event posting must be bounded.
- If the active app changes between recording start and insertion time,
  automatic insertion and recovery paste should follow the product's
  current-active-app rule unless a future spec pins the target at recording
  start.

## Route / state / data implications

- The app stores the last transcript in current app state and may expose it in
  the menu or settings.
- The app may store one VibeType Clipboard text value in memory for the current
  app session when the setting is enabled.
- Automatic insertion is a local UserDefaults-backed behavior setting and
  defaults on for the MVP.
- If transcript recovery history is enabled, accepted transcripts may also be
  kept in session-only recovery history under `transcript-history.md`.
- Output handoff may require platform permissions such as Accessibility control
  or keyboard event simulation.
- Persistent drafts outside transcript history require a separate storage spec.

## Verification mapping

- Add tests or manual QA for automatic insertion success, VibeType Clipboard
  save, disabled setting behavior, successful `Control+Command+V` paste,
  missing Accessibility behavior, empty output, and handoff failure when
  implementation exists.

## Unknowns requiring confirmation

- Whether the app needs command phrases for punctuation, formatting, or editing.
- Whether target app should be captured at recording start or paste time.
