# iOS Keyboard Experience

## Goal

Make HoldType feel like a dependable everyday iPhone keyboard with an added
voice-input action, while presenting iOS platform limits honestly.

## Experience Principles

- Keyboard first, voice second: voice features must not weaken ordinary typing.
- Familiar, not cloned: follow iOS conventions without copying Apple trade dress
  or embedding Apple emoji artwork.
- Preserve Space cursor movement; use a dedicated microphone control.
- Keep the total height close to a normal keyboard by placing voice controls in
  one compact prediction/action bar.
- Use literal transcription with punctuation by default. AI polishing requires
  an explicit user choice.
- Never discard a completed recording because transcription or insertion failed.

## Required Keyboard Behavior

A production iPhone keyboard must provide:

- alphabetic, number, and symbol layouts;
- Shift, Caps Lock, Delete with repeat, Space, Return, `123`, and Globe;
- field-appropriate Return presentation and basic auto-capitalization;
- double-space period, key callouts, useful hit targets, and light/dark appearance;
- cursor movement from a long press on Space;
- local autocorrection, a prediction row while voice is idle, and a clear Undo
  path for an unwanted correction;
- VoiceOver labels and actions that describe purpose and current state;
- a typing fallback that works without Full Access and without network access.

System emoji remains available through keyboard switching in the first product
version. A custom emoji surface is not an initial requirement.

The Phase 0 extension declares `en-US` only as feasibility metadata. Before the
typing-engine milestone starts, the product must approve the first-release
typing layouts, their autocorrection dictionaries, supported dictation
languages, and whether automatic language detection is enabled. Dictation
language and typing layout are separate user choices; QWERTY alone is not a
language contract.

## Voice States

The compact action bar presents one of these product states:

- `needsSetup`: keyboard, privacy, API key, or microphone setup is incomplete;
- `needsActivation`: the containing-app voice session is not active;
- `ready`: a bounded voice session can start;
- `listening`: waveform, elapsed time, Cancel, and Done are visible;
- `processing`: recording is safe locally while transcription completes;
- `inserted`: insertion succeeded and a short Undo opportunity is available;
- `recoverableFailure`: Retry and Copy/History recovery are available;
- `interrupted`: a call, Siri, route change, lock, or session expiry stopped work.

The UI must never label a state `ready` when tapping the microphone will first
require an unexplained app switch.

## Voice Activation Contract

The initial product hypothesis is a five-minute Quick Session that the user
explicitly starts in the containing app. It never starts automatically. The app
shows the active duration and provides an immediate Stop action; expiry, app
termination, interruption, and force quit stop the session.

During Quick Session, the microphone/audio engine remains visibly active and
the system microphone indicator remains present. In `ready`, samples are
discarded immediately in memory and are never persisted or uploaded. Tapping
the keyboard microphone changes the state to `listening` and only then starts
retaining the current utterance. The keyboard and onboarding must call this
armed state `Voice session on`, not imply that the microphone is inactive.

After activation, the user manually returns to the host app. iOS may leave
Apple's keyboard selected, so onboarding teaches Globe re-selection. HoldType
does not attempt a private automatic return.

With Full Access off, ordinary typing, read-only insertion of a transcript
published by the app, and conditional Apple Dictation fallback remain
available. The keyboard cannot send start/stop or insertion acknowledgement to
the containing app.

After an explicit Full Access disclosure, an active Quick Session may support
one-tap start/stop and acknowledgement through the shared bridge. When the
session is inactive, the keyboard shows `needsActivation`; it does not pretend
the microphone is ready and does not launch the containing app.

## Insertion Safety

The extension inserts only a non-empty accepted transcript.

When a voice session is tied to a `documentIdentifier`, the extension compares
the current identifier before automatic insertion. If it changed or is absent,
HoldType keeps the transcript recoverable and asks for an explicit Insert or
Copy action instead of guessing.

Repeated refreshes or late provider results must not insert the same transcript
twice.

## Failure And Fallback

- Secure fields, selected phone pads, and host-app keyboard rejection fall back
  to the system keyboard.
- Offline or provider failure does not block ordinary typing.
- Expired or corrupt shared state shows a compact unavailable state and does not
  insert text.
- Revoked microphone permission routes setup to the containing app.
- The keyboard never asks for credentials, microphone permission, or lengthy
  onboarding inline.
- Apple Dictation may appear as a system-provided control in some configurations.
  Otherwise the fallback is Globe, Apple keyboard, then Dictation.

## Onboarding Contract

The containing app presents setup in this order:

1. Explain the custom-keyboard and manual-return limits.
2. Add and enable HoldType Keyboard.
3. Explain what works without Full Access, then request it only for the active-
   session command path.
4. Configure the user's OpenAI key and request microphone permission.
5. Choose typing layout, dictation language, and Quick Session behavior.
6. Run a guided real dictation and recovery example.
7. Teach Globe re-selection, system emoji, Space cursor movement, and Apple
   Dictation fallback.

Permission denial or revocation must leave a clear recovery path without
reinstalling the app.

## iPhone And iPad

The first production milestone is iPhone in portrait and landscape.

iPad begins only after the iPhone typing and voice gates pass. It requires
separate validation for docked and floating keyboards, Stage Manager, multiple
windows, and Magic Keyboard/Bluetooth-keyboard workflows. A stretched iPhone
layout is not considered iPad support.

## Non-Goals For The First Product Version

- pixel-identical reproduction of Apple's keyboard;
- GIFs, stickers, or custom Apple-style emoji artwork;
- dozens of typing layouts;
- always-on background microphone by default;
- hidden semantic rewriting;
- a promised seamless return to the previous app through private APIs.

## Acceptance Gate

Before positioning HoldType as a default keyboard, dogfood must show that a
user can type for a normal working day without repeated fallback caused by tap
accuracy, Space, Delete, Return, Globe, cursor movement, or basic field types.
Autocorrection and predictions must also be useful enough that users do not
disable HoldType to repair routine typing.

Voice QA must show that completed speech is recoverable, Stop always stops the
microphone, and no late result is silently inserted into the wrong field.
