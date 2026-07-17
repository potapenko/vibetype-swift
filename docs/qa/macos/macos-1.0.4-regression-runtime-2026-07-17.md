# macOS QA Run Report

Date: 2026-07-17 CEST
Task: macOS 1.0.4 hotkey and floating-indicator regression repair
Build/Test: focused tests, full macOS tests, macOS build, and diff hygiene pass
Runtime QA: blocked
Tool: Computer Use, `xcodebuild`, release scripts, and read-only artifact checks

## Scenario 1: Manual Recording And Indicator Continuity

### Actions

1. Started a scoped `caffeinate` guard before UI interaction.
2. Launched the fresh debug app, opened the real menu-bar menu, and started and
   stopped recording through its controls.
3. Kept the recording indicator visible for more than 12 seconds and inspected
   31 timestamped frames spread across that interval.
4. Built a signed local 1.0.4 (5) preview, mounted its DMG read-only, launched
   the packaged app, and repeated the menu recording and indicator observation.
5. Inspected the packaged Settings surfaces for permissions and shortcut
   registration.

### Expected

- Manual menu recording remains available independently of the global hotkey.
- The indicator appears while recording and its pulse/orbit animation does not
  restart once per second.
- The packaged app reports the Right Command hold shortcut as registered.

### Observed

- The debug menu recording ran for 51.872 seconds and transcription succeeded.
- The packaged menu recording ran for 52.127 seconds and transcription
  succeeded.
- In both runs the indicator remained visible. Across each 31-frame sequence,
  the orbit dot progressed through distinct positions after more than 12
  seconds instead of snapping back once per second.
- The menu changed to `Recording...` with `Stop Recording` during the active
  session.
- The packaged Settings UI showed Microphone, Accessibility, and Input
  Monitoring as allowed, plus `Right Command - Hold to record` and `Global
  hotkey active`.

### Result

PASS

## Scenario 2: Real Packaged Right Command Hold

### Actions

1. Attempted a bounded synthetic Right Command input while the packaged app was
   running.
2. Inspected the compact runtime log for a distinguishable event-tap key down
   and key up.
3. Left the packaged app running and requested one physical 12-15 second Right
   Command hold/release.

### Expected

- One physical key down starts one recording session.
- One physical key up stops that same session exactly once.
- The runtime log contains one `hotkey_event` key down and one key up, followed
  by one recording start and stop.

### Observed

- The synthetic input did not reach the CGSession event tap and produced no
  `hotkey_event`. It is not accepted as proof of the real hotkey path.
- No physical packaged-app edge had been captured when this report was written.
- Deterministic mapper tests cover stale key-down/key-up snapshots, ambiguous
  Left Command release, bounded recovery, and exact-once release behavior.

### Result

BLOCKED

### Blocker

Computer Use cannot generate the required hardware-level Right Command edge.
The shortest resume action is one physical Right Command hold for 12-15 seconds
in the currently running packaged app, followed by release.

## Scenario 3: Local Artifact Qualification

### Actions

1. Ran `scripts/release/build_preview_dmg.sh --version 1.0.4 --build 5` with the
   installed Apple Development identity selected through an ignored local
   signing override.
2. Verified the exported app with `codesign --verify --deep --strict` and
   inspected its bundle metadata, hardened-runtime signature, and entitlements.
3. Validated the DMG notarization ticket with `xcrun stapler validate`.
4. Mounted the DMG read-only and launched its packaged app through
   LaunchServices.

### Expected

- A local preview can launch and support bounded runtime qualification.
- A publishable replacement must use Developer ID Application signing, be
  notarized, and retain the audio-input entitlement.

### Observed

- Local artifact:
  `dist/preview/v1.0.4/HoldType-1.0.4.dmg`.
- DMG SHA-256:
  `dd1fe463d6dab55f924761e8c374c1a1952fdf50c6927302457a4c320139411d`.
- ZIP SHA-256:
  `a54d5f19a216cc33c1efc7caafc3bf6d1b7109745ced107658310c55278651e9`.
- The bundle reports identifier `app.holdtype.HoldType`, version 1.0.4, build 5,
  a valid Apple Development signature, hardened runtime, and
  `com.apple.security.device.audio-input = true`.
- The preview manifest explicitly reports `notarized: false` and
  `public_release: false`; `stapler` confirms that the DMG has no ticket.
- No Developer ID Application identity or configured notarization profile is
  available on this Mac.

### Result

PASS for local runtime qualification; BLOCKED for public release eligibility.

### Blocker

Build the final artifact with a Developer ID Application identity and a
notarization profile, staple the ticket, then repeat the physical hotkey and
indicator smoke from that packaged artifact.

## Evidence

- Runtime log:
  `~/Library/Caches/HoldType/Diagnostics/RuntimeLogs/runtime-20260717.log`.
- Focused hotkey and indicator/controller test runs passed.
- Full `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test` passed.
- Full `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' build` passed.
- `git diff --check` passed.
- No dictated text, raw audio, provider payload, or credential was retained as
  QA evidence.

## Follow-Up

1. Capture one physical packaged Right Command hold/release and append the exact
   timestamped hotkey/start/stop result here.
2. Produce and notarize a Developer ID artifact on a release-capable machine.
3. Do not publish or replace 1.0.4 until both remaining gates pass.
