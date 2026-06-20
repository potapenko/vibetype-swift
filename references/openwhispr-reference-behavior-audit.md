# OpenWhispr Reference Behavior Audit

Status: completed for `VT-006`.

This audit records behavior evidence from the copied OpenWhispr source that can
inform the native Swift MVP. It is not an architecture guide. VibeType must keep
native Swift service boundaries and must not port Electron, React, Node.js,
local models, accounts, billing, cloud sync, notes, meetings, telemetry, or
updater systems.

## Source Slices Inspected

- `references/openwhispr-main/CLAUDE.md`
- `references/openwhispr-main/main.js`
- `references/openwhispr-main/src/hooks/useAudioRecording.js`
- `references/openwhispr-main/src/hooks/usePermissions.ts`
- `references/openwhispr-main/src/hooks/useHotkey.js`
- `references/openwhispr-main/src/hooks/useHotkeyRegistration.ts`
- `references/openwhispr-main/src/hooks/useHotkeyModeInfo.ts`
- `references/openwhispr-main/src/helpers/audioManager.js`
- `references/openwhispr-main/src/helpers/clipboard.js`
- `references/openwhispr-main/src/helpers/hotkeyManager.js`
- `references/openwhispr-main/src/helpers/tray.js`
- `references/openwhispr-main/src/stores/settingsStore.ts`
- `references/openwhispr-main/src/utils/hotkeys.ts`
- `references/openwhispr-main/src/utils/recordingErrors.ts`
- `references/openwhispr-main/src/App.jsx`
- `references/openwhispr-main/src/components/ui/PermissionsSection.tsx`
- `references/openwhispr-main/resources/macos-fast-paste.swift`
- `references/openwhispr-main/resources/macos-globe-listener.swift`
- `references/openwhispr-main/resources/macos-mic-listener.swift`

## Useful MVP Behavior

### Hotkey Activation

- OpenWhispr separates persisted hotkey value, display formatting, registration,
  and native key event delivery. The Swift MVP should keep the same separation:
  settings store, user-facing label, `GlobalHotkeyService`, and controller
  actions. Evidence: `src/hooks/useHotkey.js:4-11`,
  `src/utils/hotkeys.ts:56-145`,
  `src/hooks/useHotkeyRegistration.ts:94-193`.
- Registration failure is user-visible and non-destructive. OpenWhispr validates
  the requested shortcut, reports registration errors, suggests alternatives,
  and restores the previous working shortcut after failure. The Swift hotkey
  service should keep the previous registered hotkey active if a replacement
  fails. Evidence: `src/helpers/hotkeyManager.js:128-168`,
  `src/helpers/hotkeyManager.js:407-451`,
  `src/helpers/hotkeyManager.js:486-510`.
- Push-to-talk needs key-down/key-up events, not only a global shortcut toggle.
  OpenWhispr uses dedicated native listeners for macOS Fn/Globe and right-side
  modifiers, with a minimum hold duration and a short post-stop cooldown. The
  Swift MVP should preserve the race prevention idea even if the default key
  remains the VibeType spec default. Evidence: `main.js:1026-1118`,
  `resources/macos-globe-listener.swift:94-123`.
- Temporary hotkeys must be cleaned up on app quit. Evidence:
  `main.js:1660-1679`.

### Recording Lifecycle

- Start and stop are guarded by independent locks and current-state checks so
  repeated hotkey events do not create parallel recordings or duplicate stop
  work. The Swift controller should keep this invariant. Evidence:
  `src/hooks/useAudioRecording.js:19-31`,
  `src/hooks/useAudioRecording.js:60-85`,
  `src/helpers/audioManager.js:370-378`.
- Recording transitions to processing immediately after stop, before
  transcription begins, and returns to idle after success or failure. Evidence:
  `src/helpers/audioManager.js:438-470`,
  `src/helpers/audioManager.js:730-735`.
- Empty transcription or detected silence is not treated as successful dictated
  text. OpenWhispr shows a no-audio path and does not overwrite useful state
  with empty output. Evidence: `src/hooks/useAudioRecording.js:125-136`,
  `src/helpers/audioManager.js:591-620`.
- Cancellation is a first-class action while recording or processing. The Swift
  MVP should keep cancel semantics separate from failure semantics. Evidence:
  `src/hooks/useAudioRecording.js:272-291`,
  `src/helpers/audioManager.js:544-589`.

### Paste And Clipboard Handoff

- Paste starts by writing the transcript to the clipboard, then attempts the
  automatic paste, and falls back to "copied, paste manually" when Accessibility
  trust or the paste command fails. Evidence:
  `src/helpers/clipboard.js:673-725`,
  `src/helpers/clipboard.js:820-883`.
- Clipboard restore is delayed and optional. OpenWhispr preserves image, HTML,
  and text clipboard payloads; current VibeType scope only promises plain text,
  but future rich-clipboard work can use this as evidence. Evidence:
  `src/helpers/clipboard.js:612-632`,
  `src/helpers/clipboard.js:786-790`.
- macOS fast paste is just Cmd+V via `CGEvent` after an Accessibility trust
  check. The Swift app can implement this natively without spawning helper
  binaries. Evidence: `resources/macos-fast-paste.swift:3-17`.
- Paste operations have bounded timeouts and return fallback messages instead
  of hanging indefinitely. Evidence: `src/helpers/clipboard.js:824-831`,
  `src/helpers/clipboard.js:873-883`.

### Permissions

- Permission state should be revalidated from the platform on mount rather than
  trusting persisted UI state. Evidence: `src/hooks/usePermissions.ts:277-293`.
- The app should open the relevant System Settings pane instead of relying on an
  intrusive Accessibility prompt. Evidence:
  `src/hooks/usePermissions.ts:242-256`.
- Accessibility grant polling can be short and bounded, with troubleshooting
  copy after repeated unsuccessful checks. Evidence:
  `src/hooks/usePermissions.ts:295-320`.
- The permission UI separates Microphone and Accessibility, and treats
  Accessibility as recommended for macOS auto-paste rather than required for
  manual copy fallback. Evidence:
  `src/components/ui/PermissionsSection.tsx:23-50`,
  `src/components/ui/PermissionsSection.tsx:65-70`.

### Settings

- Useful MVP settings from OpenWhispr are: transcription language, cloud model,
  hotkey, activation mode, preferred microphone, audio cues, floating indicator
  visibility, auto-paste, and whether the transcript stays in clipboard.
  Evidence: `src/stores/settingsStore.ts:761-841`,
  `src/stores/settingsStore.ts:860-914`.
- Secrets are not hydrated from local storage in the renderer. For VibeType,
  this reinforces the current Keychain-only API-key boundary. Evidence:
  `src/stores/settingsStore.ts:803-814`.

### UI States

- The dictation surface has distinct idle, recording, and processing states,
  with recording/processing cancel actions and a tooltip showing the current
  hotkey when idle. Evidence: `src/App.jsx:278-318`,
  `src/App.jsx:345-456`.
- The floating surface can become non-interactive when idle and auto-hide after
  recording/processing finishes. This is useful for the VibeType floating
  indicator spec, but it should be implemented natively rather than with an
  Electron window. Evidence: `src/App.jsx:98-105`,
  `src/App.jsx:222-237`.
- The tray/menu surface opens settings/control panel and quit, but OpenWhispr's
  tray menu is not the same as VibeType's smaller menu-bar MVP. Evidence:
  `src/helpers/tray.js:230-270`.

### Native macOS Helpers

- `macos-globe-listener.swift` is useful evidence for key-down/key-up lifecycle
  and right-side modifier detection, but not a source file to port directly.
  Evidence: `resources/macos-globe-listener.swift:94-123`.
- `macos-mic-listener.swift` monitors other apps' microphone usage through
  CoreAudio property listeners. That belongs to OpenWhispr meeting detection,
  not the VibeType MVP recording path. Evidence:
  `resources/macos-mic-listener.swift:1-8`,
  `resources/macos-mic-listener.swift:211-296`.

## Explicitly Rejected Scope

- Electron windows, IPC/preload bridge, React state, Tailwind, and Node helper
  processes.
- Local Whisper, Parakeet, model downloads, streaming providers, VAD tuning,
  dictionary learning, snippets, reasoning cleanup, agents, notes, semantic
  search, Qdrant, meetings, calendar, accounts, billing, OAuth, cloud sync,
  usage limits, update checks, and telemetry.
- Cross-platform Linux/Windows paste and hotkey infrastructure. VibeType is a
  native macOS MVP first.
- SQLite transcription history and failed-recording retention until a VibeType
  transcript-history spec explicitly requires them.

## Follow-Up Tasks

No new backlog tasks were created in this audit. The selected evidence maps to
existing VibeType areas already represented in the backlog: hotkey service,
recording, clipboard/paste, permissions, settings, floating indicator, and
reference sub-audits.
