# KBD-FLOW-8 Signed-Device Qualification — 2026-07-15

Status: **In progress.** Signed build, product inspection, installation, and
focused handoff tests pass. The physical keyboard/host runtime matrix is now
running with operator observation on the unlocked iPhone.

## Device And Build

- Initial source checkpoint: `0d1368d`
  (`Remove legacy keyboard recovery surfaces`)
- Current isolated handoff checkpoint: `b8bb0f2`
  (`Keep keyboard handoff failures inside sheet`)
- Current deterministic qualification checkpoint: `10c5fb1`
  (`Qualify keyboard safe-area handoff matrix`)
- Current installed archive checkpoint: `be33560`
  (`Align iOS release verifier with keyboard handoff`)
- Device: Evgeny’s iPhone, iPhone 14 Pro Max (`iPhone15,3`)
- iOS: 26.5.2 (`23F84`)
- UDID: `00008120-001A19991E7BC01E`
- CoreDevice identifier: `DE70161A-3200-5D58-BF1E-DEA8B56FABC2`
- Development team: `PUA6HH22D7`
- Build result: `HoldType-iOS` Debug device build succeeded for `b8bb0f2`
- Installation result: the local Release archive app and embedded keyboard from
  `be33560` installed successfully on 2026-07-16 as version `1.0` build `1`

The build command selected only the `HoldType-iOS` scheme and physical iPhone
destination. It did not build or test the macOS app.

The 2026-07-16 device product was built from a clean archive of `b8bb0f2`, not
from the concurrent dirty working tree. The later master checkpoint `bc7f6f8`
adds the separate keyboard Auto modes popover and is not yet part of this
isolated handoff runtime result.

The combined master candidate `072e31a` also passed an earlier signed generic
iOS build from a clean source archive. The later `10c5fb1` checkpoint now
passes the same signed generic iOS build and embedded-binary validation. Its app
and keyboard use development team `PUA6HH22D7`, share App Group
`group.app.holdtype.HoldType.shared`, and contain the required microphone and
Full Access declarations. Its app code is unchanged in the later `be33560`
archive now installed for the current physical matrix.

## Focused Handoff Verification

Simulator: iPhone 17 Pro, iOS 26.5
(`2388F192-115A-45FF-B5C3-2B666B4E42F7`).

Focused suites:

- `IOSKeyboardDictationSessionCoordinatorTests`;
- `IOSKeyboardHandoffSheetTests`.

Result: **20 tests in 2 suites passed.** The checks cover Starting, Listening,
Processing, runtime failure, expiry, close/cancel, stale direct start, accepted
completion, and exclusive delivery. A generic unsigned iOS
`build-for-testing` also succeeded. These results prove deterministic handoff
state reduction; they do not substitute for physical microphone or host-field
interaction.

The broader keyboard/handoff matrix was repeated on 2026-07-16 after aligning
the safe-area test fixture with its declared compact trait environment. Result:
**100 tests in 11 suites passed** on the iPhone 17 Pro iOS 26.5 simulator. The
change is confined to the test fixture's trait overrides; the production
keyboard view is unchanged. The selected suites cover the keyboard surface,
handoff intent and routing, sheet presentation, shared session coordination,
snapshot and Latest delivery, extension recreation, document/host matching,
and exactly-once insertion. No ordinary Voice test suite or macOS target was
run.

The iOS release spec was also reconciled with the validated keyboard handoff
route: app launch from the keyboard is no longer listed as a release non-goal,
while automatic return and unsupported policy bypass remain out of scope.

## Signed Product Inspection

- Containing app bundle: `app.holdtype.HoldType.ios`
- Keyboard bundle: `app.holdtype.HoldType.ios.keyboard`
- Both products are signed by the same development team.
- Both products contain the matching App Group
  `group.app.holdtype.HoldType.shared`.
- The containing app contains the microphone purpose string.
- The keyboard declares `RequestsOpenAccess = true`.
- Embedded-binary validation passed during the signed build.

## Signed Release Bundle Verification

A clean `Release` generic-iOS product was built from app checkpoint `10c5fb1`
with development team `PUA6HH22D7`. The repository release-bundle verifier was
reconciled with the current keyboard handoff contract before inspecting it:

- containing-app background mode is exactly `audio`, which keeps app-owned
  capture alive after the user swipes back;
- the production keyboard requires `RequestsOpenAccess = true` for its bounded
  App Group command boundary;
- Apple-optimized CgBI app icons are decoded and rejected when any alpha is
  translucent;
- provisioning profiles and code-signature metadata are excluded from the
  keyboard implementation byte scan, while executable and resource bytes
  remain covered.

Verifier result: **53 passed, 0 failed, 0 manual.** Verifier regression result:
**18 tests passed.** This proves the signed local Release bundle contract and
keyboard isolation. It is development-signed evidence, not yet an App Store
distribution signature or an uploaded TestFlight candidate.

A clean local archive of checkpoint `be33560` also succeeded at
`/tmp/holdtype-kbd-flow8-archive.gwGPJz/HoldType-iOS-be33560.xcarchive`.
Its embedded app independently passes the same **53/53** verifier checks and
identifies as version `1.0` build `1`, bundle `app.holdtype.HoldType.ios`, team
`PUA6HH22D7`. The archive uses the installed Apple Development identity. No
Apple Distribution identity is currently installed, and no App Store export,
certificate creation, or upload was attempted. Therefore this is archive
readiness evidence, not an internal TestFlight candidate.

## Runtime History

CoreDevice installed the app, then rejected the launch because the physical
iPhone was locked:

```text
RequestDenied: Unable to launch app.holdtype.HoldType.ios because the device
was not, or could not be, unlocked.
```

Unlocking the physical phone is not available to Mac automation. No runtime
state, microphone lifecycle, swipe-back behavior, host-field insertion, or
TestFlight result is claimed from this attempt.

Later on 2026-07-16 CoreDevice reported the unlocked phone as connected and
installed the local Release archive from `be33560`. A device app inventory
confirmed HoldType `1.0` build `1` at bundle
`app.holdtype.HoldType.ios`. Installation does not itself prove keyboard
activation or any handoff runtime behavior; the nominal case below remains the
first physical claim.

On 2026-07-16 CoreDevice confirmed the same phone is booted, paired, connected,
in Developer Mode, and available for development services. The signed
`b8bb0f2` product installed successfully without automatically launching the
containing app. The first bounded runtime case is now awaiting the operator's
observed result:

1. cold HoldType;
2. Notes with the HoldType keyboard and an active insertion point;
3. tap the existing keyboard Voice indicator once;
4. observe the handoff sheet reach Listening;
5. use the bottom system return gesture;
6. dictate a short phrase and tap the indicator again for Finish;
7. observe Processing, exactly-once insertion, keyboard retention, and whether
   HoldType reopens unexpectedly.

## Qualification Matrix Ledger

`Automated pass` proves deterministic state and delivery logic only. A row
remains `Physical pending` wherever the KBD-FLOW-8 plan requires real
microphone, extension lifecycle, host-field, permission, or system-gesture
evidence.

| Path | Automated evidence | Physical evidence |
| --- | --- | --- |
| Cold valid Start, sheet, swipe, Finish, insert | Start/Finish and sheet reducers pass | Pending |
| Healthy warm repeat | Warm acknowledgement and reuse pass | Pending |
| Setup blockers and fresh tap after repair | Preflight and targeted routing pass in focused tests | Pending |
| Full Access off/on | Restricted editing and route selection pass | Pending |
| Microphone undecided/granted/denied | Permission behavior is not claimed by the keyboard matrix | Pending |
| Standard, Translate, Improve, combined | Mode combinations and cold Translation intent pass | Pending where available |
| Sheet Starting, Listening, close, expiry, stale relaunch | All named reducer/coordinator paths pass | Pending |
| Extension retained and recreated | Durable reconnect and nil-document recovery pass | Pending |
| Same field, changed field, changed host | Document/host insertion gates pass | Pending |
| Finish and Cancel | Same-attempt completion/cancellation pass | Pending |
| Offline, timeout, interruption, provider failure, app termination | Provider failure passes; remaining runtime boundaries are not claimed | Pending |
| Automatic insertion, Latest, duplicate delivery | Exactly-once claim and Latest fallback pass | Pending |
| Expiry followed by fresh cold handoff | Expired reconnect and next-launch transition pass | Pending |
| Ordinary standalone Voice with no sheet | Outside the selected keyboard automation | Pending observation only |
| Internal TestFlight candidate | Local archive and 53/53 bundle checks pass | Distribution identity/export/upload pending |

## Remaining Matrix

Record the observed nominal cold-handoff result first. Then continue the full
KBD-FLOW-8 matrix from the plan, including Cancel, failure/expiry, warm reuse,
extension recreation, changed document/host, Latest fallback, and ordinary
standalone Voice. Do not substitute iPhone Mirroring for custom-keyboard
interaction: Mirroring is only a containing-app inspection surface and may
suppress the onscreen iPhone keyboard.

## Scope Boundary

- No macOS source, test, package, or build was touched.
- The unrelated working-tree change in
  `HoldType.xcodeproj/project.pbxproj` remains excluded.
- KBD-FLOW-8 and the overall goal remain incomplete.
