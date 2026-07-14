# HoldType iOS V1.1 Release Contract

Status: canonical iOS product contract; approved and revised 2026-07-14 for
keyboard-controlled dictation MVP.

`V1.1` is the first planned iOS release designation. It does not imply that an
iOS V1.0 was previously shipped.

This spec supersedes conflicting P5H-P8 behavior for V1.1. Detailed legacy iOS
specs remain research and implementation evidence, but they do not expand this
release unless this file explicitly links to that behavior.

Keyboard MVP update, 2026-07-14: `History` and the permanent Settings action are
removed from the keyboard and remain containing-app destinations. Unavailable
voice states replace the microphone with a complete recovery instruction. The
microphone becomes actionable through an explicit
app-owned Keyboard Dictation Session: the extension sends bounded Start, Finish,
or Cancel commands while the containing app owns microphone capture, OpenAI,
text rules, Latest, and History. The extension never accesses the microphone or
launches the containing app. This architecture remains a signed-device
feasibility gate before it becomes a release claim.

## Goal

Ship one coherent iPhone product: a useful containing app for voice input and
personal writing rules, plus a compact custom command keyboard whose primary
action controls an app-owned dictation session and inserts accepted text into
the active host field.

V1.1 optimizes for a trustworthy daily path, not maximum platform coverage. It
must finish the visible product before adding another recovery or storage
subsystem. The one bounded background session is release scope because iOS does
not expose microphone access to keyboard extensions. HoldType Keyboard
complements the user's system keyboards; it is not a replacement QWERTY engine.

## Release Scope

V1.1 includes:

- iPhone setup, Voice, Library, compact History, and Settings;
- foreground recording and OpenAI transcription in the containing app;
- one explicit, bounded, app-owned Keyboard Dictation Session;
- existing optional correction and translation;
- one recoverable pending recording;
- one Latest Result;
- one app-private composed Voice Draft governed by `ios-voice-draft.md`;
- up to 20 successful text-only History entries;
- an optional app-private Recording Cache for local History playback;
- one production-quality iPhone command-keyboard surface with actionable Start,
  Finish, and Cancel voice controls while that session is available;
- no Settings, History, or containing-app launch action inside the extension;
- automatic insertion only for the same still-live keyboard request and host
  context;
- an explicit `Latest` insertion path after the user returns to the host;
- a bounded keyboard projection of one Latest item with time-limited insertion
  eligibility only;
- the existing Usage Estimate kept unchanged as an informational Settings
  route;
- one distribution-signed internal TestFlight candidate and the metadata,
  privacy, and review artifacts required to decide App Store submission;
- the existing iPad containing-app adaptation as best-effort compatibility UI,
  not a marketed or release-qualified V1.1 surface.

The command surface has no product typing locale. It inserts accepted Unicode
text in any transcription language supported by the containing app. Keyboard
chrome localization is independent of transcription language and does not add
alphabetic layouts.

## Non-goals

- failed-attempt History or more than one recoverable failed recording;
- retry-audio queues or failed-attempt audio playback;
- History policy generations, outboxes, tombstones, receipts, or multi-record
  transaction protocols;
- automatic provider retry after relaunch;
- automatic insertion into an unverified or changed host field;
- microphone, API key, prompts, OpenAI code, or raw audio in the extension;
- alphabetic QWERTY, number or symbol decks, Shift, Caps Lock, predictions,
  autocorrection, or locale-specific typing dictionaries;
- pixel-identical Apple keyboard trade dress or Apple emoji assets;
- a general background Quick Session unrelated to the explicit Keyboard
  Dictation Session;
- launching the containing app from the keyboard, automatically returning to a
  previous host app, or bypassing iOS extension policy;
- indefinite background recording, idle speech retention, or silent-audio
  keepalive tricks;
- configurable session duration, cloud sync, accounts, analytics, profiles,
  modes, Live Activity, or billing;
- production iPad floating keyboard, Stage Manager, or hardware-keyboard
  shortcuts;
- purchasing Apple Developer enrollment or dependencies, or guaranteeing final
  App Review approval. Public submission remains an explicit release-owner
  action after the recorded gates pass.

## Product Navigation

The containing app exposes four useful destinations only:

- `Voice`: record, recover one pending attempt, and work with one composed
  editable Draft while Latest remains the last accepted result;
- `Library`: Dictionary, Voice Emoji Commands, and Replacement Rules;
- `History`: successful accepted text only;
- `Settings`: provider, language/writing, recording, privacy, and setup.

A destination must not ship as a placeholder. During implementation, History
is removed from navigation until the compact screen is ready. V1.1 is not
release-complete until the finished History destination is restored.

Voice is the first destination on every cold launch or newly created scene.
Returning an existing scene from the background preserves its current
destination. History remains a separate tab and is not previewed on Voice.

## Setup

- Setup explains how to add and switch to HoldType Keyboard and enable Allow
  Full Access for keyboard-controlled dictation.
- Provider setup owns API-key entry and current OpenAI processing consent.
- Microphone permission is requested by the containing app only when the user
  starts the first recording or explicitly reviews permission setup.
- The app exposes one practice field for keyboard switching and insertion in a
  compact Voice toolbar sheet rather than the primary Voice canvas.
- Setup exposes one plain `Start Keyboard Session` action, a visible session
  state, and a Stop action. Starting a session alone neither creates a recording
  nor contacts the provider.
- Setup states that the containing app owns recording even when the user controls
  it from the keyboard. If the session is unavailable, the keyboard says
  `Session not running`, shows the exact Voice-screen recovery path, and never
  launches the app itself.
- Setup explains that History and Settings are opened from the containing app.
- Setup explains that normal typing remains on the user's system keyboard and
  that Globe switches between it and HoldType.
- Full Access recovery keeps the complete iPhone Settings route visibly
  emphasized. `Shortcut: hold 🌐 → Keyboard Settings` appears only as a
  secondary hint and never replaces the full route.
- Keyboard and Full Access recovery open one dedicated in-app setup destination
  with a public Open System Settings action and practice field. The containing
  app reports Full Access as not currently verified rather than claiming it can
  read the system toggle directly.
- Punctuation, Space, Delete, Return, Globe, and an already-available
  restricted-mode Latest do not require provider setup, microphone permission,
  network, or Full Access. Keyboard-controlled dictation does require Full
  Access and a valid app-owned session.

## Foreground Voice

- `Start Dictation` records in the foreground containing app.
- The active recording offers an explicit Done action. A deliberate long press
  on the containing app's primary activity reveals a compact cancellation
  control without reserving space or moving that activity; keyboard Cancel
  remains an explicit keyboard command.
- Done stops microphone capture before provider processing continues.
- A valid completed recording becomes locally recoverable before the first
  provider request.
- Only one recording or provider chain may be active or pending.
- Provider stages have explicit timeouts and real cancellation.
- Standard dictation is always the primary action. Append, Auto Translate, and
  Auto Correction are session-only icon toggles in the settings row below the
  Voice Draft editor. The existing one-shot Translate and Correction actions,
  plus Undo, Redo, Copy, and Clear, stay in the action row above it. All three
  settings start off on cold launch, remain selected for subsequent
  containing-app attempts until turned off, and never rewrite durable Settings.
  Auto Translate is available only when its current route is valid, while Auto
  Correction forces the saved correction configuration for the selected
  attempts. Both may be enabled together.
- Current Dictionary, Voice Emoji Commands, Replacement Rules, cleanup,
  correction, and translation apply in their documented order.
- A successful result becomes Latest Result even if compact History append
  fails.
- Every accepted result is also offered exactly once to the separate Voice
  Draft. The safe default replaces the Draft only after acceptance; Append mode
  joins the new text with one blank line. Draft failure never rolls back Latest,
  History, or Pending cleanup.
- The Draft is editable only while Voice is inactive. It starts unfocused, so
  cold launch never opens the keyboard; a direct tap provides normal selection,
  typing, paste, and emoji input. One completed edit is one app-level Undo
  mutation and preserves accepted-result deduplication independently of text.
- Real recorder metering drives mirrored native level bars around the primary
  Voice control only while Listening. Meter values are ephemeral, bounded, and
  never persisted or logged.
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
- Failure to refresh the bounded keyboard copy never invalidates canonical
  Latest. The containing app retains a nonblocking cache warning until a later
  publication actually succeeds; operations that do not publish cannot clear
  that warning.
- Canonical load and Clear notices have display priority but do not erase a
  pending cache warning. A failed empty-snapshot publication after Clear keeps
  the otherwise-absent Latest section visible until the cache is successfully
  refreshed.

## Compact History

- History is local, app-private, text-only, and limited to the 20 newest
  accepted results.
- Each entry uses the accepted `resultID` as its opaque idempotency key and
  contains accepted text and an internal creation date used only for ordering.
- Entries are presented newest first as one flat list. Each row shows the full
  text directly; History has no result-detail destination and displays no
  creation date or time.
- Each row exposes one-tap Copy and, when eligible, Play immediately before
  Copy. Trailing swipe Delete removes that row. History does not add Share or
  another tap before Copy.
- Management actions such as confirmed Clear All and the Save History policy
  stay in toolbar or Settings surfaces so the primary screen remains a text
  list.
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
- History never owns audio and never contains failed provider attempts. A Play
  button resolves a separately retained Recording Cache file by `resultID`.
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

## Recording Cache And History Playback

- Recording Cache is app-private, off by default, and independent from the
  text-only History repository. It reuses `RecordingCachePolicy`: enabling it
  defaults to the 10 newest recordings; unlimited retention requires an
  explicit choice.
- When the current saved policy keeps recordings, HoldType retains the
  validated Pending audio in the cache under that accepted `resultID` before
  Pending cleanup. Relaunch reconciliation is idempotent and never repeats
  provider work.
- Recording Cache is optional: cache read, retention, or write failure never
  changes an accepted dictation into a failed result or blocks accepted Pending
  cleanup. The next reconciliation opportunity may retry cache maintenance.
- A History row shows Play only while Recording Cache is enabled and the exact
  cache file for that row still exists. Saving cache-off reconciles managed
  cache files immediately; clearing or retention pruning a file also removes
  Play availability.
- Play is local only. It does not contact OpenAI, retry transcription, mutate
  Latest or History, write either clipboard, or insert text.
- Deleting a History row does not delete its independent Recording Cache file;
  cache retention and cache clearing own those files, matching macOS behavior.
- One process-owned player owns History playback. Starting Voice first stops
  playback and deactivates its playback audio session before recording audio is
  activated.
- A missing or unplayable file removes Play availability or reports one compact
  playback failure. File paths never appear in product logs or UI.

## Keyboard Command Surface

The selected production composition is **Brand Stage**. Geometry and hierarchy
stay identical in Light and Dark Mode; only system materials, key colors,
shadows, and contrast adapt to the active iOS appearance. The HoldType blue and
purple are reserved for the microphone and small active-state accents.

The first-release surface provides:

- a compact top row with a three-icon Quick Insert, Translate, and Improve
  utility group on the left, the HoldType mark centered without status text,
  and `Latest` insertion on the right;
- one medium actionable microphone only while an app-owned Keyboard Dictation
  Session can start or finish real recording; unavailable states show complete
  recovery copy and processing shows progress instead of a disabled microphone;
- one direct, reversible Quick Insert workspace containing bundled local
  punctuation and emoji; it replaces the Voice workspace without an
  intermediate launcher, has no visible title, shows two emoji rows in regular
  height, and closes back to the exact underlying Voice state after any
  insertion;
- one-tap Translate and Improve starts with no menu or dialog: Translate is
  disabled until its saved route is valid, while Improve forces the saved
  correction configuration for that request without changing the durable
  correction preference;
- one editing row containing Globe, a wide Space key, Delete, and adaptive
  Return;
- short-tap Space insertion plus long-press and drag cursor movement without an
  inserted space;
- Delete repeat with bounded acceleration and Return behavior derived from the
  current text-input traits;
- minimum 44-point targets, VoiceOver labels and state announcements, Dynamic
  Type-safe labels, Reduce Motion support, and sufficient contrast in both
  appearances;
- local Quick Insert and editing controls that work without network or Full
  Access, even when voice dictation is unavailable; active Starting, Listening,
  and Processing states keep Voice visible and disable all three utility
  actions.

The HoldType mark is identity only, not a button or status surface. No state
label appears under or beside it; all state and recovery information lives in
the voice stage. The keyboard
contains no alphabet, number deck, `A` probe key, `Refresh`, Shift, Caps Lock,
`123`, predictions, or autocorrection. Accepted results may contain arbitrary
Unicode; ordinary free typing and system emoji remain available through Globe.

## Keyboard Dictation And Latest Insertion

- The extension never records audio, requests microphone permission, reads
  Keychain, or contacts OpenAI. The containing app owns the recorder and the
  existing provider/text-rule pipeline.
- Keyboard Start joins the same process-owned Voice workflow and recorder
  arbitration used by foreground Voice. It does not create a second recorder,
  provider pipeline, persistence owner, or recovery path. Foreground Voice,
  Pending Retry/Discard, and a keyboard request are mutually exclusive while
  any one of them owns Voice work.
- The user explicitly starts one bounded Keyboard Dictation Session in the
  containing app. An unavailable or expired session produces `Session not
  running` plus the exact Voice-screen recovery path; the keyboard does not
  launch the app.
- Keyboard-controlled voice requires Allow Full Access so the extension can
  write one bounded command to the App Group boundary. Local editing, Globe,
  and safe Latest fallback remain functional without it.
- The extension declares HoldType dictation support. iOS disables or suppresses
  its own Dictation key; a retained disabled icon in the system strip remains
  Apple-owned and is not a HoldType action.
- Microphone, Translate, and Improve may each write Start for one request id.
  Start also freezes that request's standard, translation, or forced-correction
  action. `Listening…` appears only after the app acknowledges real capture. A
  second microphone tap writes Finish; Cancel ends the request without provider
  processing.
- After capture stops, `Processing…` reflects the app-owned provider chain.
  Provider work has explicit timeout and cancellation and never starts
  automatically after relaunch.
- One accepted result auto-inserts exactly once only if the same live extension
  request still owns the current host context. A dismissed/restarted extension,
  host-context change, stale request, or ownership loss disables automatic
  insertion.
- The transient result is published only for the request whose accepted Latest
  record came from that same keyboard capture. Provider failure, cancellation,
  a duplicate command, or a result from another request never fabricates a
  transient result.
- When automatic insertion is unsafe, the accepted result still follows the
  canonical Latest and optional History path. The user may later select
  `Latest` explicitly.
- The extension writes one replaceable command record and the app writes one
  replaceable state/result record. The command carries only a bounded action
  enum; state may carry only a boolean Translation-available capability. Both
  are bounded and expiring. They are not
  a delivery transaction, History store, outbox, receipt, acknowledgement
  family, tombstone, lease, or replay queue.
- The app publishes one separate bounded Latest snapshot to App Group storage.
  The extension remains able to read and insert a safe app-written Latest item
  when restricted-mode access permits it.
- The projection is a replaceable cache, not a second History repository or a
  delivery transaction. It has one app writer and no outbox, receipt,
  acknowledgement, tombstone, or replay protocol.
- The snapshot contains schema version, revision, and one optional Latest item
  with a 10-minute insertion expiry. It contains only result id, exact accepted
  text, creation time, and expiry. No History row, secret, audio, prompt,
  dictionary, provider response, setting, or host context enters the snapshot.
- An already-expired result is omitted from publication. A published result is
  disabled at its 10-minute expiry even while the keyboard remains open. If the
  current canonical Latest is unsafe to project, an empty schema 3 snapshot
  replaces any older shared text rather than presenting it as current.
- A failure to load canonical state preserves the last-known bounded cache;
  ordinary expiry still limits insertion. Legacy schema 1/2 cache files are
  atomically replaced by an empty schema 3 cache at app startup.
- `Latest` inserts only a valid unexpired item and the keyboard never renders or
  previews its text. Full 20-entry History, Delete, Clear All, playback, and
  retention settings remain in the containing app.
- The extension requests no external Settings or containing-app launch. Setup
  recovery is always readable without relying on a system callback.
- Every Latest selection is an explicit insertion. One tap calls
  `textDocumentProxy` once; re-entrant handling of that tap is suppressed.
- The same still-valid result may be inserted again only after another explicit
  user tap. Relaunch, refresh, host-field change, or app return never inserts or
  replays it automatically; V1.1 therefore needs no durable consumed-ID log.
- If the App Group snapshot is unavailable or invalid, `Latest` is disabled
  while punctuation, editing controls, Globe, and the `Ready` surface remain
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
- `RequestsOpenAccess` is true for the production dictation keyboard. Setup and
  Privacy explain why Allow Full Access is needed for keyboard-to-app command
  exchange. The extension itself does not contact OpenAI or transmit host
  keystrokes.
- With Full Access disabled, voice commands are unavailable but local editing,
  Globe, and any safe restricted-mode Latest access remain functional.
- Keyboard setup and Privacy explain that one expiring command/state pair and
  one 10-minute Latest item may enter the local shared container. Each is a
  replaceable bounded record, not a durable transcript history.
- The extension receives no API key or provider client.
- Pending audio and the canonical 20-entry History remain app-private,
  protected, and backup-excluded according to their data type. Raw audio never
  enters App Group storage. Expiry removes command, state, result, and Latest
  eligibility according to their separate bounded lifetimes.
- An idle Keyboard Dictation Session does not retain or upload spoken content.
  Actual capture begins only after Start and ends on Finish, Cancel, timeout,
  interruption, or failure. Product state and the system recording indicator
  must agree with real microphone ownership.
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
- Compact History append, one-tap Copy, swipe Delete, Clear All, cap, and
  failure isolation pass; no detail route, Share, date, or time is rendered.
- Recording Cache off/on, bounded retention, missing-file Play eligibility,
  local playback failure, and playback-to-Voice handoff pass.
- Release navigation contains no placeholder destination.
- Normal iPhone launch shows Voice, Library, History, and Settings in the tab
  shell; qualification routes never become a production root.
- Keyboard tests cover both appearances, recovery instructions, punctuation,
  Delete repeat, Space cursor movement, Return traits, session-state honesty,
  bounded command/state decoding, stale-request rejection, one bounded Latest
  item, expiry, automatic insertion ownership, and explicit Latest insertion.

### Signed Physical iPhone

The KBD-MVP-2 feasibility spike may use the approved split qualification in
`docs/ios-keyboard-dictation-mvp-plan.md`: physical containing-app recorder
controls plus Simulator keyboard evidence. That split avoids the external-
keyboard behavior of iPhone Mirroring and does not waive any item in this later
release gate.

V1.1 is not release-complete until a recorded device pass proves:

- app and extension install with matching signing and App Group configuration;
- keyboard enablement and Globe switching;
- punctuation and editing controls in Notes, Messages, Mail, Safari, and two
  third-party apps;
- restricted-mode local editing and any supported read-only Latest behavior with
  Allow Full Access off;
- Full Access setup and one-writer command/state exchange with it on;
- secure-field, phone-pad, and host-opt-out fallback;
- absence of a Settings launch, containing-app launch, or private Settings
  workaround in the extension;
- app-owned Keyboard Dictation Session start, availability, expiry, and stop;
- keyboard Start, acknowledged Listening, Finish, Cancel, Processing, timeout,
  and one accepted insertion in a still-owned host context;
- background transition, interruption, Low Power Mode, and process-eviction
  behavior without indefinite silent-audio or idle-content capture;
- app foreground recording, Done, Cancel, interruption, and provider timeout;
- rejected automatic insertion after extension restart, host-context change, or
  request expiry, with Latest remaining available as the safe fallback;
- process termination preserves Latest or the one pending attempt;
- effective Keychain and Data Protection behavior.
- after explicit user authorization with a configured provider key, one manual
  Standard-mode smoke proves physical microphone -> OpenAI -> configured text
  rules -> Latest -> History -> same-request keyboard insertion. Automated
  agents do not enter the key or run live-provider tooling without that request.

Simulator evidence cannot pass this gate.

The release candidate uses no keyboard History or Settings launch. Local editing
and explicit Latest are independently useful. Keyboard-controlled dictation
remains a release no-go until the app-owned background-session round trip passes
on a signed physical iPhone and its privacy and energy behavior are acceptable.
Observed competitor behavior alone does not pass this gate.

## Complexity Guardrails

- A new internal abstraction must serve a current V1.1 behavior or required
  release gate.
- Do not add a failed-history, outbox, policy-generation, receipt, lease, or
  capability family to V1.1.
- Do not grow a QWERTY, locale-layout, prediction, or autocorrection engine under
  the command-surface milestone.
- Prefer one owner and one record for one product concept.
- Keyboard dictation adds at most one current command record and one current
  state/result record. It does not reopen the retired persistence architecture.
- Tests protect product invariants and semantic failure boundaries, not every
  implementation micro-state.
- Each checkpoint reports production/test line movement. Growth during a
  simplification checkpoint requires a concrete user-visible justification.

## Verification Mapping

- Scope audit: `docs/ios-v1-scope-reset-audit.md`.
- Development and deletion order: `docs/ios-v1-development-plan.md`.
- Keyboard MVP execution: `docs/ios-keyboard-dictation-mvp-plan.md`.
- Historical physical keyboard evidence remains under `docs/qa/runs/` but does
  not pass the V1.1 device gate.

## Voice Activation Decision

The selected MVP is an app-owned Keyboard Dictation Session, not microphone
access inside the extension. The keyboard controls a session that the user
started in HoldType, and inserts only a result still owned by the live request
and host context. It never launches HoldType, fakes Listening, or records idle
speech. The signed-device feasibility spike is a stop gate: failure does not
justify private APIs, indefinite background tricks, another persistence system,
or a QWERTY detour.
