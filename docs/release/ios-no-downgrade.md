# iOS Forward-Only Release Policy

This policy applies to the HoldType iOS containing app and its embedded
keyboard extension. It does not change the macOS Sparkle release policy.

## Current Boundary

The current iOS source can persist two values that older iOS binaries may not
decode or enforce safely:

- accepted-output History state `pendingReplacement`, introduced by source
  commit `a4c9355`;
- failed-History `retryOperation`, introduced by source commit `02e1e1c`.

The first build currently capable of writing both values identifies itself as
iOS version `1.0`, build `1`. No HoldType iOS build has been distributed yet.
Before the first TestFlight or App Store upload, the release owner must record
the actual uploaded version/build here; that build inherits this policy even
if its number changes during signing or distribution preparation.

The existing `v1.0.0` through `v1.0.3` tags are macOS releases and are not
compatible rollback destinations for iOS data.

## Rollback Rule

Do not install, distribute, or direct a user to an iOS binary that predates
either source boundary required by a value already writable in that user's app
container. In particular, a binary between `a4c9355` and `02e1e1c` understands
`pendingReplacement` but not `retryOperation`, so it is not a valid rollback
from the current build. Reinstalling an older binary, restoring an older
TestFlight build, or treating the 24-hour accepted-output lifetime as cleanup
is not an approved recovery procedure.

An older decoder may preserve the store as unreadable and therefore cannot
perform the current expiry, cleanup, retry, or exact recovery contract. If a
release must be withdrawn, ship a forward fix that still understands and
enforces every persisted value already writable by the withdrawn build.

Downgrade may be allowed only after a separate compatibility spec and tests
prove a migration or recovery path for both values. Until then, the policy is
forward-only.

## Release Checklist

For every TestFlight or App Store build that can write either value:

1. Record the version, build number, source commit, and distribution channel
   below before upload.
2. Keep the strict wire-codec and recovery suites green, including
   `IOSAcceptedOutputDeliveryJournalTests`, `IOSFailedHistoryJournalTests`,
   `IOSAcceptedHistoryCoordinatorTests`, and
   `IOSFailedHistoryRetryRecoveryTests`.
3. State in internal rollback notes that an older iOS binary is not an
   approved fallback.
4. Use a forward build for incident recovery; never delete or reinterpret an
   unreadable store merely to make rollback appear successful.

## Distributed Build Ledger

No iOS build distributed yet.

| Version | Build | Commit | Channel | Forward-only values |
| --- | --- | --- | --- | --- |
| Pending first upload | Pending | Pending | TestFlight/App Store | `pendingReplacement`, `retryOperation` |
