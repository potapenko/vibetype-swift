# HoldType iOS V1.1 Scope Reset Audit

Status: approved scope reset; 2026-07-13.

This audit replaces the assumption that the full P0-P8 portability roadmap
should continue in its current order. It records the current product, the
architecture imbalance, and the parts that V1.1 will keep, simplify,
quarantine, or remove.

The release contract is `docs/specs/features/ios-v1-release.md`. The executable
roadmap is `docs/ios-v1-development-plan.md`. This audit preserves the old
baseline snapshot; the later Brand Stage Adaptive decision replaces its implied
full-typing keyboard direction.

## Baseline And Limits

- Audit baseline: committed `master` at `b50645a`.
- The two uncommitted P5H-2 edits in
  `IOSFailedHistoryTransfer.swift` and `IOSForegroundVoicePersistence.swift`
  are stopped work in progress and are not part of the product baseline.
- Fresh runtime evidence was captured from the committed baseline on an iPhone
  16 simulator running iOS 18.6.
- Simulator evidence proves rendering and navigation only. Keyboard
  enablement, App Group behavior, microphone behavior, process eviction, host
  rejection, and secure fields still require a signed physical iPhone.
- This audit changes no macOS product behavior.

## Executive Decision

The current iOS product already has a useful containing app: foreground Voice,
Latest Result, Library, and Settings. Development lost focus by building a
large, hidden History transaction system before building the keyboard that
motivated the iOS product.

V1.1 therefore stops P5H and does the following:

1. preserve the working app and portable provider code;
2. immediately prove the signed-device keyboard-to-app voice handoff;
3. replace hidden History machinery with a small accepted-text history;
4. retain only one recoverable pending recording;
5. build one usable iPhone keyboard with a dedicated voice action;
6. defer failed-attempt History, retry audio, background Quick Session, and
   advanced iPad keyboard work;
7. reduce code and tests before expanding the product again.

## Current Product Evidence

| Step | Current user experience | Health | V1.1 decision |
| --- | --- | --- | --- |
| Voice | Native foreground dictation, Standard and Translate entry points, Latest Result, Copy, Share, Practice, and Clear | Useful and visible; physical microphone flow is not yet qualified | Keep and simplify |
| Library | Dictionary, Voice Emoji Commands, and Replacement Rules have native editors and durable app-private storage | Useful and visible | Keep |
| History | The selected tab says `History Unavailable` | Placeholder; no user value | Replace |
| Settings | API key, transcription, correction, translation, recording, privacy, and usage routes exist | Core settings and current Usage Estimate are useful | Keep and smoke-test current routes; stop expanding Usage |
| Keyboard | Phase-0 controller exposes one `a` key, Space, Delete, Globe, Refresh, and Insert latest | Not a usable keyboard | Replace |
| Keyboard voice bridge | The only app writer of a keyboard transcript is a DEBUG practice probe | No production voice handoff | Replace |

Runtime screenshots from this audit are stored outside the repository in
`/tmp/holdtype-v1-audit-2026-07-13/`. They are supporting evidence, not a
release qualification artifact.

## Scale

The committed baseline contains approximately:

- 123,600 production Swift lines;
- 121,400 test Swift lines;
- 2,417 Swift Testing `@Test` declarations;
- 65,865 production and 67,344 test lines in `HoldTypePersistence` alone.

From the pre-goal commit `d7a1bb4` to the audit baseline:

- 255 commits changed 626 files;
- the final tree difference is `+247,641 / -4,346` lines;
- the central keyboard controller remained 199 lines.

The approximately 2.4 GB checkout size is mostly build output. Tracked source
is much smaller. The architectural problem is still real: the repository has
roughly 245,000 tracked Swift lines, split almost one-to-one between production
and tests.

## Main Imbalance

Name-based inventory of accepted History, failed History, and History policy
code finds approximately:

- 39,376 production lines;
- 45,581 test lines.

This hidden stack creates policy generations, outboxes, leases, receipts,
capabilities, pending replacement, retry-audio ownership, cleanup tombstones,
and process-loss recovery. Production still shows a History placeholder and
uses provider disclosure version 1.

The one-recording Pending/capture/protected-audio subsystem adds approximately
19,008 production and 11,835 test lines. Foreground Voice orchestration adds
another roughly 17,500 production lines before the consent layer.

These are not isolated quality improvements. They displaced the release path:
the app has no production keyboard bridge, and the keyboard cannot perform
ordinary QWERTY typing.

## Keep

- `HoldTypeDomain` and its portable text-processing models.
- `HoldTypeOpenAI`, including bounded file-backed upload, explicit timeouts,
  cancellation, and reader-based requests.
- The iPhone app shell and existing iPad containing-app adaptation as
  best-effort compatibility, not a release-qualified V1.1 surface.
- Voice, Latest Result, Dictionary, Voice Emoji Commands, Replacement Rules,
  and the core Settings editors.
- API-key ownership in the containing-app Keychain.
- The extension isolation boundary: no API key, OpenAI client, prompt,
  dictionary, or raw audio in the keyboard target.
- These safety invariants:
  - a completed recording is recoverable before provider work starts;
  - stopping recording releases the microphone promptly;
  - uncertain provider work is never replayed automatically;
  - one unresolved pending attempt blocks a second recording;
  - secrets and raw audio never enter App Group storage.

## Simplify

### Pending Recording

Replace the current subsystem with one actor-owned repository containing:

- one protected audio file;
- one compact metadata record;
- the product states `ready`, `processing`, and `failed`;
- explicit `retry`, `discard`, and `complete` operations;
- atomic metadata publication, file protection, and backup exclusion.

Target size is 3,000-4,000 production lines and 2,000-3,000 focused test lines,
not a fault permutation for each filesystem micro-step.

### Latest Result

Keep one app-private atomic accepted-text record with `resultID` and
`sourceAttemptID`. It supports Load, Replace, and Clear, is always on, and no
longer expires after 24 hours. Only the keyboard snapshot expires. Latest does
not need an accepted-History outbox, policy generation, or captured foreground
capability.

### History

Replace the current stack with one app-private text repository:

- at most 20 newest accepted entries;
- identifier, accepted text, and creation date;
- Copy, Share, Delete, and Clear All;
- one actor serializing append and mutation;
- default-on local saving with clear setup/privacy disclosure and confirmed
  disable-and-clear behavior;
- no accepted audio;
- no failed rows, retry audio, outbox, generations, receipts, or tombstones.

An append failure never changes a successful Voice result and never repeats a
provider request.

### Voice And Consent

Converge on two primary owners:

- a `@MainActor` presentation model for user-visible state;
- one actor/service for recording, provider processing, Pending, Latest, and
  accepted-text History.

Use a few typed clients instead of dozens of closure dependencies. Provider
consent needs one versioned accepted/revoked record checked before each remote
stage; it does not need to share a transaction protocol with History.

### Tests

- Run package tests in their packages.
- Keep `HoldTypeIOSTests` for platform composition, navigation, and a few
  end-to-end smokes rather than recompiling every package test source.
- Test semantic commit boundaries and user-visible recovery, not every
  internal capability combination.
- A test must protect a product invariant or a plausible regression.

## Quarantine For A Later Product Decision

The following families must leave the active production graph before they are
deleted. Git remains the historical source; no duplicate archive branch is
needed.

- `IOSAcceptedHistory*` in its current transactional form;
- `IOSAcceptedOutputDelivery*` capabilities used only by P5H;
- `IOSFailedHistory*` and retry-audio ownership;
- `IOSHistoryPolicy*`, outbox, policy cutover, and pending replacement;
- captured foreground History mode and its disclosure-v2 activation train;
- failed-History scratch maintenance and lifecycle recovery;
- background Quick Session and keyboard-to-app command machinery;
- advanced retained-audio cleanup and Recording Cache;
- production iPad floating keyboard, Stage Manager, and hardware-keyboard
  extras;
- diagnostics export and exhaustive crash-permutation work.

## Remove Or Replace

- The stopped uncommitted P5H-2 WIP.
- The local P5H-2 checkpoints `053fa33` and `b50645a`, through a normal forward
  cleanup or revert commit after the scope-reset checkpoint; history must not
  be rewritten.
- The 18-line History placeholder after the compact History screen exists.
- DEBUG-only keyboard bridge publication after production publication exists.
- Dead prototype/session models with no production caller.
- Duplicate inclusion of package test sources in the iOS application test
  target.
- Internal diagnostic descriptions and capability wrappers that have no
  surviving V1.1 consumer.

## Size Direction

Line count is a smoke alarm, not the definition of quality. The expected result
of this reset is nevertheless material:

- after legacy persistence and orchestration removal, approximately
  60,000-65,000 production and 55,000-60,000 test Swift lines;
- after the production keyboard and its focused tests, approximately
  65,000-72,000 production and 60,000-68,000 test Swift lines;
- a reduction near one half while retaining the working app features.

If a simplification checkpoint increases total Swift substantially, it must
explain why the user-visible V1.1 path became more complete.

## Audit Conclusion

The product is not blocked by a missing History edge case. It is blocked by
priority inversion. R0 must first restore a compiling committed baseline. The
next product checkpoint is then the bounded signed-device handoff probe, before
another persistence rewrite. Only a positive handoff result allows the compact
V1.1 vertical slice to continue. No new History capability, recovery generation,
or background-session state may be added.
