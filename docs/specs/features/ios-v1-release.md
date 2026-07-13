# HoldType iOS V1.1 Release Contract

Status: canonical iOS product contract; approved and revised 2026-07-13.

`V1.1` is the first planned iOS release designation. It does not imply that an
iOS V1.0 was previously shipped.

This spec supersedes conflicting P5H-P8 behavior for V1.1. Detailed legacy iOS
specs remain research and implementation evidence, but they do not expand this
release unless this file explicitly links to that behavior.

K1 update, 2026-07-13: current Apple documentation and App Review Guideline
4.4.1 do not qualify a review-safe keyboard-to-containing-app launch. The
non-blocked keyboard UI, editing, Latest, and recent-result work may proceed, but
the keyboard-plus-voice V1.1 release claim remains unresolved until an explicit
product rescope, new Apple guidance, or explicit acceptance of the review risk.

## Goal

Ship one coherent iPhone product: a useful containing app for foreground voice
input and personal writing rules, plus a polished custom voice-command keyboard
for starting the verified voice flow, correcting text, and explicitly inserting
accepted results.

V1.1 optimizes for a trustworthy daily path, not maximum platform coverage. It
must finish the visible product before adding another recovery, storage, or
background subsystem. HoldType Keyboard complements the user's system keyboards;
it is not a replacement QWERTY engine.

## Release Scope

V1.1 includes:

- iPhone setup, Voice, Library, compact History, and Settings;
- foreground recording and OpenAI transcription in the containing app;
- existing optional correction and translation;
- one recoverable pending recording;
- one Latest Result;
- up to 20 successful text-only History entries;
- one production-quality iPhone voice-command keyboard surface;
- a dedicated keyboard voice action and explicit Insert Result path;
- a bounded keyboard projection of Latest and up to five accepted texts from the
  previous 24 hours;
- the existing Usage Estimate kept unchanged as an informational Settings
  route;
- the existing iPad containing-app adaptation as best-effort compatibility UI,
  not a marketed or release-qualified V1.1 surface.

The command surface has no product typing locale. It inserts accepted Unicode
text in any transcription language supported by the containing app. Keyboard
chrome localization is independent of transcription language and does not add
alphabetic layouts.

## Non-goals

- failed-attempt History or more than one recoverable failed recording;
- retry-audio queues, accepted audio playback, or Recording Cache;
- History policy generations, outboxes, tombstones, receipts, or multi-record
  transaction protocols;
- automatic provider retry after relaunch;
- automatic insertion into an unverified or changed host field;
- microphone, API key, prompts, OpenAI code, or raw audio in the extension;
- alphabetic QWERTY, number or symbol decks, Shift, Caps Lock, predictions,
  autocorrection, or locale-specific typing dictionaries;
- pixel-identical Apple keyboard trade dress or Apple emoji assets;
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
- Setup explains that normal typing remains on the user's system keyboard and
  that Globe switches between it and HoldType.
- Punctuation, Space, Delete, Return, and Globe remain available when provider
  setup, microphone permission, network, or Full Access is unavailable.

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
  the Latest item inside the App Group keyboard snapshot has a short insertion
  expiry of 10 minutes.
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

## Keyboard Command Surface

The selected production composition is **Brand Stage**. Geometry and hierarchy
stay identical in Light and Dark Mode; only system materials, key colors,
shadows, and contrast adapt to the active iOS appearance. The HoldType blue and
purple are reserved for the microphone and small active-state accents.

The first-release surface provides:

- a compact top row with `History` on the left, the HoldType mark plus honest
  status in the center, and `Latest` on the right;
- one medium microphone control and a restrained waveform/status stage; the
  microphone is the only primary action and never becomes a full-width button;
- one correction row containing `.`, `,`, `?`, and `!`;
- one editing row containing Globe, a wide Space key, Delete, and adaptive
  Return;
- short-tap Space insertion plus long-press and drag cursor movement without an
  inserted space;
- Delete repeat with bounded acceleration and Return behavior derived from the
  current text-input traits;
- minimum 44-point targets, VoiceOver labels and state announcements, Dynamic
  Type-safe labels, Reduce Motion support, and sufficient contrast in both
  appearances;
- local punctuation and editing controls that work without network or Full
  Access.

The HoldType mark is identity and status, not an unlabeled button. The keyboard
contains no alphabet, number deck, `A` probe key, `Refresh`, Shift, Caps Lock,
`123`, predictions, or autocorrection. Accepted results may contain arbitrary
Unicode; ordinary free typing and system emoji remain available through Globe.

## Keyboard Voice And Insertion

- The microphone button performs only a physically verified action.
- The extension never records audio or contacts OpenAI itself.
- Current K1 evidence does not prove a supported containing-app handoff. The
  production extension therefore adds no custom URL/private launch path and
  exposes no actionable microphone or optimistic `Listening` state.
- The user explicitly returns to the host app and invokes `Insert Result`.
  V1.1 does not promise private automatic return or automatic insertion.
- The app may publish one bounded keyboard snapshot to App Group storage only
  after the physical gate proves the required Full Access state. The extension
  is read-only.
- The projection is a replaceable cache, not a second History repository or a
  delivery transaction. It has one app writer and no outbox, receipt,
  acknowledgement, tombstone, or replay protocol.
- The snapshot contains schema version, revision, one Latest item with a
  10-minute insertion expiry, and up to five recent accepted-text items with a
  24-hour expiry. Each item contains only result id, accepted text, creation
  time, and expiry. No secret, audio, prompt, dictionary, provider response,
  setting, or host context enters the snapshot.
- `Latest` inserts only a valid unexpired Latest item. `History` presents the
  bounded recent projection newest first; full 20-entry History, Delete, Clear
  All, and retention settings remain in the containing app.
- Turning Save History off or deleting app History removes the affected recent
  projection before that destructive action reports success. A projection-clear
  failure is visible and does not pretend the shared copy was removed. Every
  projected recent item expires after 24 hours regardless. Missing or invalid
  shared state is never rendered as an empty successful History.
- Every Latest or recent-result selection is an explicit insertion. One tap
  calls `textDocumentProxy` once; re-entrant handling of that tap is suppressed.
- The same still-valid result may be inserted again only after another explicit
  user tap. Relaunch, refresh, host-field change, or app return never inserts or
  replays it automatically; V1.1 therefore needs no durable consumed-ID log.
- If App Group or Full Access is unavailable, app-dependent actions show an
  honest compact fallback while punctuation, editing controls, and Globe remain
  usable.
- Secure fields, phone pads, and hosts that reject custom keyboards fall back
  to system behavior. HoldType does not claim to bypass that policy.

## Privacy And Permissions

- The API key remains in app-owned Keychain storage.
- Provider consent is current, explicit, app-private, and checked before every
  remote stage.
- The History-aware local-retention disclosure is contract version `2`.
  Acceptance of the former no-History version `1` requires explicit review
  before another provider request.
- Keyboard setup and Privacy explain that, after the qualified Full Access path
  is enabled, one 10-minute Latest item and up to five accepted texts from the
  previous 24 hours may be copied into the local shared container for explicit
  keyboard insertion.
- The extension receives no API key or provider client.
- Pending audio and the canonical 20-entry History remain app-private, protected,
  and backup-excluded according to their data type. Only the bounded derived
  accepted-text projection described above enters App Group storage.
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
  app Voice, Copy, and Globe; local editing controls remain functional.
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
- Keyboard tests cover both appearances, punctuation, Delete repeat, Space
  cursor movement, Return traits, voice-state honesty, snapshot validation,
  bounded recent results, expiry, and explicit insertion.

### Signed Physical iPhone

V1.1 is not release-complete until a recorded device pass proves:

- app and extension install with matching signing and App Group configuration;
- keyboard enablement and Globe switching;
- punctuation and editing controls in Notes, Messages, Mail, Safari, and two
  third-party apps;
- Full Access off and on behavior;
- secure-field, phone-pad, and host-opt-out fallback;
- the honest unavailable microphone state and absence of an undocumented launch;
- app foreground recording, Done, Cancel, interruption, and provider timeout;
- explicit return and Latest/History insertion exactly once per tap, with no
  automatic or wrong-field replay;
- process termination preserves Latest or the one pending attempt;
- effective Keychain and Data Protection behavior.
- after explicit user authorization with a configured provider key, one manual
  Standard-mode smoke proves physical microphone -> OpenAI -> configured text
  rules -> Latest -> History -> manual return -> Insert Result. Automated agents
  do not enter the key or run live-provider tooling without that request.

Simulator evidence cannot pass this gate.

The current public documentation does not qualify the supported containing-app
handoff requirement. The keyboard-plus-voice V1.1 defined here remains no-go
until an explicitly approved product rescope, new Apple guidance, or explicit
acceptance of the review risk; an instruction-only microphone button is not
successful completion of V1.1.

## Complexity Guardrails

- A new internal abstraction must serve a current V1.1 behavior or required
  release gate.
- Do not add a failed-history, outbox, policy-generation, receipt, lease, or
  capability family to V1.1.
- Do not grow a QWERTY, locale-layout, prediction, or autocorrection engine under
  the command-surface milestone.
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

## Voice Activation Decision

Physical evidence may qualify App Group, editing, insertion, fallback, and
metadata behavior. It may also show whether a one-way custom URL happens to work
on a specific iOS version, but it cannot alone make undocumented keyboard
behavior App-Review-safe. No production spike adds a private host-return path or
fabricates recording state. Continuing as an app-only product or changing the
keyboard's role requires an explicit scope and product-name decision.
