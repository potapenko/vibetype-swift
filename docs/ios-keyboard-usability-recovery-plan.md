# HoldType iOS Keyboard Usability Recovery Plan

Status: implemented; Simulator lane passed and physical-device lane pending,
2026-07-14.

This direct-task plan repairs the physical-device usability failure reported for
HoldType Keyboard. Product behavior is governed by
`docs/specs/features/ios-v1-release.md` and
`docs/specs/features/ios-keyboard-experience.md`.

## Outcome

The keyboard must never present a control that looks actionable while silently
doing nothing. A user who cannot dictate must see the exact recovery path in the
keyboard itself. The microphone appears only when it can start or finish a real
app-owned recording.

## Approved Product Decisions

- Remove the permanent keyboard `Settings` button. It neither resolves a
  stopped app-owned session nor has physical-device evidence that it opens the
  intended destination reliably.
- Keep the centered HoldType mark free of status text. It is identity only;
  every state and recovery message belongs to the voice stage and appears once.
- Keep Settings and every setup editor in the containing app.
- Replace the microphone and decorative waveform with a complete instruction
  when Full Access is unavailable, the app-owned session is stopped or expired,
  or the last request failed.
- Use `Session not running` as a state, never `Open HoldType` as an ambiguous
  pseudo-action.
- Show the active microphone only in Ready and Listening. Show progress, not a
  disabled microphone, while Start is awaiting acknowledgement or provider work
  is processing.
- Keep punctuation, Space, Delete, Return, Globe, and eligible Latest available
  independently from voice readiness.
- Label Space plainly and keep adaptive Return on one line.
- Set the custom-keyboard dictation declaration so iOS treats its own Dictation
  key as unavailable while HoldType supplies the voice action. Depending on the
  device and OS, iOS may suppress the system button or leave it visible in a
  disabled state; that system-owned strip is not a HoldType control.
- Tell users consistently that Full Access is required only for
  keyboard-controlled voice. Local editing and safe Latest remain available
  without it.

## Recovery Copy

### Session stopped or expired

Title: `Start a voice session`

Instruction: `Open HoldType → Voice → Keyboard Dictation Session → Start
Keyboard Session. Then return here.`

### Full Access unavailable

Title: `Enable Full Access`

Emphasized route: `iPhone Settings → General → Keyboard → Keyboards →
HoldType → Allow Full Access.`

Follow-up: `Then open HoldType and start a session.`

Secondary shortcut: `Shortcut: hold 🌐 → Keyboard Settings.`

The shortcut never replaces the complete route.

### Request failure

Title: `Dictation stopped`

Instruction: `Open HoldType → Voice to review the problem and start a new
keyboard session.`

## Execution

1. Update the canonical specs before implementation.
2. Add an explicit keyboard voice-stage presentation model.
3. Replace unavailable microphone states with recovery content.
4. Remove the keyboard Settings action and its unbounded external callback.
5. Align containing-app setup, privacy, and Full Access copy.
6. Declare HoldType dictation support so iOS disables or suppresses its own
   Dictation key, and clarify editing controls.
7. Add deterministic presentation and controller coverage for every state.
8. Exercise the real extension in Simulator with sanitized Keychain access.
9. Run the full iOS regression, generic iOS Release build, macOS build, and
   `git diff --check`.
10. Record only observed physical-device results. Do not infer a device pass
    from Simulator or unit tests.

## Session-Lifetime Gate

The current 60-second lifetime came from a bounded feasibility spike. The
approved product plan names a 60-minute maximum, but an idle containing app has
not proved that duration on a signed device without a forbidden silent-audio
keepalive.

This task does not change the constant from 60 seconds to 60 minutes by source
assertion alone. The longer product lifetime remains a signed-device feasibility
gate. Until that gate passes, UI and QA must describe the implemented session as
brief and must not promise a one-hour background session.

## Exit

- No unavailable state displays the active microphone or waveform.
- Every unavailable state contains a complete recovery instruction.
- No permanent Settings control remains in the keyboard.
- No status text appears under or beside the HoldType mark.
- Full Access guidance is consistent between Voice, Privacy, specs, and tests.
- `hasDictationKey` is enabled so the Apple-owned Dictation key is disabled or
  suppressed while HoldType supplies its voice action; Simulator may retain the
  disabled icon in the system strip.
- Simulator interaction proves local editing controls and visible recovery
  states through the real extension.
- Any unverified physical row remains explicitly pending.
