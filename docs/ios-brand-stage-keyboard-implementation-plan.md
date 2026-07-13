# iOS Brand Stage Keyboard Implementation Plan

Status: active direct-chat execution plan, 2026-07-13.

Product behavior remains governed by `docs/specs/features/ios-v1-release.md`
and `docs/specs/features/ios-keyboard-experience.md`. This file is the bounded
engineering sequence for replacing the Phase-0 probe. It is not a backlog and
does not revive the retired persistence architecture.

## Outcome

Deliver the selected Brand Stage Adaptive command surface with:

- stable Light and Dark compositions;
- local punctuation, Globe, Space cursor movement, Delete repeat, and adaptive
  Return;
- explicit Latest and at most five recent-result insertions;
- one bounded app-written, extension-read-only App Group snapshot;
- honest voice availability with no private or undocumented production launch;
- automated coverage plus Simulator and signed-device evidence where required.

This work does not add QWERTY, alphabet or number layouts, prediction,
autocorrection, keyboard dictionaries, background recording, automatic return,
or automatic text insertion.

## Baseline And K1 Decision

The 2026-07-13 baseline passes:

- `HoldType-iOS` Debug build on the iOS 26.5 iPhone Simulator;
- all six existing `KeyboardBridgeIOSTests`.

The K1 documentation gate does not qualify an actionable production microphone:

- custom keyboard extensions cannot access the microphone;
- `NSExtensionContext.open` is public, but iOS support is documented for Today
  and iMessage extension points, not custom keyboards;
- App Review Guideline 4.4.1 says keyboard extensions must not launch apps other
  than Settings;
- there is no public host-identity or automatic-return contract.

A custom URL may work one-way on some iOS versions, but that does not make it a
documented or review-safe production keyboard API. No physical device is
currently connected, so the signed K1 spike cannot run in this checkpoint.
Production code therefore adds no URL launch, responder-chain trampoline,
private selector, host-bundle discovery, or optimistic `Listening` state. Until
an explicit product rescope or Apple clarification, Brand Stage renders voice as
visibly unavailable and non-interactive. That is not K1 completion.

## Complexity Budget

- Keep UIKit in the extension; add no UI framework or third-party dependency.
- Keep shared presentation logic UIKit-independent and small.
- Use one App Group JSON file and one containing-app writer.
- Add no transaction coordinator, outbox, receipt, acknowledgement, consumed-ID
  log, tombstone, lease, policy generation, or retry queue.
- Prefer three focused keyboard files and one app publisher over a new package or
  service family.
- Every checkpoint reports source/test line movement and has a direct
  user-visible or verification purpose.

## B0 — Contract And Gate

Record the current public-API and App Review result in the active release,
keyboard UX, and feasibility specs. Preserve the selected composition while
making unavailable voice behavior explicit. Do not silently declare an app-only
fallback to be V1.1; that product decision remains separate.

Exit:

- the implementation plan is committed;
- no active spec asks production code to manufacture a positive K1 result;
- the baseline build and bridge tests are recorded.

## B1 — Bounded Snapshot V2

Replace the Phase-0 transient/session envelope with one projection:

```text
schemaVersion = 2
revision
publishedAt
historyEnabled
latest?
  resultID
  text
  createdAt
  expiresAt
recentResults[0...5]
  resultID
  text
  createdAt
  expiresAt
```

Rules:

- Latest expires 10 minutes after its canonical creation time; republishing
  never extends it.
- Recent items expire after 24 hours, are newest first, unique by result id, and
  capped at five.
- `expiresAt == now` is expired.
- Preserve accepted text exactly; reject empty, oversized, or unsafe control
  content rather than trimming or silently rewriting it.
- Bound file size and decode failures. Missing, corrupt, incompatible, and
  inaccessible records are not successful empty History.
- The first V2 save atomically replaces the Phase-0 V1 file.

Tests cover exact text, round trip, limits, ordering, deduplication, both expiry
boundaries, disabled History, corrupt/oversized/incompatible data, and strictly
increasing revisions.

## B2 — One Production Publisher

Add one app-owned actor that loads canonical Latest and compact History, derives
the snapshot, and atomically replaces the shared file. It owns no durable state.

Publish after:

- successful acceptance and compact History append;
- launch or foreground reconciliation;
- Clear Latest;
- History Delete, Clear All, enable, and disable-and-clear.

Projection failure never changes successful dictation into provider failure and
never recreates provider work. A destructive History action must not report that
the shared copy is gone when publication failed; retry republishes current
canonical state. Remove the DEBUG sample writer after production wiring.

## B3 — Brand Stage Adaptive UI

Replace the probe controller with:

1. Top rail: History, centered HoldType mark/status, Latest.
2. Voice stage: a 56–60 point branded microphone treatment and restrained static
   waveform. It is disabled while K1 is unresolved and has no fake tap action.
3. Correction row: `.`, `,`, `?`, `!`.
4. Editing row: conditional Globe, wide Space, Delete, adaptive Return.

Implementation details:

- semantic dynamic colors with HoldType blue `#5165E8` and purple `#844DF2`
  limited to brand/status accents;
- minimum 44-point targets, Dynamic Type-safe labels, VoiceOver names and hints,
  Reduce Motion, Increase Contrast, and Reduce Transparency behavior;
- show Globe only when `needsInputModeSwitchKey` requires it;
- keep `hasDictationKey = false` while HoldType voice is unavailable;
- no `A`, `Refresh`, giant Latest button, alphabet deck, settings gear, or opaque
  mode icon.

## B4 — Editing Semantics

- Punctuation inserts one literal scalar per tap.
- Space tap inserts one space.
- A 0.30-second Space long press enters cursor mode; horizontal drag emits
  bounded character offsets and never also inserts a space.
- Delete fires once on touch-down, repeats after about 0.42 seconds, and
  accelerates only within the bounded 85–45 ms cadence. Every end, cancel,
  disappearance, and deinit path stops repeat.
- Return maps current public `UIReturnKeyType` to an honest label and inserts
  `"\n"`; host-specific submit behavior remains device QA.
- No host text or keystroke content is logged or persisted.

Pure tests cover cursor thresholds/reset, repeat timing bounds/cancellation,
Return presentation, and one-event insertion gating. UIKit integration remains
Simulator/device evidence because the iOS test target does not compile the
extension controller.

## B5 — Latest And Recent Results

- Reload the snapshot at normal extension lifecycle boundaries; add no Refresh
  control and treat no file event as a wake-up mechanism.
- Latest inserts only a valid unexpired item with one `insertText` call per tap.
- History replaces the voice stage with at most five newest valid items and an
  explicit close action; the editing row remains available.
- A recent item inserts only on its explicit tap. Reload, host change, app return,
  or process recreation never replays it.
- Disabled, empty, missing, corrupt, incompatible, and inaccessible History are
  distinct compact states.
- Full 20-entry History and destructive controls remain in the containing app.

## B6 — Verification And Evidence

Automated:

- focused shared model, publisher, owner/wiring, and presentation tests;
- Debug and Release iOS builds;
- extension dependency and entitlement isolation;
- macOS build regression;
- `git diff --check`.

Simulator with sanitized automation environment:

- enable and select HoldType Keyboard;
- capture Light/Dark portrait and compact-landscape evidence;
- verify punctuation, Space, cursor drag, Delete tap/hold, Return, Globe, Latest,
  recent-result selection, and no automatic insertion;
- inspect Dynamic Type, Reduce Motion, Increase Contrast, and accessibility
  labels where Simulator exposes them.

Signed physical iPhone remains required for effective App Group/Full Access,
secure and phone fields, host rejection, eviction, system footer,
`hasDictationKey`, Return behavior, Data Protection, and review-facing metadata.
A device test may prove a one-way URL technically works, but it cannot alone make
that undocumented keyboard behavior App-Review-safe.

## Checkpoint Order

| Checkpoint | Deliverable | Status |
| --- | --- | --- |
| B0 | Plan, K1 evidence, active spec alignment | In progress |
| B1 | Snapshot V2 and focused tests | Not started |
| B2 | Production publisher and app wiring | Not started |
| B3-B4 | Brand Stage UI and editing semantics | Not started |
| B5 | Latest/History consumption | Not started |
| B6 | Builds, Simulator QA, evidence, release assessment | Not started |

Engineering completion means every non-blocked slice is green and the keyboard
contains no misleading or prohibited voice action. Release completion still
requires an explicit product decision for K1 plus remaining signed-device checks.
