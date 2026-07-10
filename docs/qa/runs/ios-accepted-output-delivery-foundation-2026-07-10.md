# iOS Accepted Output Delivery Foundation QA

Date: 2026-07-10
Milestone: P2 app-private accepted-output delivery checkpoint

## Scope

- Commit one accepted transcript before History or keyboard publication.
- Preserve exact text bytes, delivery identity, output intent, captured
  preferences, and pending History ownership for at most 24 hours.
- Make replacement, clear, expiry, duplicate acceptance, process relaunch, and
  uncertain commits deterministic with revision and file-revision CAS.
- Keep the record, History metadata, and all persistence code outside the
  keyboard extension.
- Leave publication generation `0 -> 1`, App Group projection, and insertion
  acknowledgement to the later bridge checkpoint.

## Automated Evidence

- `swift test --package-path Packages/HoldTypePersistence -Xswiftc
  -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 256 tests in 15 suites.
- `swift test --package-path Packages/HoldTypeIOSCore -Xswiftc
  -strict-concurrency=complete -Xswiftc -warnings-as-errors`
  - Result: passed, 29 tests.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test`
  - Result: passed, 441 tests on macOS 26.5.1.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,id=B12CCB99-5B3D-49A5-8CF2-7976C570D2EB' test
  CODE_SIGNING_ALLOWED=NO`
  - Result: passed, 619 tests on iPhone 16 simulator, iOS 18.1.
- `plutil -lint HoldTypeIOS/Info.plist HoldTypeKeyboard/Info.plist
  HoldType/Info.plist`
  - Result: passed.
- `git diff --check`
  - Result: passed before checkpoint commit.

## Durability And Race Evidence

- The strict wire codec enforces the exact 16-field v1 record, explicit nulls,
  canonical UUIDs and millisecond UTC dates, duplicate-key rejection, a 1 MiB
  source cap, and a 128 KiB decoded text cap before Foundation materialization.
- Schema dispatch has bounded headroom, so an ordinary 17-field future schema
  remains `unsupportedSchemaVersion` while an unknown v1 field is invalid v1.
- Exact UTF-8 identity, frozen trimming, forbidden controls, revision overflow,
  impossible state/generation combinations, and redacted public diagnostics are
  covered at their boundaries.
- Identical create/replacement races reconcile with one bounded reload and an
  identical durability rewrite. A different current value remains a typed slot,
  CAS, or identity collision.
- One operation uses one temporal-state branch decision. Clear cannot trap at
  the expiry boundary, pending History cannot be lost after a second clock
  sample, and History authority is revalidated after the confirmation fsync.
- Acceptance confirmation cannot accidentally mint History authority. A live
  duplicate may only weaken `keepLatestResult` from true to false and can never
  restore it.
- Opaque recovery pins exact file identity and can remove malformed metadata
  after the still-deferred bridge-wide revocation proof; normal reads and writes
  continue to require exact protection, backup, mode, and marker configuration.
- Bounded staging maintenance advances a descriptor-relative directory cursor
  across passes. A deterministic 301-name case proves the second pass reaches a
  valid stale staging file beyond the first 256 stable foreign names.

## Extension Isolation Evidence

- The `HoldTypeKeyboard` target has no package dependencies.
- `otool` on `HoldTypeKeyboard.debug.dylib` shows only Foundation, UIKit,
  Objective-C, system, and Swift runtime libraries.
- `nm` finds no `HoldTypeDomain`, `HoldTypePersistence`, `HoldTypeOpenAI`, or
  `HoldTypeIOSCore` symbols in the extension.

## Independent Review

Three read-only reviews covered state-machine/CAS behavior, filesystem and
authorization security, and architecture/target isolation. Their findings led
to the opaque-removal path, single temporal snapshot, post-fsync expiry check,
same-acceptance race reconciliation, bounded value-string preflight, future
schema headroom, and cross-pass staging cursor. A final Store review reported
clean, with no remaining blocking finding.

## Gate Decision

P2 accepted-output simulator/package checkpoint: passed.

This is not physical-device evidence. Signed-device Complete Data Protection,
locked-device availability, force-quit/process eviction, real App Group
projection/revocation, keyboard enablement, Full Access behavior, and actual
`UITextDocumentProxy` insertion remain their named physical gates.
