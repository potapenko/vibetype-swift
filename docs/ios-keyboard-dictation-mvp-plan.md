# HoldType iOS Keyboard Handoff Plan

Status: canonical keyboard execution plan; revised and approved 2026-07-14.

Product behavior is governed by:

- `docs/specs/features/ios-keyboard-handoff-and-delivery.md` for the complete
  keyboard microphone, app handoff, request reconnection, and text delivery;
- `docs/specs/features/ios-keyboard-experience.md` for the keyboard's visual
  composition, editing controls, voice/error area, and accessibility;
- `docs/specs/features/ios-v1-release.md` for the containing app and overall iOS
  release, except where the narrower handoff spec explicitly supersedes an
  older no-launch or manual-session clause.

This is a direct-chat execution plan, not a backlog. Each implementation slice
runs in a separate chat, stays on `master`, preserves unrelated work, and ends
with one scoped checkpoint commit.

## Strategy

HoldType will build the keyboard only as an end-to-end voice entry point:

```text
tap existing keyboard microphone
        -> open HoldType and start app-owned recording
        -> user returns to the host app
        -> recreated keyboard reconnects to the request
        -> finish or cancel from the keyboard
        -> accepted text inserts exactly once when the document still matches
```

There is no separate black button, Open HoldType action, keyboard handoff
screen, or user-prepared Keyboard Dictation Session. The existing microphone is
the primary action. The existing keyboard voice/error area carries every
handoff, permission, recording, processing, failure, and recovery message.

The first Voice screen already being developed in the containing app remains
the landing surface. This plan integrates with that screen and must not replace,
fork, or redesign it.

The keyboard is an all-or-nothing release capability. App Store uncertainty is
accepted as a release risk, not used to weaken the product in advance. If the
complete flow cannot be approved, the fallback is an app-only build without
the extension or keyboard onboarding. A manual-session keyboard is not a
fallback.

## Validated Foundation

The earlier KBD-MVP work remains useful engineering evidence even though its
manual-session product strategy is retired.

| Existing slice | Reused evidence | Status |
| --- | --- | --- |
| KBD-MVP-1 | Normal app shell, embedded extension, and keyboard action plumbing | Completed |
| KBD-MVP-2 | Signed-device app-owned audio and App Group feasibility | Passed; commit `8829623` |
| KBD-MVP-3 | Recorder, OpenAI, result state, and guarded insertion pipeline | Implemented; commit `2693855` |
| KBD-MVP-4 | Brand Stage recovery and state presentation work | Useful UI foundation; old manual-session recovery contract superseded |
| KBD-MVP-5 | Device qualification and TestFlight | Replaced by KBD-FLOW-7 |

Existing code should be evolved, not discarded. In particular, keep the
app-owned recorder/provider pipeline, bounded shared records, canonical Latest,
and defensive insertion checks. Replace the assumptions that the app is
already prepared and that extension-process lifetime defines destination
ownership.

## Target Architecture

```text
Host text document
    ^
    | UITextDocumentProxy.insertText (at most once)
    |
HoldType Keyboard Extension
    |  fresh request + source document identity
    |  opens holdtype://... with opaque request identity
    v
Bounded App Group command record
    |
    v
Containing app / existing first Voice screen
    |  validates request, owns microphone, OpenAI, and accepted text
    v
Bounded App Group state/result record
    |
    +--> recreated extension reconnects by request + document identity
    +--> matching document claims and inserts once
    +--> unsafe or uncertain delivery stays in canonical Latest
```

### Coordination Boundary

Keep the current two-record budget unless a physical-device finding proves it
insufficient:

1. an extension-written current request/command record;
2. an app-written current state/result record.

Both records are atomically replaced, schema-versioned, bounded, expiring, and
have one authoritative writer. They are not an append-only log, durable queue,
or second History store.

The next schema must support:

- keyboard-created opaque request ID;
- command kind: start, finish, or cancel;
- source `documentIdentifier` when available;
- request creation and expiry;
- app phases such as opening, awaiting permission, listening, processing,
  result ready, failed, cancelled, and expired;
- accepted result identity and expiry;
- enough bounded claim state to prevent replay after extension recreation.

Raw audio, credentials, prompts, provider payloads, durable host content, and
canonical History remain outside the App Group.

### Launch Validation

- The custom URL carries opaque routing identity only.
- HoldType starts recording only when the URL matches a fresh shared request.
- An ordinary app launch never starts the microphone.
- A repeated or stale URL never starts a second capture.
- The app may surface microphone permission after the explicit keyboard tap,
  but does not report Listening until real capture starts.

### Destination And Exactly-Once Delivery

- Extension-process identity is not destination identity. iOS may destroy and
  recreate the extension during the round trip.
- Reconnection uses request identity plus the source document identity that iOS
  exposes through `UITextDocumentProxy.documentIdentifier`.
- Automatic insertion requires the same live request, the same source document,
  an unexpired result, and no prior claim.
- Claim happens before `insertText`. A recreated extension must observe the
  claim and never replay the result.
- If insertion success is uncertain, do not retry automatically. Preserve the
  accepted result in Latest and expose an explicit recovery action.

## Execution Rules

- Execute KBD-FLOW slices in order. Do not combine the feasibility spike with a
  production refactor.
- Do not run keyboard implementation work in parallel with another task editing
  the same files. Integrate with the parallel Voice-screen work at its public
  boundary after that work is committed.
- Do not spawn subagents unless the user explicitly asks.
- Read `AGENTS.md`, `docs/agent-onboarding.md`, `SWIFT.md`, this plan, the three
  governing specs, and only task-owned source/tests.
- Do not create backlog tasks or use the backlog selector.
- Work only on `master`. Preserve unrelated changes and stage only task-owned
  paths.
- Every file-changing iteration ends with focused verification and one scoped
  checkpoint commit.
- Remove DEBUG-only probes before the iteration commit unless a bounded device
  qualification route explicitly owns them.
- A failed core feasibility gate stops keyboard implementation. Do not silently
  restore the retired manual-session strategy.

## Runtime Evidence Rules

- Use the Simulator for UI/state determinism and actual extension-host
  interaction that it can represent.
- Use a signed physical iPhone for real microphone ownership, app switching,
  extension recreation, source-document continuity, and insertion delivery.
- iPhone Mirroring may operate the containing app only and does not prove direct
  keyboard-extension interaction.
- Before Simulator, Mirroring, or physical-device QA, follow the repository's
  `iOS Simulator, Mirroring, And Physical Device QA` tooling contract.
- Start scoped `caffeinate` before every UI automation session and stop it after
  the session.
- Launch automated app QA through the sanitized verification path. Never enter
  a login-keychain password or approve `Always Allow`.
- Do not use live OpenAI or `--live-debug` unless the user explicitly authorizes
  that session. Use controllable fakes for normal automated verification.
- Evidence must identify commit/build, device, iOS version, starting state,
  actions, and observed result. A source inspection is not runtime proof.

## Delivery Sequence

| ID | Scope | Exit condition | Status |
| --- | --- | --- | --- |
| KBD-FLOW-0 | Product contract and revised execution plan | Canonical spec and plan adopt the Flow-like strategy | Completed 2026-07-14 |
| KBD-FLOW-1 | One-tap signed-device feasibility spike | Existing mic opens HoldType, real capture starts, return recreates/reconnects keyboard, Finish stops capture, and a deterministic result reaches the source document | Next |
| KBD-FLOW-2 | Bridge v2 request and destination identity | Versioned records support keyboard-created request, source document, app phases, expiry, and bounded claim state | Pending |
| KBD-FLOW-3 | Launch and app-owned capture integration | Valid fresh handoff opens the existing Voice screen and begins capture; ordinary/stale launches do not | Pending |
| KBD-FLOW-4 | Cross-lifetime command and exactly-once delivery | Start/Finish/Cancel survive extension recreation; safe result inserts once and mismatch falls back to Latest | Pending |
| KBD-FLOW-5 | Production pipeline integration | Real transcription and existing text rules feed the same request without duplicate provider work | Pending |
| KBD-FLOW-6 | Setup, error, accessibility, and app-only packaging | Existing voice/error area covers all states; release can cleanly include or exclude keyboard | Pending |
| KBD-FLOW-7 | Device matrix, TestFlight, and review candidate | Signed-device matrix passes and one complete keyboard candidate is submitted or the explicit app-only decision is taken | Pending |

## KBD-FLOW-1 — One-Tap Physical Feasibility Spike

### Purpose

Prove the only product path worth building before changing production bridge
architecture. This is a disposable or narrowly isolated spike, not the final
implementation.

### Required scenario

1. In a real host text field, select HoldType Keyboard.
2. Tap its existing microphone button.
3. Observe HoldType open from that user action.
4. Observe the containing app start real microphone capture for the matching
   request without a separately prepared session.
5. Swipe back to the host.
6. Observe the extension reconnect after likely recreation and show Listening.
7. Tap the microphone again to Finish.
8. Observe app-owned recording stop and a deterministic fake result become
   available.
9. Observe exactly one insertion into the originating document.

Also exercise Cancel, permission denial, repeated URL, stale request, changed
document, and extension recreation before result delivery.

### Exit decision

- `pass`: evidence proves the whole round trip; proceed to KBD-FLOW-2;
- `needs narrow follow-up`: one bounded public-API uncertainty remains and has a
  named experiment;
- `fail`: a core step cannot work reliably with public APIs on the supported
  device/OS. Stop keyboard implementation and report the app-only consequence.

App Review is not decided by this spike and is not a reason to mark a working
public-API flow failed.

## KBD-FLOW-2 — Bridge V2

- Introduce the new request/state schema with explicit migration from current
  transient records.
- Make request ID originate in the keyboard before app launch.
- Persist source document identity and expiry.
- Replace extension-lifetime ownership with request/document ownership.
- Add deterministic tests for stale URLs, phase transitions, record corruption,
  expiry, supersession, and claim replay.
- Keep the bridge bounded to two transient records unless KBD-FLOW-1 evidence
  requires a documented exception.

Exit when bridge tests prove reconnection and at-most-once claims without UI or
live microphone dependencies.

## KBD-FLOW-3 — App Launch And Capture

- Route a valid handoff into the existing first Voice screen.
- Reuse the screen's recorder/status model; do not build a second handoff UI.
- Start capture once per fresh request after permission succeeds.
- Publish Opening, permission, Listening, failure, and expiry truthfully.
- Make repeated, malformed, expired, or unrelated launches harmless.
- Preserve ordinary standalone Voice behavior.

Exit when app integration tests and signed-device evidence distinguish a valid
handoff from ordinary launch and prove one real capture lifecycle.

## KBD-FLOW-4 — Keyboard Reconnection And Delivery

- Restore the active request when a new extension instance appears in the same
  source document.
- Drive the existing voice/error area from app-acknowledged state.
- Route the existing microphone to Finish while Listening and back to Start
  after a terminal state.
- Keep Cancel explicit and idempotent.
- Claim an eligible result before insertion and prevent replay across process
  restarts.
- Preserve Latest for document mismatch, missing identity, expiry, or uncertain
  insertion.

Exit when automated bridge/controller tests plus signed-device QA prove the
normal path and every no-wrong-field invariant.

## KBD-FLOW-5 — Production Text Pipeline

- Connect Finish to the existing bounded recorder, OpenAI transcription, and
  correction/translation rules.
- Keep one provider submission per request and no automatic retry after an
  external failure.
- Commit accepted output once to canonical Latest and current History policy.
- Publish only bounded accepted result data to the keyboard bridge.
- Verify timeout, offline, empty audio, provider failure, cancellation, and
  app termination.

Exit when fake-provider automation passes and an explicitly authorized live
smoke proves the production boundary without duplicate submission or delivery.

## KBD-FLOW-6 — Product Completion And Packaging

- Replace retired `Session not running` guidance with states appropriate to
  one-tap handoff.
- Keep the existing microphone as the only primary launch/finish control.
- Keep all state and recovery copy in the voice/error area.
- Complete Voice-screen return instruction, Full Access, microphone permission,
  offline, timeout, failed, expired, and Latest recovery UX.
- Verify VoiceOver names, focus order, Dynamic Type, contrast, and Light/Dark.
- Add a build/release configuration that cleanly excludes the extension and
  keyboard onboarding while preserving the standalone Voice product.

Exit when Simulator UI QA passes and both keyboard-included and app-only
artifacts are internally coherent.

## KBD-FLOW-7 — Release Qualification

Run a bounded matrix across supported iOS versions and representative host apps:

- fresh install and upgrade;
- Full Access off/on;
- microphone undecided/allowed/denied;
- cold/warm app;
- extension retained/recreated;
- same document/focus changed/different document;
- Start/Finish/Cancel;
- offline, timeout, provider failure, interruption, and app termination;
- result insertion, Latest fallback, and duplicate-delivery attempts.

Then qualify one internal TestFlight build. If the complete keyboard is rejected
and no compliant equivalent preserves the canonical flow, make an explicit
release decision to submit the app-only artifact. Do not substitute the retired
manual-session keyboard.

## Immediate Next Step

After KBD-FLOW-0 is committed, the next implementation chat is KBD-FLOW-1 only.
Its job is to prove the end-to-end public-API round trip on a signed physical
iPhone before production bridge or UI refactoring begins.
