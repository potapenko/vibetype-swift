# KBD-FLOW-5 Keyboard Reconnection — 2026-07-15

## Scope

This checkpoint covers keyboard-extension reconnection and keyboard state UX.
It does not implement KBD-FLOW-6 durable delivery claims.

## Verified Contract

- A warm bridge session, one capture attempt, one microphone request, and the
  originating text document have separate opaque identities.
- Extension process lifetime is not used as ownership.
- A recreated extension reconnects only to exact shared attempt identity and a
  matching non-nil document identity.
- A changed or missing document identity cannot automatically insert a result.
- The central Voice indicator remains visible through Starting, Listening, and
  Processing; Listening routes the microphone to Finish and keeps Cancel
  explicit.
- Keyboard recovery copy is operational and contains no manual app-navigation
  instruction.
- Expiry returns the keyboard to Ready; the next microphone tap creates a fresh
  handoff.
- An unavailable Translate start does not claim or block the warm session.

## Automated Evidence

The focused KBD-FLOW-5 matrix passed 54 tests across bridge identity,
coordinator behavior, controller recreation, focus changes, expiry, central
indicator states, and keyboard copy.

After the final command-admission edge-case fix, the directly affected
`IOSKeyboardDictationSessionCoordinatorTests` suite passed 11 of 11 tests on an
iPhone 16 Pro iOS 18.6 Simulator.

## Scope Boundary

- No macOS app source, macOS test, or macOS package file was changed.
- No macOS build was run for this checkpoint.
- The unrelated working-tree change in
  `HoldType.xcodeproj/project.pbxproj` is excluded from this checkpoint.
- Exactly-once insertion and durable delivery acknowledgement remain owned by
  KBD-FLOW-6.
