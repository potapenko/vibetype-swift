# KBD-FLOW-6 Exactly-Once Delivery — 2026-07-15

## Scope

This checkpoint covers terminal keyboard delivery and reuse of an unexpired
app-owned session. It stays inside the iOS keyboard bridge, the special
keyboard session coordinator, the keyboard extension, and their tests.

## Verified Contract

- Finish reaches the existing keyboard workflow once; accepted output is
  already persisted by that workflow as canonical Latest and under the current
  History policy before bridge delivery.
- Shared coordination remains exactly two bounded atomic projections: one
  extension-written command and one containing-app-written state.
- The extension requests a fresh delivery claim and inserts only after the app
  publishes a grant for that exact claim.
- The in-process insertion guard is set before `insertText` and the durable
  claim prevents a recreated extension from replaying an uncertain insertion.
- Changed or missing document identity never requests a claim and falls back to
  canonical Latest.
- A matching acknowledgement clears only the terminal attempt and republishes
  the still-unexpired session as Ready.
- A competing claim is rejected; a new extension cannot inherit a claim granted
  to a previous process.
- Session expiry behavior remains unchanged: the next microphone tap uses a
  fresh cold handoff.

## Automated Evidence

The focused iOS Simulator matrix covered:

- `KeyboardDictationBridgeTests`: 5 passed;
- `IOSKeyboardDictationSessionCoordinatorTests`: 12 passed;
- `KeyboardViewControllerTests`: 18 passed after the terminal-state race fix.

The matrix verifies bounded claim records, exclusive grants, matching
acknowledgement, warm reuse, one insertion, extension recreation, changed and
missing destinations, and Latest fallback.

## Scope Boundary

- No macOS app source, macOS test, macOS package, or Xcode project file was
  changed.
- No macOS build was run for this checkpoint.
- The unrelated working-tree change in
  `HoldType.xcodeproj/project.pbxproj` is excluded from this checkpoint.
- Physical end-to-end insertion remains part of KBD-FLOW-8 qualification.
