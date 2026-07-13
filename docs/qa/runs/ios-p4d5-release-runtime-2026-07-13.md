# iOS P4D-5 Release And Runtime Qualification QA

Date: 2026-07-13
Milestone: P4D-5 release and runtime qualification
Record status: P4D-5A local automated engineering evidence is current. Its only
remaining gates are the Xcode Organizer privacy-report export and explicit
release-owner confirmation of the forward-only rule. P4D-5B remains pending.
Evidence fields marked `Pending` are not release claims.

## Decision

P4D-5 is split into two independent qualification checkpoints:

- P4D-5A is the local technical Release gate.
- P4D-5B is the signed physical-device gate.

P4D-5A is not yet marked passed because the Mac was locked when the prepared
local archive reached the Xcode Organizer report step and because the release
owner has not yet recorded the forward-only confirmation. P4D-5 and P4 remain
open until both checkpoints pass. A completed P4D-5A may be checkpointed while
P4D-5B waits for a qualifying device and operator-local signing, but it must not
be presented as physical-device evidence, recorder approval, App Store
readiness, or approval of the Phase-0 keyboard as a product.

M0B/M0C keyboard constraints, production typing, TestFlight dogfood,
battery/performance qualification, and App Review remain in P6 through P8.
They are not silently absorbed into this record.

## P4D-5A — Local Technical Release Gate

All rows must have reproducible evidence before P4D-5A can pass. A focused test
or an older milestone record may support investigation, but it does not replace
the full serialized regressions below.

| Gate | Required evidence | Status |
| --- | --- | --- |
| Full iOS regression | One signed, serialized, non-parallel `HoldType-iOS` simulator run with warnings as errors and automation Keychain access disabled | Passed |
| Portable packages | Complete serialized strict test runs for `HoldTypeDomain`, `HoldTypeOpenAI`, `HoldTypePersistence`, and `HoldTypeIOSCore` | Passed |
| macOS regression | Complete serialized macOS test regression and ordinary `HoldType` build; a diagnostic warnings-as-errors audit records pre-existing Swift 6/deprecation debt, while any new diagnostic in P4D-5-owned or shared portable code remains blocking | Passed |
| Generic builds | Clean generic iOS Simulator Debug and Release builds containing the app and embedded keyboard extension | Passed |
| Bundle contract | Processed app/extension plists, source and simulated entitlements, privacy manifests, code signatures, embedding, executable identities, and dependency graphs inspected from the built Release bundle | Passed for the local Simulator boundary; signed processed entitlements remain P4D-5B |
| App icon | Release bundle contains the compiled asset catalog and complete opaque iPhone, iPad, and marketing AppIcon slots without asset-catalog warnings | Passed |
| Keyboard isolation | Release keyboard binary has no app-only Domain, Persistence, OpenAI, iOS-core, Keychain, microphone, audio-capture, provider, raw-audio, or History dependency | Passed |
| Release UI boundary | Internal Phase-0 bridge probe UI, labels, routes, and symbols are absent from the Release containing app | Passed |
| Privacy | Exact purpose strings and executable-bundle manifests pass source and built-artifact inspection; Xcode privacy report has no unexplained category | Manifest/archive inspection passed; Organizer report Pending |
| No downgrade | Forward-only persisted wire values and the prohibited rollback path are recorded; the release owner explicitly accepts the rule | Policy recorded; owner confirmation Pending |
| Runtime | Bounded iPhone and iPad Release-equivalent smoke plus local accessibility-state coverage completes without live microphone, provider, Keychain, or consent mutation | Passed locally |
| Review | Independent release, accessibility, privacy, and keyboard-isolation review has no unresolved P1 or P2 finding | Passed |
| Hygiene | `git diff --check` and run-owned Simulator/build-artifact cleanup are complete | Passed |

### Evidence Ledger

Fill every applicable field with the exact command, destination, configuration,
result count, log, and result-bundle or artifact path. `Pending` means the
evidence has not yet been accepted for this gate.

- Full serialized iOS simulator regression
  - Destination: iPhone 16, iOS 18.6,
    `ADF05678-789A-4607-B80E-0948B54D5802`.
  - Command/configuration: `HoldType-iOS`; signed Debug simulator build;
    `-parallel-testing-enabled NO`; one worker; automation Keychain UI skipped;
    Swift and GCC warnings as errors; index store disabled.
  - Result: 1,915 tests in 179 suites passed in 73.327 seconds.
  - Log: `/tmp/p4d5-ios-full-serialized-final5.log`.
  - Result bundle: `/tmp/p4d5-ios-full-serialized-final5.xcresult`.
- Strict package regressions
  - Configuration: `swift test -j 1 --no-parallel -Xswiftc
    -warnings-as-errors` for each package.
  - `HoldTypeDomain`: 159 tests / 32 suites passed;
    `/tmp/p4d5-HoldTypeDomain-serialized-strict-tests-final.log`.
  - `HoldTypeOpenAI`: 118 tests / 8 suites passed;
    `/tmp/p4d5-HoldTypeOpenAI-serialized-strict-tests-final.log`.
  - `HoldTypePersistence`: 1,097 tests / 57 suites passed on the current
    qualification-fixture and process-context code;
    `/tmp/p4d5-HoldTypePersistence-serialized-strict-tests-final4.log`.
  - `HoldTypeIOSCore`: 97 tests / 8 suites passed;
    `/tmp/p4d5-HoldTypeIOSCore-serialized-strict-tests-final.log`.
  - The current slice changes package source only in `HoldTypePersistence`.
    The other three strict logs remain source-current, and the final5 iOS run
    also rebuilt every linked package with warnings as errors.
- Full macOS regression and build
  - Test result/log: 441 tests / 50 suites passed in 1.617 seconds;
    `/tmp/p4d5-macos-full-serialized-final.log` and
    `/tmp/p4d5-macos-full-serialized-final.xcresult`.
  - Build result/log: ordinary `HoldType` macOS build passed with automation
    Keychain UI skipped; `/tmp/p4d5-macos-build-final.log`.
  - Diagnostic WAE audit: `/tmp/p4d5-macos-wae-build.log` confirms the
    remaining failures are pre-existing Swift 6/default-main-actor and
    deprecation debt in six unrelated macOS files. The same diagnostics appear
    in the pre-P4D-5 `/tmp/p4d4-ui-macos-build.log`; no diagnostic in a
    P4D-5-owned or shared portable path was accepted.
- Generic iOS Simulator builds
  - Debug result/artifact/log: passed with Swift/GCC warnings as errors;
    `/tmp/p4d5-ios-generic-debug-final5.log`.
  - Release result/artifact/log: passed with Swift/GCC warnings as errors;
    `/tmp/p4d5-ios-generic-release-final5.log`; preserved app at
    `/tmp/p4d5-ios-release-artifacts-final5/HoldType-iOS.app`.
  - Current locally ad-hoc-signed Simulator archive: archive passed after the
    final5 executable and qualification routes were built at
    `/tmp/HoldType-iOS-P4D5-final5.xcarchive`; log
    `/tmp/p4d5-ios-archive-final5.log`. It is current Organizer and archive
    inspection input, not signed-device or distribution evidence.
- Release-bundle verifier
  - Verifier command/version: `python3
    scripts/verify_ios_release_bundle.py --app <app> --json` fails closed with
    exit 2 while manual checks remain; the explicitly acknowledged local run
    adds `--allow-manual`. Its 14 unit tests, including a valid translucent PNG
    rejection fixture, passed at
    `/tmp/p4d5-ios-release-verifier-tests-final5.log`.
  - Result/log: 51 passed, 0 failed, 2 manual;
    `/tmp/p4d5-ios-release-verifier-final5.json`. The unacknowledged run
    returned exit 2 with the same checks at
    `/tmp/p4d5-ios-release-verifier-manual-boundary-final5.json`.
  - The current ad-hoc archive independently returns the same 51 pass / 2
    manual result. Its unacknowledged run exits 2 at
    `/tmp/p4d5-ios-archive-verifier-manual-boundary-final5.json`; its explicitly
    acknowledged local run exits 0 at
    `/tmp/p4d5-ios-archive-verifier-final5.json`. App and extension code
    signatures contain the exact bundle identifiers.
  - Manual items: generic Simulator and ad-hoc Simulator-archive signatures
    expose no distribution processed entitlements. Preserved simulated xcent
    files independently contain exact app/extension application identifiers
    and only App Group `group.app.holdtype.HoldType.shared`; signed-device proof
    remains P4D-5B.
  - Inspected app:
    `/tmp/p4d5-ios-release-artifacts-final5/HoldType-iOS.app`.
  - Inspected extension: embedded `PlugIns/HoldTypeKeyboard.appex` in that app.
- Runtime and accessibility
  - iPhone device/OS/configuration: clean run-owned iPhone 16, iOS 18.6,
    `ADF05678-789A-4607-B80E-0948B54D5802`; preserved Release bundle;
    automation Keychain UI skipped; no qualification route.
  - iPhone result/evidence: a fresh uninstall/install/first launch reached
    `Ready to dictate` without a foreground retry from the current final5
    Release artifact; standard and maximum Dynamic Type/dark/Increase Contrast
    content remained scrollable; practice text survived a Voice/Settings round
    trip. Final fresh-launch screenshot:
    `/tmp/p4d5-release-iphone-fresh-ready-final5.jpg`.
  - iPad device/OS/configuration: clean run-owned iPad Pro 11-inch (M4), iOS
    18.6, `11A58EEC-B52F-4ABE-9642-27D157FE73E7`; regular-width split shell;
    current final5 Release bundle; the final clean launch used light appearance
    and standard content size, while the qualification pass also covered dark
    appearance, Increase Contrast, and
    accessibility-extra-extra-extra-large content size.
  - iPad result/evidence: a fresh uninstall/install/first launch reached
    `Ready to dictate` in the initial process opportunity; Voice, Latest
    Result, Privacy, disclosure, and practice content remained reachable by
    scrolling. Final screenshot:
    `/tmp/p4d5-release-ipad-fresh-ready-final5.jpg`.
  - Deterministic iPad gallery evidence:
    `/tmp/p4d5-gallery-voice-listening-max-final.jpg`,
    `/tmp/p4d5-gallery-latest-success-max-final.jpg`,
    `/tmp/p4d5-gallery-privacy-ready-final.jpg`, and
    `/tmp/p4d5-gallery-privacy-disclosure-final.jpg`.
    The additional setup-blocked, provider post-processing, and saving-result
    routes were also exercised on the regular-width shell; current saving
    evidence is `/tmp/p4d5-gallery-ipad-saving-result-standard-final5.jpg`.
  - Current iPad action/confirmation evidence:
    `/tmp/p4d5-gallery-latest-copy-final4.jpg`,
    `/tmp/p4d5-gallery-privacy-withdraw-confirmation-standard-final4.jpg`, and
    `/tmp/p4d5-gallery-privacy-reset-confirmation-standard-final4.jpg`.
    Copy produced only `Copied`; Share did not open and the Practice field
    retained its empty placeholder. The exact confirmation titles were present
    in the accessibility tree. Escape dismissed each dialog, after which the
    original Withdraw or Reset action remained available; no fake mutation was
    admitted.
  - Compact-iPhone deterministic gallery coverage exercised setup blocked,
    arming, listening, finalizing, provider transcription and post-processing,
    saving result, Capture recovery, failed-History retry, accepted Latest
    Result actions, Privacy accepted/unreadable/ready states, the full provider
    disclosure, and both destructive confirmation dialogs. Current rendered
    evidence includes
    `/tmp/p4d5-gallery-iphone-latest-copy-max-final5.jpg`,
    `/tmp/p4d5-gallery-iphone-saving-result-max-final5.jpg`,
    `/tmp/p4d5-gallery-iphone-withdraw-confirmation-max-final5.jpg`,
    `/tmp/p4d5-gallery-iphone-reset-confirmation-max-final5.jpg`, and
    `/tmp/p4d5-gallery-iphone-privacy-disclosure-max-final5.jpg`.
    The final Latest Result action label wraps without truncation, Copy reports
    only `Copied`, and Cancel closes each confirmation without mutation.
  - Focused workflow, accessibility-announcement, and qualification-route
    regression: 73 tests in 3 suites passed in 5.222 seconds;
    `/tmp/p4d5-review-fixes-focused-final5.log`.
  - Supported local configuration coverage includes light/dark appearance,
    standard and maximum accessibility content size, Increase Contrast, and
    portrait layouts on compact and regular-width shells. No custom P4D-5
    animation is present; standard SwiftUI controls own Reduce Motion behavior.
    Public headless Simulator tooling in the installed Xcode exposes no Reduce
    Motion or orientation control, so actual Reduce Motion and landscape passes
    remain P4D-5B instead of being inferred from private defaults, AppleScript,
    or unsupported Simulator APIs.
- Independent review
  - Release/privacy and keyboard-isolation review found four P2 issues: exact
    application-identifier verification, a fail-closed AppIcon gate, an
    over-broad rollback exception, and a manual-verifier success exit. All four
    were fixed and the current verifier tests and final5 artifact pass.
  - Concurrency/spec review checked the one-opportunity foreground recovery
    recheck, persistence ownership, deterministic qualification seams, and
    product contracts. Its P2/P3 findings were fixed and covered by the current
    focused, package, and full iOS regressions.
  - Accessibility/runtime review checked announcement coalescing, Voice/Latest
    Result/Privacy semantics, headings, minimum action targets, independent
    actions, exact dialogs, and non-mutating fixtures. It reported no remaining
    P1/P2 after the fixes and rendered evidence above.
  - QA-ledger audit identified a stale archive, an omitted owner-confirmation
    blocker, and insufficiently bounded compact-shell claims. The current
    final5 archive, explicit owner-pending wording, compact-iPhone evidence, and
    narrowed supported-local matrix resolve those findings. Its follow-up found
    only two ledger omissions: final hygiene and the physical landscape gate;
    both are now explicit below.
  - A final read-only code/spec/ledger review after the signed-local archive and
    cleanup found no remaining actionable P1 or P2 issue across production
    Swift, DEBUG-only route isolation, privacy, keyboard isolation,
    accessibility, verifier behavior, or evidence claims.
- Final local checks
  - `git diff --check`: passed after the final ledger reconciliation.
  - Run-owned cleanup: passed. The two dedicated qualification Simulators
    (`ADF05678-789A-4607-B80E-0948B54D5802` and
    `11A58EEC-B52F-4ABE-9642-27D157FE73E7`) and the two run-owned HoldType
    DerivedData roots were removed. No package `.build` root remained. QA logs,
    result bundles, screenshots, verifier JSON, and the current Organizer input
    archive were preserved as the evidence named in this record; unrelated
    Simulator and sibling-repository DerivedData state was not changed.

### Built-Bundle Contract

The Release inspection must fail closed if any required artifact is absent or
if an app-only capability leaks into the extension.

Containing app:

- the processed plist contains exactly the approved microphone purpose string;
- it contains no Speech-recognition purpose string and no audio background
  mode;
- `PrivacyInfo.xcprivacy` is embedded and declares no tracking or tracking
  domains;
- Audio Data and Other User Content are declared for App Functionality and are
  conservatively linked to the user;
- File Timestamp reason `C617.1` is present, while System Boot Time reason
  `35F9.1` is absent unless an Xcode privacy report first proves a covered API;
- the compiled asset catalog and AppIcon are present;
- the embedded keyboard extension has the expected identifier, executable,
  extension point, and signature;
- no internal Phase-0 bridge-probe view, route, copy, or accessibility element
  is reachable or represented in the Release UI.

Keyboard extension:

- the processed plist remains a keyboard service and does not request
  microphone, Speech recognition, or background audio;
- `RequestsOpenAccess` remains `false` for Phase 0;
- its privacy manifest declares no tracking domains, collected data, or
  required-reason API category;
- the binary and link graph remain limited to keyboard UI and the local
  read-only bridge boundary, with no app-only package, provider, Keychain,
  microphone/audio-capture, raw-audio, History, or diagnostics dependency;
- Release strings and symbols do not imply an implemented voice command,
  automatic app return, Full Access verification, or production typing engine.

The Xcode privacy report belongs to P4D-5A. The physical App Privacy Report
belongs to P4D-5B.

The current local archive needed by Organizer exists at
`/tmp/HoldType-iOS-P4D5-final5.xcarchive`; its successful build is recorded in
`/tmp/p4d5-ios-archive-final5.log` after the final5 production and DEBUG-only
qualification code. The automated Organizer attempt stopped
before any UI action because the Mac was locked and Computer Use could not
unlock it. Therefore no Xcode privacy-report result is claimed here. Resume by
opening that archive in Xcode Organizer and generating the report after the Mac
is manually unlocked; any unexpected category reopens the manifest contract.

### Local Runtime And Accessibility Matrix

Use deterministic state injection or controllable fakes. Do not request real
microphone permission, activate a real audio session, contact OpenAI, read or
write a live Keychain item, accept or withdraw durable provider consent, or
publish Voice data to App Group merely to populate a screen.

Using supported Simulator controls, cover on an iPhone compact shell and an
iPad regular-width split shell:

- setup and blocked preflight;
- arming, listening, finalizing, provider processing, output processing, and
  saving-result presentation;
- recover/discard and retry/discard states;
- accepted active result plus independent Latest Result actions;
- Privacy status, full provider disclosure, and exact confirmation dialogs;
- light and dark appearance, maximum supported Dynamic Type, Increase Contrast,
  and portrait layout;
- readable action stacking, scrolling, focus order, headings, labels, values,
  hints, and non-color status communication;
- content-free transition announcements without duplicate announcements and
  without announcing listening elapsed time every second.

Source inspection must confirm that the slice adds no custom animation whose
behavior would bypass the system Reduce Motion environment. Actual Reduce
Motion and landscape rendering are part of P4D-5B because the installed public
headless Simulator tools do not expose supported controls for either state; do
not manufacture local evidence with private preferences or GUI automation.
Simulator and local accessibility inspection do not satisfy the manual
VoiceOver, Voice Control, Switch Control, or Full Keyboard Access device gate.

## Forward-Only / No-Downgrade Release Rule

The current app-private stores include two persisted values whose protection an
older binary does not understand completely:

- `pendingReplacement` is store-minted authority for recovery of an atomic
  accepted-output replacement. An older decoder preserves the record as
  unreadable and cannot reach its normal expiry or cleanup.
- `retryOperation` binds failed-History Retry ownership and delivery protection.
  A binary that does not enforce that relation cannot safely recover or clean
  it.

Any build capable of writing either value is a no-downgrade release until a
separately specified compatible recovery path exists. Operational rollback
must not install or direct users to a binary that cannot decode and enforce
every such value the newer build can write. Downgrade is never a cleanup,
expiry, or recovery procedure.

P4D-5A may mark this gate passed only after release notes and rollback guidance
state that forward-only rule, the exact first affected build is recorded, and
the release owner confirms that an older binary is not an approved fallback.
The 24-hour accepted-output lifetime does not make downgrade safe because the
older binary cannot parse `pendingReplacement` to execute expiry.

- First release/build capable of writing `pendingReplacement`: current
  unreleased HoldType iOS `1.0` (`1`) source at and after commit `a4c9355`.
- First release/build capable of writing `retryOperation`: current unreleased
  HoldType iOS `1.0` (`1`) source at and after commit `02e1e1c`.
- Release-note/rollback-policy evidence:
  `docs/release/ios-no-downgrade.md`. No iOS build has been distributed; the
  first actual TestFlight/App Store version and build must be added to that
  document before upload.
- Compatibility tests and artifact evidence: strict
  `IOSAcceptedOutputDeliveryJournalTests`, `IOSFailedHistoryJournalTests`,
  `IOSAcceptedHistoryCoordinatorTests`, and
  `IOSFailedHistoryRetryRecoveryTests` are included in the 1,097-test
  Persistence pass and the 1,915-test iOS pass above.
- Gate decision: Pending explicit release-owner confirmation. The repository
  policy forbids an older iOS binary as a fallback, and the distributed-build
  ledger remains a required pre-upload action; this engineering record does not
  impersonate the release owner's approval.

## P4D-5B — Signed Physical-Device Gate

Record device model, OS build, app build/commit, signing identity or team,
configuration, permission state, route/accessory, expected result, actual
result, and pass/fail decision for every physical pass. Redact credentials,
transcripts, route UIDs, file paths, and other payloads from this record.

### P4D-2C Recorder And Foreground-Audio Matrix

- On a short real recording, prove exact source inode, owner, mode, link count,
  path agreement, required xattrs, Complete protection, and backup policy after
  recorder initialization, after `prepareToRecord()`, during recording where
  observable, and after close.
- Exercise first explicit microphone request, authorized start, denial, revoked
  permission, and the public Settings-route recovery. Passive presentation must
  not prompt.
- Verify built-in input plus each available wired or Bluetooth/HFP input. Freeze
  the selected input tuple; input loss, mute, or change must stop safely, while
  an output-only change may continue only when the frozen input and recorder
  validity remain proved.
- Exercise interruption start/end, route loss, input mute, app backgrounding,
  lock, scene loss, and available calls/Siri/alarms/media-services reset cases.
  Capture must never continue invisibly and must never auto-resume.
- Verify the start cue completes before retained capture, the success stop cue
  starts only after recorder close, disabled cues remain disabled, and cancel or
  interruption produces no success cue. The system microphone indicator and
  visible Voice state must agree with actual capture.
- Verify explicit Done, Cancel, expiry/watchdog, valid partial, too-short or
  invalid partial, blocked local recovery, and bounded finalization. The named
  background assertion must end, must not keep the microphone alive for network
  work, and must preserve the furthest durable source or Pending checkpoint on
  expiration.
- If the `AVAudioRecorder` source-identity proof fails at any point, P4D-2C and
  P4D-5B fail. Select a descriptor-backed AudioToolbox/AVAudioEngine writer
  rather than weakening the storage contract.

### Effective Data Protection And Keychain

- On the signed device, inspect effective protection and backup behavior for
  representative settings, Library, Usage, source audio, Pending, accepted
  output, and failed-History/retry artifacts according to each owning spec.
  Simulator evidence that Complete protection was merely requested is not
  sufficient.
- Verify protected data does not become optimistic absence or corruption while
  the device is locked; the UI must expose blocked local recovery where the
  owning contract requires it.
- With a non-secret test value, verify the app-only generic-password item uses
  service `app.holdtype.HoldType.ios`, account `openai-api-key`,
  `WhenUnlockedThisDeviceOnly`, non-synchronizable storage, and only the
  containing app's signed application-identifier access group.
- Verify locked-device Keychain access fails locally and redacted, later unlock
  permits the explicit recovery path, passive status performs no read, and the
  keyboard cannot access the item. Do not use or record a production API key.

### Physical Privacy And Accessibility

- Generate the physical App Privacy Report after the bounded scenario. Confirm
  that any observed network/data access stays within the declared provider path
  and that no unexpected analytics, tracking, host-text, keyboard, or content
  destination appears. If the scenario intentionally performs no live provider
  request, record that limitation instead of manufacturing traffic.
- Manually traverse Voice, Latest Result, Privacy, provider disclosure,
  confirmations, and practice flow with VoiceOver. Verify order, headings,
  labels, values, hints, actions, state announcements, and recovery access.
- Repeat the actionable flow with Voice Control, Switch Control, and Full
  Keyboard Access. No action may depend on color, waveform, drag, or speech
  alone.
- Verify maximum Dynamic Type, Dark Mode, Increase Contrast, and Reduce Motion
  in portrait and landscape on every physical form factor included in the gate
  where the device supports those orientations. Record an unavailable form
  factor or orientation as pending rather than inferring its behavior from
  Simulator.

Open physical risk — VoiceOver audio contamination:

- A listening-state VoiceOver announcement can overlap the transition into
  retained capture. Simulator routing cannot prove whether built-in speaker
  speech, a start cue, or route negotiation is picked up by the microphone.
- Run one VoiceOver Start and short recording with built-in speaker output, then
  repeat with each available wired or Bluetooth headset/HFP route. Inspect the
  retained artifact or controlled result locally without putting its content in
  logs or this record.
- Expected: no VoiceOver announcement or boundary cue contaminates retained
  audio, the frozen input route remains valid, capture state is announced
  without per-second chatter, and Stop remains immediately reachable.
- If announcement speech or cue audio is retained, routing changes unexpectedly,
  or announcement timing makes Start/Stop ambiguous, P4D-5B fails. Do not waive
  the result as an accessibility-only issue; sequence the announcement before
  retained capture or adopt another accessible feedback design, then repeat
  both speaker and headset cases.

### Bounded App-Only Start-To-Outcome Scenario

Run one explicit Start through either a confirmed accepted result or a visible,
durable recovery outcome. The gate does not require a live OpenAI call.

- Use a release-equivalent signed QA configuration and a controllable provider
  boundary. Do not silently substitute a production credential or uncontrolled
  live request.
- Prove explicit consent and permission ordering, visible microphone lifetime,
  one protected completed artifact, Pending journaling before any provider
  dispatch, bounded Stop/finalization, and either exact Latest Result authority
  or Recover/Retry/Discard authority after interruption or controlled failure.
- Relaunch or foreground-reconcile the chosen recovery case and verify that the
  completed recording does not become an invisible orphan or auto-upload.
- Confirm no external-app insertion, keyboard Voice command, Quick Session,
  background-audio declaration, or automatic return is involved.

### Physical Evidence Ledger

- Device model and OS build: Pending
- App build/commit/configuration/signing: Pending
- Permission and route states: Pending
- P4D-2C identity evidence: Pending
- Foreground audio/interruption/lock/finalization evidence: Pending
- Data Protection evidence: Pending
- Keychain accessibility/isolation evidence: Pending
- App Privacy Report: Pending
- VoiceOver built-in-speaker result: Pending
- VoiceOver wired/Bluetooth headset result: Pending
- Voice Control result: Pending
- Switch Control result: Pending
- Full Keyboard Access result: Pending
- Appearance, maximum Dynamic Type, Increase Contrast, Reduce Motion, and
  portrait/landscape result: Pending
- App-only Start-to-result-or-recovery result: Pending
- P4D-5B gate decision: Pending

## Final Gate Decision

- P4D-5A local technical Release gate: Pending only the Xcode Organizer privacy
  report and explicit release-owner confirmation
- P4D-5B signed physical-device gate: Pending
- P4D-5 overall: Open
- P4 overall: Open

The overall decision may change to passed only when both checkpoint decisions
are passed and their evidence is linked above. Missing signing, device,
accessibility, privacy-report, or recorder-identity evidence remains `Pending`;
it is never inferred from Simulator behavior or an otherwise successful Release
build.

## Contract Sources

- `docs/ios-product-portability-plan.md`
- `docs/ios-keyboard-development-plan.md`
- `docs/release/ios-no-downgrade.md`
- `docs/specs/features/ios-accepted-output-delivery-record.md`
- `docs/specs/features/ios-failed-history-and-retry-audio.md`
- `docs/specs/features/ios-privacy-and-permissions.md`
- `docs/specs/features/ios-settings-and-secret-storage.md`
- `docs/specs/features/ios-voice-session-and-audio.md`
- `docs/specs/features/ios-containing-app-experience.md`
- `docs/specs/features/ios-keyboard-feasibility.md`
- `docs/specs/features/ios-keyboard-experience.md`
