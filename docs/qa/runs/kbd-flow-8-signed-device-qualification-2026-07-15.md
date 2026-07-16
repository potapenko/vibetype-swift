# KBD-FLOW-8 Signed-Device Qualification — 2026-07-15

Status: **In progress.** Signed build, product inspection, installation, and
focused handoff tests pass. The physical keyboard/host runtime matrix is now
running with operator observation on the unlocked iPhone.

## Device And Build

- Initial source checkpoint: `0d1368d`
  (`Remove legacy keyboard recovery surfaces`)
- Current isolated handoff checkpoint: `b8bb0f2`
  (`Keep keyboard handoff failures inside sheet`)
- Device: Evgeny’s iPhone, iPhone 14 Pro Max (`iPhone15,3`)
- iOS: 26.5.2 (`23F84`)
- UDID: `00008120-001A19991E7BC01E`
- CoreDevice identifier: `DE70161A-3200-5D58-BF1E-DEA8B56FABC2`
- Development team: `PUA6HH22D7`
- Build result: `HoldType-iOS` Debug device build succeeded for `b8bb0f2`
- Installation result: the `b8bb0f2` app and embedded keyboard installed
  successfully on 2026-07-16

The build command selected only the `HoldType-iOS` scheme and physical iPhone
destination. It did not build or test the macOS app.

The 2026-07-16 device product was built from a clean archive of `b8bb0f2`, not
from the concurrent dirty working tree. The later master checkpoint `bc7f6f8`
adds the separate keyboard Auto modes popover and is not yet part of this
isolated handoff runtime result.

The combined master candidate `072e31a` also passes a signed generic iOS build
from a clean source archive. Its app and embedded keyboard sign and validate
successfully. A direct-device build could not acquire the phone as an Xcode
destination because the temporarily network-connected device requested an
unlock or cable connection. The `072e31a` product therefore remains built but
not installed; it must not replace `b8bb0f2` until the isolated runtime case
below is observed.

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
