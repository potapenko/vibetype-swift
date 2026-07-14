# HoldType iOS V1.1 Completion Plan

Status: canonical execution plan; reduced, reprioritized, and updated for Brand
Stage Adaptive and the restricted keyboard boundary on 2026-07-14.

Product behavior is governed by
`docs/specs/features/ios-v1-release.md`. Historical P0-P8, P5H, accepted-
History, and failed-History documents are evidence only. They are not active
implementation queues.

## Outcome

Finish the visible iPhone product without another architecture expansion:

- foreground Voice with Pending and Latest Result;
- Library and core Settings;
- compact successful-text History;
- one production Brand Stage Adaptive voice-command keyboard;
- explicit keyboard Latest insertion, History app navigation, and an honest
  decision on keyboard voice activation;
- signed-device qualification.

The user explicitly reprioritized working History ahead of the keyboard device
gate. K1 still gates keyboard-plus-voice release claims, but it did not block
finishing app-private History.

## Current Product State

Working and retained:

- foreground Voice, Done, Cancel, Retry, Discard, and Latest Result actions;
- always-on, non-expiring app-private Latest Result;
- compact, app-private History for up to 20 successful texts, including list,
  detail, Copy, Share, Delete, Clear All, and the default-on `Save History`
  control;
- Dictionary, Voice Emoji Commands, and Replacement Rules;
- API key, transcription, correction, translation, recording, privacy, and
  Usage Estimate settings;
- containing-app practice field and the Brand Stage extension with punctuation,
  cursor Space, Delete repeat, adaptive Return, Globe, Light/Dark styling, and
  explicit Latest insertion;
- one production app-written, extension-read-only schema 3 snapshot containing
  at most one 10-minute Latest item;
- the real containing-app History route plus a keyboard History request whose
  App Review and device result remain separately gated.

Remaining release work:

1. Current Apple documentation does not qualify containing-app launch as a
   supported custom-keyboard action, and App Review 4.4.1 forbids keyboard
   extensions from launching apps other than Settings. That blocks a production
   HoldType microphone handoff and also leaves the requested History launch
   unqualified.
2. The production Latest path is implemented without Full Access, and the
   canonical Latest -> App Group -> real-keyboard insertion E2E is complete on
   iOS 18.6 Simulator. Matching App Group signing, restricted-mode reading,
   insertion, and process eviction still require a signed physical-iPhone pass.
3. Real-host editing behavior, signed-device accessibility settings, and the
   remaining physical-iPhone matrix require runtime evidence.

## Execution Rules

- Build user-visible vertical slices; do not restore P5H capability families.
- Keep the working Voice/Pending path until its replacement is proven.
- Use one actor and one atomic record for compact History.
- History failure never changes a successful Latest Result into a failed
  dictation and never blocks Pending/audio cleanup.
- Delete legacy code only after the replacement has no production dependency
  on it.
- Each implementation checkpoint reports production and test line movement.
- Work only on `master`, preserve unrelated changes, and commit scoped paths.

## H1 — Compact History Repository

Create one app-private atomic record:

```text
schemaVersion
enabled
entries[0...20]
  resultID
  text
  createdAt
```

Required operations:

- load the confirmed record, defaulting a new install to enabled and empty;
- idempotently append by `resultID`, newest first, capped at 20;
- delete one exact entry;
- clear all while preserving enabled state;
- enable future appends;
- disable and clear in one atomic replacement.

The actor serializes all mutation. The file is protected, backup-excluded,
bounded, strict-schema JSON. Corruption and I/O failure are errors, not an empty
successful History.

Verification:

- missing, valid, corrupt, oversized, and unsupported records;
- cap, ordering, idempotent append, delete, clear, enable, disable-and-clear;
- atomic write failure leaves the previous confirmed record unchanged;
- concurrent mutations are serialized.

Exit: the compact repository passes independently and no UI or Voice path uses
legacy History policy, generation, outbox, failed rows, or retry audio.

## H2 — Production Append And Latest Semantics

Connect compact History immediately after successful Latest acceptance:

1. Latest remains the mandatory durable destination.
2. If compact History is enabled, append the accepted `resultID`, final text,
   and creation date idempotently.
3. If append fails, return success with a nonblocking local History warning.
4. Complete exact Pending/audio cleanup regardless of History outcome.

Also align Latest with V1.1:

- Latest is always on;
- remove the iOS `keepLatestResult` control and ignore its persisted value;
- remove the 24-hour Latest expiry without changing the short-lived Latest item
  inside the keyboard App Group snapshot;
- do not change macOS behavior.

Verification:

- Voice success produces Latest plus one History entry;
- the same result never duplicates;
- History disabled produces Latest only;
- History write failure still produces Latest and a warning;
- Retry/reconciliation never repeats provider work merely to append History.

Exit: a real successful containing-app dictation can create a compact History
entry, and Latest follows the canonical no-expiry, always-on contract.

## H3 — Finished History Surface

Replace the placeholder with one process-owned observable History owner and a
native SwiftUI surface.

Screen states:

- loading;
- disabled, with an explicit Enable action;
- empty: `No History Yet`;
- newest-first list;
- load failure: `History Unavailable` with Retry;
- nonblocking mutation warning while retaining the last confirmed list.

User actions:

- open full text detail;
- Copy and Share;
- Delete one entry;
- confirmed Clear All;
- default-on `Save History` control;
- confirmed disable-and-clear;
- re-enable for future results only.

Update Setup, Privacy, and provider disclosure copy to state that up to 20
successful texts are stored locally when `Save History` is on. Remove claims
that History is absent or includes failed attempts.

Verification:

- owner state and stale-command tests;
- view/presentation tests for every state and confirmation path;
- compact-iPhone and iPad compatibility rendering;
- Simulator flow: create result -> History list -> detail -> Copy/Share ->
  Delete -> Clear All -> disable -> re-enable -> future append.

Exit: Release navigation contains a useful History destination and never shows
the old unconditional unavailable text.

## H4 — Bounded Legacy Cleanup

After H1-H3 are green:

- remove old accepted/failed History services from production composition;
- stop failed-History scratch and accepted/failed recovery scheduling;
- remove only leaf source/test families with no surviving production consumer;
- retain the current Pending/Latest machinery until a smaller replacement is
  separately proven;
- remove superseded History policy/generation/outbox/failed-row tests together
  with the deleted code rather than porting them.

Exit:

- production composition owns only compact successful-text History;
- no failed-attempt History, retry-audio, policy-generation, or outbox service
  starts with the app;
- the cleanup checkpoint is materially net-negative in source and test lines;
- macOS and iOS remain green.

Completion evidence, 2026-07-13:

- production composition no longer starts the legacy accepted/failed History
  coordinator or failed-History retry providers;
- compact History repository, Voice acceptance, state owner, settings, and
  presentation paths pass their focused tests;
- signed iPhone and iPad Simulator builds launch with the sanitized automation
  environment; external UI acceptance verified the populated newest-first
  list and detail on both form factors, exact Copy output, Share presentation,
  and the non-destructive Clear confirmation path;
- macOS plus generic iOS builds succeed;
- H1-H4 changed 58 files with 2,833 insertions and 6,810 deletions: a net
  reduction of 3,977 lines;
- the broad persistence run executed 1,118 tests and reported 18 pre-existing
  issues in untouched legacy/timing paths; each timing-sensitive case passes
  in isolation, and no observed issue exercises the H4 changes.

The remaining deep persistence interlocks used by Pending and Latest are not a
user-visible History service. Their replacement and deletion now follow the
approved bounded plan in `docs/ios-v1-persistence-simplification-plan.md`.

## P1-P6 — Persistence Simplification And Legacy Retirement

Replace the active Pending/Latest compatibility graph with one compact
voice-state owner, detach capture and provider consent, prove zero production
references, and then delete the accepted/failed History, retry-audio, outbox,
generation, old delivery, and transaction-support families.

The focused execution order, complexity budget, deletion manifest, stop
conditions, and verification gates are defined in
`docs/ios-v1-persistence-simplification-plan.md`. This cleanup precedes K1 so
the keyboard work builds on the intended V1.1 persistence boundary.

Completion evidence, 2026-07-13:

- the private persistence lab is preserved at archive commit `b684741` and tag
  `archive-2026-07-13`;
- production now owns one compact Pending/Latest record, exact capture audio,
  standalone provider consent, and separate compact successful-text History;
- relaunch performs local reconciliation only, while provider Retry and
  Discard remain explicit user actions;
- `HoldTypePersistence` moved from 79 source and 55 test files to 23 source and
  12 test files;
- package Swift moved from 66,064 source plus 66,898 test lines to 9,254 source
  plus 8,030 test lines, a net reduction of 115,678 lines;
- the deletion checkpoint removed 107 obsolete files and 122,165 lines before
  the compact replacement was accounted for;
- the iOS scheme moved from 1,957 tests before deletion to 990 focused and
  surviving tests, all passing; package tests pass 193 plus 53;
- iOS Debug/Release, release-bundle isolation, and macOS builds pass; physical
  Data Protection, eviction, and App Group entitlement claims remain device
  gates.

## K1 — Voice Activation Platform Gate

Documentation result, 2026-07-13: **not qualified for production**.

- custom keyboard extensions have no microphone access;
- `NSExtensionContext.open` is public, but iOS support is documented for Today
  and iMessage extension points rather than custom keyboards;
- App Review Guideline 4.4.1 says keyboard extensions must not launch apps other
  than Settings;
- no public host-identity or automatic-return contract exists.

A one-way custom URL may work on some iOS versions, but a signed device pass
would prove only technical behavior, not App Review compatibility. The
containing app may register and verify its public History route, and the
selected keyboard keeps the user-required History control. Production uses no
responder-chain trampoline, private selector, automatic-return claim, or
fabricated recording state. The keyboard-originated History launch and the
keyboard-plus-voice release claim require Apple clarification or explicit
acceptance of the remaining release risk after bounded device evidence.

## K2 — Production Brand Stage Adaptive

Replace the probe with the selected composition while keeping the unresolved
voice stage visibly unavailable and non-interactive:

- top rail with History, centered HoldType identity/status, and Latest;
- one medium branded microphone stage with no fake action or optimistic state;
- `.`, `,`, `?`, and `!` correction keys;
- Globe, wide Space, Delete repeat, and adaptive Return;
- long-press and drag cursor movement on Space;
- identical geometry with system-adaptive Light and Dark materials;
- 44-point targets, VoiceOver, Reduce Motion, Increase Contrast, and Dynamic
  Type-safe labels;
- removal of `A`, manual Refresh, and the giant Insert Latest probe control.

K2 adds no alphabet, number deck, Shift/Caps, predictions, autocorrection,
keyboard dictionaries, or locale-layout engine. The microphone remains
non-interactive while K1 is unresolved. Result actions remain honestly gated by
K3 state while local editing and Globe keep working.

## K3 — Latest Snapshot And History Route Qualification

- publish one real accepted Latest with a 10-minute expiry to one bounded
  app-written, extension-read-only App Group snapshot;
- omit already-expired results and replace legacy schema 1/2 payloads with an
  empty current-schema cache at app startup;
- declare `RequestsOpenAccess = false`; the extension reads the app-written
  snapshot in Apple's restricted keyboard sandbox and never writes to App Group;
- keep full 20-entry History and every destructive History action app-private;
- keep the projection as one replaceable cache with one app writer; add no
  outbox, receipt, acknowledgement, tombstone, or delivery transaction;
- implement explicit one-call-per-tap insertion for Latest with no automatic
  replay;
- register and test the containing-app History route, wire the keyboard History
  control through public extension APIs only, and record the separate
  device/review qualification result;
- finalize setup, restricted-access privacy, and fallback copy;
- run Debug/Release dependency checks, simulator appearance/accessibility checks,
  and the signed physical-iPhone matrix;
- perform one explicitly authorized live Standard smoke only when a configured
  provider key is available.

## Explicitly Deferred

- failed-attempt History and retry audio;
- accepted audio playback or Recording Cache;
- background Quick Session and Live Activity;
- QWERTY, alphabet/number layouts, predictions, autocorrection, and typing
  dictionaries;
- production iPad floating keyboard and Stage Manager qualification;
- cloud sync, accounts, analytics, profiles, modes, and billing.

## Completion Dashboard

| Slice | Status |
| --- | --- |
| R0 Scope reset and stable baseline | Completed 2026-07-13 |
| H1 Compact History repository | Completed 2026-07-13 |
| H2 Production append and Latest semantics | Completed 2026-07-13 |
| H3 Finished History surface | Completed 2026-07-13 |
| H4 Bounded legacy cleanup | Completed 2026-07-13 |
| P1-P6 Persistence simplification and legacy retirement | Completed 2026-07-13 |
| K1 Voice activation platform gate | Not qualified for production, 2026-07-13 |
| K2 Production Brand Stage Adaptive | Engineering complete; portrait/iPad and compact-landscape runtime evidence complete, signed-device host/accessibility gates pending 2026-07-14 |
| K3 Latest snapshot and History route qualification | Canonical Latest E2E complete on Simulator; History review risk and signed-device host/device gates pending 2026-07-14 |

Compact History, the non-interactive Brand Stage voice core, and explicit Latest
insertion are complete in code. The requested best-effort History request remains
an explicit review risk, and the signed-device gates are unresolved.
