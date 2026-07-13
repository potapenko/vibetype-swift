# HoldType iOS V1.1 Release Contract

Status: canonical iOS product contract; approved 2026-07-13.

`V1.1` is the first planned iOS release designation. It does not imply that an
iOS V1.0 was previously shipped.

This spec supersedes conflicting P5H-P8 behavior for V1.1. Detailed legacy iOS
specs remain research and implementation evidence, but they do not expand this
release unless this file explicitly links to that behavior.

## Goal

Ship one coherent iPhone product: a useful containing app for foreground voice
input and personal writing rules, plus a usable custom keyboard with a dedicated
voice action and explicit result insertion.

V1.1 optimizes for a trustworthy daily path, not maximum platform coverage. It
must finish the keyboard and visible product before adding another recovery,
storage, or background subsystem.

## Release Scope

V1.1 includes:

- iPhone setup, Voice, Library, compact History, and Settings;
- foreground recording and OpenAI transcription in the containing app;
- existing optional correction and translation;
- one recoverable pending recording;
- one Latest Result;
- up to 20 successful text-only History entries;
- one production-quality iPhone typing layout;
- a dedicated keyboard voice action and explicit Insert Result path;
- the existing Usage Estimate kept unchanged as an informational Settings
  route;
- the existing iPad containing-app adaptation as best-effort compatibility UI,
  not a marketed or release-qualified V1.1 surface.

The first keyboard locale is `en-US`. A second locale is a later release unless
it can be added without delaying or weakening the physical-device V1.1 gate.

## Non-goals

- failed-attempt History or more than one recoverable failed recording;
- retry-audio queues, accepted audio playback, or Recording Cache;
- History policy generations, outboxes, tombstones, receipts, or multi-record
  transaction protocols;
- automatic provider retry after relaunch;
- automatic insertion into an unverified or changed host field;
- microphone, API key, prompts, OpenAI code, or raw audio in the extension;
- pixel-identical Apple keyboard trade dress or Apple emoji assets;
- full Apple-quality autocorrection and predictions in the first V1.1 build;
- background Quick Session or a keyboard-started background recording flow;
- cloud sync, accounts, analytics, profiles, modes, Live Activity, or billing;
- production iPad floating keyboard, Stage Manager, or hardware-keyboard
  shortcuts;
- App Store submission, enrollment, or purchase of dependencies.

## Product Navigation

The containing app exposes four useful destinations only:

- `Voice`: record, recover one pending attempt, and work with Latest Result;
- `Library`: Dictionary, Voice Emoji Commands, and Replacement Rules;
- `History`: successful accepted text only;
- `Settings`: provider, language/writing, recording, privacy, and setup.

A destination must not ship as a placeholder. During implementation, History
is removed from navigation until the compact screen is ready. V1.1 is not
release-complete until the finished History destination is restored.

## Setup

- Setup explains how to add and switch to HoldType Keyboard.
- Provider setup owns API-key entry and current OpenAI processing consent.
- Microphone permission is requested by the containing app only when the user
  starts the first recording or explicitly reviews permission setup.
- The app exposes one practice field for keyboard switching and insertion.
- Setup never claims that voice can start from the keyboard until a signed
  physical-device test proves the exact action.
- Ordinary keyboard typing remains available when provider setup, microphone
  permission, network, or Full Access is unavailable.

## Foreground Voice

- `Start Dictation` records in the foreground containing app.
- The active recording offers explicit Done and Cancel actions.
- Done stops microphone capture before provider processing continues.
- A valid completed recording becomes locally recoverable before the first
  provider request.
- Only one recording or provider chain may be active or pending.
- Provider stages have explicit timeouts and real cancellation.
- Standard dictation is always the primary action. Translation is available
  only when its current target is valid.
- Current Dictionary, Voice Emoji Commands, Replacement Rules, cleanup,
  correction, and translation apply in their documented order.
- A successful result becomes Latest Result even if compact History append
  fails.
- No local recovery action repeats provider work automatically.

## Pending Recovery

- V1.1 stores at most one pending attempt: one stable `attemptID`, one protected
  audio file, and compact app-private metadata.
- Local states are ready, processing, failed, and accepted-with-result while
  exact audio cleanup is unfinished.
- Relaunch performs local reconciliation only.
- A recoverable pending attempt offers Retry and Discard.
- Retry is explicit and uses current setup. It creates one fresh provider
  attempt only after local ownership is confirmed.
- Discard removes the exact pending audio and metadata and never affects Latest
  Result or accepted History.
- Corrupt or uncertain state fails visibly and preserves data when safe absence
  cannot be proved.
- Starting a second recording is unavailable while one pending attempt still
  owns audio.

## Latest Result

- Latest Result stores one accepted text value, its result identifier, and its
  source attempt identifier in app-private storage.
- It provides Copy, Share, Use in Practice, and Clear.
- Clear is idempotent and does not mutate an unrelated pending attempt.
- Latest Result contains no provider payload, prompt, credential, or raw audio.
- Relaunch preserves the most recent accepted text until Clear or replacement.
- V1.1 intentionally removes the old 24-hour app-private Latest expiry. Only
  the App Group keyboard snapshot is short-lived.
- Latest Result is always on for V1.1. The old iOS `keepLatestResult` preference
  is removed from the UI and ignored by a scoped migration; macOS behavior is
  unchanged.

## Compact History

- History is local, app-private, text-only, and limited to the 20 newest
  accepted results.
- Each entry uses the accepted `resultID` as its opaque idempotency key and
  contains accepted text and creation date.
- Entries are presented newest first with text preview and full-text detail.
- Each entry supports Copy, Share, and Delete. The screen supports confirmed
  Clear All.
- History append, Delete, and Clear All are serialized by one repository owner.
- History storage failure is a nonblocking local warning after Voice success;
  it never turns a successful provider result into a failed dictation.
- Latest is committed before the History append is attempted. Exact Pending
  metadata and audio cleanup always continue after the attempt, including when
  History storage fails.
- If the app relaunches after Latest was committed but before local acceptance
  cleanup completed, reconciliation may append that same result idempotently
  when `Save History` is still on. It never repeats provider work and never
  keeps Pending solely because History is unavailable.
- History never owns audio and never contains failed provider attempts.
- A new install enables `Save History` by default. Setup and Privacy state that
  up to 20 successful texts are stored locally on this device.
- Turning `Save History` off requires confirmation, stops future appends, and
  atomically replaces the repository record with disabled plus no entries
  before the switch reports success. Cancel or storage failure leaves the
  previous enabled record and entries unchanged.
- Turning it on affects later successful results only. V1.1 does not use a
  History generation or cutover protocol.
- The History destination has explicit loading, disabled, empty, list, and
  unavailable states. Only a genuine load failure uses `History Unavailable`
  and offers Retry; an enabled empty record shows `No History Yet`.
- A failed Delete, Clear All, enable, or disable operation keeps the last
  confirmed presentation and shows a nonblocking local warning. Destructive
  actions report success only after the atomic record replacement succeeds.

## Keyboard Typing

The first-release keyboard provides:

- alphabetic, number, and symbol layouts for `en-US`;
- Shift, double-tap Caps Lock, Delete with repeat, Space, Return, `123`, symbol
  switching, and Globe;
- field-appropriate Return labeling and basic auto-capitalization;
- double-space period;
- cursor movement from a long press on Space;
- key callouts, useful touch targets, light/dark appearance, and optional
  haptics that follow the current preference;
- VoiceOver labels, traits, and state announcements;
- ordinary Unicode typing without network and without Full Access.

Long-press Space remains cursor movement. Voice uses a separate microphone
control in a compact action bar.

V1.1 may use a small bundled correction lexicon and explicit Undo if it is
ready, but it must not present unfinished predictions or claim Apple-level
autocorrection quality. A later keyboard-quality milestone may add predictions
without changing the voice safety contract.

## Keyboard Voice And Insertion

- The microphone button performs only a physically verified action.
- The extension never records audio or contacts OpenAI itself.
- After D0 proves supported containing-app handoff, the button opens or
  activates that documented app voice flow; it does not display `Listening`
  before the containing app actually owns a recording.
- The user explicitly returns to the host app and invokes `Insert Result`.
  V1.1 does not promise private automatic return or automatic insertion.
- The app may publish one short-lived accepted-text snapshot to App Group
  storage only after the physical gate proves the required Full Access state.
- The snapshot contains only version, result identifier, accepted text,
  creation time, and expiry. It contains no secret, audio, prompt, dictionary,
  provider response, or host context.
- Insert is available only for a valid unexpired snapshot. One button tap calls
  `textDocumentProxy` once; re-entrant handling of that tap is suppressed.
- The same still-valid result may be inserted again only after another explicit
  user tap. Relaunch, refresh, host-field change, or app return never inserts or
  replays it automatically; V1.1 therefore needs no durable consumed-ID log.
- If App Group or Full Access is unavailable, the keyboard explains the
  fallback and preserves ordinary typing and Globe.
- Secure fields, phone pads, and hosts that reject custom keyboards fall back
  to system behavior. HoldType does not claim to bypass that policy.

## Privacy And Permissions

- The API key remains in app-owned Keychain storage.
- Provider consent is current, explicit, app-private, and checked before every
  remote stage.
- The extension receives no API key or provider client.
- Pending audio and History remain app-private, protected, and backup-excluded
  according to their data type.
- Product logs contain no accepted text, prompt, dictionary content, API key,
  provider body, raw audio, or host document context.
- External calls have bounded timeouts.

## Failure Policy

- Offline or provider failure keeps the one pending recording when it is safe
  to retry, with explicit Retry or Discard.
- Local History failure preserves Latest Result.
- Local Latest failure preserves Pending ownership until the user-visible
  result can be recovered or safely retried locally.
- Keyboard handoff failure never fabricates recording progress.
- A temporarily unavailable qualified voice path degrades to clear instructions,
  app Voice, Copy, and Globe; ordinary typing remains functional.
- A process restart never uploads automatically and never inserts text
  automatically.

## Release Gates

### Automated And Simulator

- macOS behavior remains green.
- iOS Debug and Release builds succeed with the embedded extension.
- App and extension dependency isolation is verified.
- Foreground Voice to Latest succeeds with fakes.
- Relaunch exposes the one Pending Retry/Discard path.
- Library and core Settings persist.
- Compact History append, Delete, Clear All, cap, and failure isolation pass.
- Release navigation contains no placeholder destination.
- Keyboard engine tests cover layout changes, Shift/Caps, Delete repeat, Space
  cursor movement, field traits, expiry, and explicit insertion.

### Signed Physical iPhone

V1.1 is not release-complete until a recorded device pass proves:

- app and extension install with matching signing and App Group configuration;
- keyboard enablement and Globe switching;
- ordinary typing in Notes, Messages, Mail, Safari, and two third-party apps;
- Full Access off and on behavior;
- secure-field, phone-pad, and host-opt-out fallback;
- the exact microphone-button handoff and honest unavailable state;
- app foreground recording, Done, Cancel, interruption, and provider timeout;
- explicit return and Insert Result exactly once per tap, with no automatic or
  wrong-field replay;
- process termination preserves Latest or the one pending attempt;
- effective Keychain and Data Protection behavior.
- after explicit user authorization with a configured provider key, one manual
  Standard-mode smoke proves physical microphone -> OpenAI -> configured text
  rules -> Latest -> History -> manual return -> Insert Result. Automated agents
  do not enter the key or run live-provider tooling without that request.

Simulator evidence cannot pass this gate.

The signed device gate must prove a supported containing-app handoff from the
microphone control. If it cannot, the keyboard-plus-voice V1.1 defined here is a
no-go and requires an explicitly approved, renamed app-only scope; an
instruction-only microphone button is not successful completion of V1.1.

## Complexity Guardrails

- A new internal abstraction must serve a current V1.1 behavior or required
  release gate.
- Do not add a failed-history, outbox, policy-generation, receipt, lease, or
  capability family to V1.1.
- Prefer one owner and one record for one product concept.
- Tests protect product invariants and semantic failure boundaries, not every
  implementation micro-state.
- Each checkpoint reports production/test line movement. Growth during a
  simplification checkpoint requires a concrete user-visible justification.

## Verification Mapping

- Scope audit: `docs/ios-v1-scope-reset-audit.md`.
- Development and deletion order: `docs/ios-v1-development-plan.md`.
- Historical physical keyboard evidence remains under `docs/qa/runs/` but does
  not pass the V1.1 device gate.

## Physical Spike Decision

The first physical spike decides whether supported app handoff plus explicit
manual return and Insert Result is feasible. It uses only public API and a
minimal signed probe. It may not introduce background Quick Session
architecture to manufacture a positive result.

A positive result fixes that interaction as the V1.1 voice mode. A negative
result stops keyboard-plus-voice V1.1 before persistence or keyboard expansion;
continuing as an app-only product requires an explicit scope and product-name
decision.
