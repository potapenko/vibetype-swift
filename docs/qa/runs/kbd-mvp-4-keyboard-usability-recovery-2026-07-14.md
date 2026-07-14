# KBD-MVP-4 Keyboard Usability And Recovery QA — 2026-07-14

## Scope

This run qualifies the keyboard usability recovery changes described in
`docs/ios-keyboard-usability-recovery-plan.md`. It does not qualify a signed
physical-device keyboard matrix or a longer background-session lifetime.

## Automated Verification

- Simulator: iPhone 16, iOS 18.6
  (`71E5A24E-74E4-49EE-BDFB-026C4C15CCCC`)
- `HoldType-iOS` Debug Simulator build: passed
- Full `HoldType-iOS` test run: 1,062 tests in 140 suites passed
- Generic Simulator build without code signing: passed
- Generic iOS Release build without code signing: passed
- macOS baseline build: passed

The automated contract covers all recovery presentations, status vocabulary,
absence of a keyboard Settings action, local editing while Full Access is off,
one-request insertion ownership, stale-request rejection, dynamic colors,
compact landscape, safe areas, and accessibility copy.

The follow-up Full Access copy refinement is also covered at the real UIKit
view level: the complete Settings route uses a bold font, the
return-to-HoldType sentence remains separate, and `Shortcut: hold 🌐 → Keyboard
Settings.` remains visible at the 393-point phone width.

## Simulator Interactive Extension Result

Starting state:

- the current Debug app was installed with its embedded `HoldTypeKeyboard`
  extension and launched with `HOLDTYPE_AUTOMATION=1` plus live Keychain UI
  disabled;
- the real extension was presented in the containing app's standard Keyboard
  Practice field;
- Full Access was off;
- the keyboard dictation session was stopped;
- the practice field contained 39 characters.

Observed unavailable presentation:

- the keyboard contained no permanent Settings button;
- the HoldType microphone and waveforms were absent;
- the centered HoldType mark had no duplicated status caption;
- the voice stage communicated the required action once through `Enable Full
  Access` and the complete recovery route;
- the stage title was `Enable Full Access`;
- the stage displayed the complete route through iPhone Settings and then back
  to HoldType to start a keyboard session;
- `Latest` remained visible but disabled;
- the space key was visibly labelled `space`;
- no visible recovery label was clipped at the tested width;
- the disabled microphone icon retained by iOS in the system-owned bottom strip
  remained Apple Dictation, not a HoldType action. `hasDictationKey` was true,
  which is UIKit's public declaration for disabling the system Dictation key
  when a custom keyboard supplies dictation.

Computer Use exercised the actual extension controls. Period added one
character, Space added one, Delete removed one, and Return added a line break.
After the sequence the host field contained 41 characters and visibly ended in
a period plus line break. The system Globe switched from HoldType to an Apple
keyboard.

## Evidence Boundary

This Simulator pass proves the actual extension presentation and host-field
interaction with Full Access off. It does not prove physical-device touch
delivery, signing, microphone ownership, background-session duration, Notes
behavior, or provider transcription.

The signed physical-device keyboard/host matrix remains required before
TestFlight or release. The current 60-second app-owned session limit also
remains unchanged until a signed-device measurement proves a longer safe
lifetime.

## Result

KBD-MVP-4 keyboard usability and recovery behavior is **passed in the
Simulator lane**. The physical-device release gate remains pending and must be
reported separately.
