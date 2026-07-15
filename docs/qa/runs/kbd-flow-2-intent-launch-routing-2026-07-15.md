# KBD-FLOW-2 Intent And Launch Routing QA

Date: 2026-07-15

Scope: the bounded keyboard handoff intent, its atomic App Group projection,
the keyboard microphone cold/warm launch branches, strict containing-app URL
routing, and the no-Full-Access setup route. This checkpoint selects Voice for
a valid launch but does not start capture or present the production handoff
sheet.

## Result

- With a valid warm session, the existing microphone path writes the existing
  Start command and does not create an intent or open the app.
- Without a valid session, the same microphone writes one ten-second intent
  containing opaque request and document identifiers plus the selected Voice
  action, then opens only its matching `holdtype://keyboard-handoff/<id>` URL.
- The keyboard keeps its central Ready indicator when cold, changes it to the
  non-interactive `Opening HoldType…` state during launch, and restores a
  retryable indicator when launch fails.
- Without Full Access, tapping the microphone opens
  `holdtype://settings/fullAccess` and does not write a handoff intent.
- The app consumes a valid matching intent before selecting Voice. Ordinary,
  malformed, expired, repeated, mismatched, and superseded launches are inert.
- Resolving the URL returns only a routing decision. KBD-FLOW-2 has no capture
  callback and therefore cannot start recording from URL handling alone.

## Automated Evidence

- `HoldType-iOS` Debug build on iPhone 16 Pro, iOS 18.6 Simulator: passed.
- Focused routing, store, keyboard controller, command-surface, keyboard-view,
  and containing-shell matrix: 52 tests passed, 0 failed.
- Intent tests cover strict route parsing, source identity and action round
  trip, expiry, mismatch, exactly-once consumption, and supersession.
- Router tests cover settings preservation, valid matching selection,
  malformed and unmatched launches, and repeated launch rejection.
- macOS `HoldType` baseline build: passed with pre-existing warnings.
- Final `git diff --check`: passed before checkpoint.

## Device Boundary

Simulator and deterministic unit evidence prove intent persistence, branching,
and app-side route validation. They do not prove that iOS permits the production
keyboard extension to open the containing app on a signed physical device,
nor do they prove microphone capture, return gestures, keyboard reconnection,
or text insertion. Those claims remain assigned to later KBD-FLOW stages.
