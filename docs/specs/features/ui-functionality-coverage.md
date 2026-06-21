# UI And Functionality Coverage

## Goal

Keep a durable map from the intended VibeType MVP surfaces and flows to current
Swift implementation, OpenWhispr behavior evidence, backlog tasks, and
verification.

This file prevents reference audits and grooming passes from treating blocked
or disconnected tasks as finished product coverage.

## Coverage Rules

- A surface or flow is `implemented` only when the relevant task is `done` and
  the Swift behavior exists in the current checkout.
- A surface or flow is `blocked` when its next product delta depends on a
  blocked task. The first unblock action must be named.
- A surface or flow is `planned` when the task exists but is not
  dependency-ready yet.
- Reference behavior is not considered covered merely because an old task file
  mentions it.
- When OpenWhispr evidence is used, preserve native Swift/AppKit boundaries and
  do not copy Electron, React, Node.js, account, billing, cloud sync,
  telemetry, local model, meeting, or updater behavior.

## Current Map

Snapshot date: 2026-06-22.

| Surface or flow | Current VibeType state | Reference evidence | Next backlog action | Verification |
| --- | --- | --- | --- | --- |
| Menu bar app shell | Visible menu bar app and Settings entry exist; Start/Stop is still a placeholder path in `vibetype/MenuBarView.swift`. `VT-150` closed the menu identity blocker, but `VT-010` still needs executable menu-surface evidence. | `references/openwhispr-main/src/helpers/tray.js`; `references/openwhispr-main/src/helpers/menuManager.js` | Run selector-ready `VT-158` to close out `VT-010`; then use controller slices to replace placeholder recording behavior. | macOS build plus bounded menu-bar runtime QA when visible menu behavior changes. |
| Settings surface | Native Settings window exists with API key, transcription fields, behavior toggles, permission/privacy copy, and Accessibility status; API key and toggle closeouts remain blocked, and `VT-153` recorded that transcription-field runtime inspection is still blocked. | `references/openwhispr-main/src/components/SettingsPage.tsx`; `TranscriptionModelPicker.tsx`; `ApiKeyInput.tsx`; `MicrophoneSettings.tsx` | Retry `VT-151`, `VT-152`, and the `VT-025` runtime inspection path when macOS UI-reading capability is available; run `VT-026` after `VT-157` closes `VT-071`. | Unit/build evidence for settings models; Computer Use QA for changed Settings controls when available. |
| Permission states | Microphone and Accessibility status handling exists in menu and Settings surfaces; `VT-031`, `VT-032`, `VT-033`, `VT-034`, and `VT-149` are complete. | `references/openwhispr-main/src/hooks/usePermissions.ts`; `references/openwhispr-main/src/components/ui/PermissionsSection.tsx` | Let the blocked-task resolver close `VT-030` after higher-priority blocked items, using `VT-149` as the completed product follow-up. | Fake-backed tests for permission states; bounded runtime QA only for visible permission UI changes. |
| Recording lifecycle | Recorder protocol and fake coverage exist, but there is no AVFoundation recording adapter wired into the user flow. `VT-154` is blocked on local Xcode test execution before `VT-041` can close. | `references/openwhispr-main/src/hooks/useAudioRecording.js`; `references/openwhispr-main/src/helpers/audioManager.js` | Retry `VT-154` after local tooling recovery can reach focused unit-test execution, then run `VT-042`, `VT-043`, `VT-044`, and `VT-045`. | Fake-backed tests for lifecycle states; bounded platform QA only when actual microphone capture changes. |
| OpenAI transcription | Request builder and URLSession client exist with fake-backed tests; controller integration is not present. `VT-155` and `VT-156` are blocked on local Xcode test execution. | `docs/openwhispr_swiftui_codex_tz.md`; current OpenAI transcription spec | Retry `VT-155` and `VT-156` after local tooling recovery can reach focused unit-test execution, then connect through controller success/failure tasks. | Fake URL loader tests, timeout tests, and no live OpenAI calls in automation. |
| Text output and paste | Clipboard copy/restore and Accessibility-gated paste primitives exist; last-transcript menu integration waits on transcript normalization. | `references/openwhispr-main/src/helpers/clipboard.js`; `references/openwhispr-main/resources/macos-fast-paste.swift` | Close `VT-054` through its blocker path, then run `VT-064` before controller success-output wiring. | Fake clipboard/paste tests; bounded active-app paste QA only when paste adapter changes. |
| Global hotkey | Shortcut model, activation-mode logic, protocol, and fake tests exist; real registration and controller handoff are not complete. | `references/openwhispr-main/src/helpers/hotkeyManager.js`; `references/openwhispr-main/src/hooks/useHotkeyRegistration.ts`; `references/openwhispr-main/resources/macos-globe-listener.swift` | Run selector-ready `VT-157` to close out `VT-071` after `VT-158`, then run `VT-072` and downstream controller wiring. | Fake event-stream tests first; runtime hotkey smoke only when real macOS registration changes. |
| Floating indicator | NSPanel/SwiftUI indicator skeleton exists and follows current placeholder status; final state contract remains blocked as metadata only, with `VT-082` done as the product follow-up. | `references/openwhispr-main/src/App.jsx` dictation state and preview behavior | Let the blocked-task resolver close `VT-081` when it reaches the indicator lane, then connect indicator to controller states after `VT-121` through `VT-124`. | Model tests for presentation; runtime QA when panel visibility or placement changes. |
| Dictation session controller | No central controller owns the full start, stop, transcribe, output, failure, and cancel flow yet. | `references/openwhispr-main/src/hooks/useAudioRecording.js`; `references/openwhispr-main/src/utils/permissions.ts` | Unblock recorder, transcription, and output seams, then run `VT-121` through `VT-124`. | Fake-backed controller tests; visible menu/runtime QA only once UI is wired to controller actions. |
| Transcript history | Local-only, disabled-by-default contract exists; settings flag and entry model have landed but `VT-131` and `VT-132` remain blocked by Xcode verification state. No history list UI is in MVP scope. | `references/openwhispr-main/src/stores/transcriptionStore.ts`; `references/openwhispr-main/src/components/HistoryView.tsx` | Retry `VT-131` and `VT-132` verification when local Xcode test execution is healthy, then run `VT-133` through `VT-135` behind the opt-in flag. | Unit tests for storage and append/clear behavior; Settings QA for the opt-in flag and clear action. |
| iOS companion and keyboard exploration | iOS containing app/setup surface exists; simulator and keyboard-extension work is separate from the macOS menu bar MVP. | iOS keyboard feasibility spec and user-provided visual direction | Resolve simulator/build blockers before `VT-143` through `VT-147`; do not block macOS MVP on iOS exploration. | XcodeBuildMCP or `xcodebuild` simulator evidence when available; blocker note when simulator evidence is unavailable. |

## Grooming Expectations

When a grooming or reference-audit task touches one of these areas, it must
update the row if it changes the implementation state, next task, blocker, or
reference evidence.

When the normal selector returns `no_ready`, the map should help the next agent
identify whether the correct action is blocker resolution, task decomposition,
or a new vertical product slice.
