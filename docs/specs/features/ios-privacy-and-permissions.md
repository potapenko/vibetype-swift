# iOS Privacy And Permissions

## Goal

Make microphone capture, third-party keyboard access, Full Access, OpenAI
processing, and local retention understandable before HoldType uses them.

Keep system permissions separate from product setup and never imply that the
containing app can grant or reliably inspect settings owned by iOS.

## Scope

- microphone authorization in the containing app
- keyboard enablement and Full Access setup
- OpenAI audio/text-processing consent
- separate Quick Session microphone consent
- system Settings routing and truthful readiness status
- App Privacy, privacy manifests, and default-log boundaries

## Non-goals

- legal privacy-policy wording
- Accessibility or Input Monitoring permission on iOS
- accounts, analytics, telemetry, advertising, or cloud sync
- Nearby Text Context or server-side processing of ordinary keystrokes
- automatic permission changes or private Settings URLs

## Permission and setup model

- Only the containing app requests microphone authorization and captures audio.
- The keyboard extension never requests or receives microphone access.
- Keyboard enablement and Full Access are user-controlled system settings, not
  permissions HoldType can grant programmatically.
- Full Access is not microphone permission. It is requested only after M0
  physical-device validation justifies extension-owned command and
  acknowledgement writes.
- Speech Recognition permission is not requested because the first product
  does not use Apple's Speech framework.
- Ordinary typing remains available offline and without Full Access.
- Without Full Access, the keyboard keeps its bundled typing fallback and may
  consume only the read-only shared state proven by M0B.
- iOS does not need macOS Accessibility, Input Monitoring, launch-at-login, or
  active-app automation setup.

## User-visible behavior

- First launch explains the containing app, keyboard extension, manual return
  to the host app, and why HoldType cannot modify Apple's keyboard.
- HoldType does not request microphone permission on launch. The first explicit
  app voice action may trigger the normal iOS prompt.
- Microphone status is shown as `allowed`, `denied`, `not determined`, or
  `unavailable`. Reading status never starts capture or creates a file.
- Denied or unavailable microphone state blocks voice input but leaves Library,
  History, Settings, diagnostics, and ordinary keyboard typing usable.
- A denied state offers a public Open System Settings action and does not
  repeatedly prompt.
- Keyboard setup provides a public route to relevant system settings when
  available, written version-appropriate fallback steps, and a practice field.
- The app never claims it enabled the keyboard or made it the default.
- Extension readiness is based on a guided practice result and fresh extension
  evidence, not `UITextInputMode.activeInputModes` or another fingerprinting
  shortcut.
- The containing app shows Full Access only as `recently verified enabled` or
  `not currently verified`. A stale heartbeat never becomes a confident
  `disabled` state.
- Inside the extension, live `hasFullAccess` may explain that voice commands are
  unavailable while ordinary typing continues.

### P4D Microphone Permission Adapter

- The iOS 17+ containing app reads
  `AVAudioApplication.shared.recordPermission` and calls
  `AVAudioApplication.requestRecordPermission` only from the explicit Start
  continuation when status is not determined. It does not use the deprecated
  `AVAudioSession` permission API.
- Permission completion is treated as an untrusted asynchronous callback. The
  process owner revalidates the initiating scene, attempt token, current
  provider consent, credential generation, and aggregate foreground activity
  before audio configuration or source creation.
- One explicit permission request may wait for at most 120 monotonic seconds.
  Timeout or caller cancellation retires that Start attempt, creates no audio
  session or file, and returns to an honest non-recording failure state. A
  later system callback may change the next passive permission observation,
  but it cannot resume the expired attempt or continue its preflight.
- Denied permission creates no audio session or file and offers the public app
  Settings URL. Granted permission with no usable input is `unavailable`, not
  `listening`. Passive Privacy & Permissions status never prompts.
- The containing-app purpose string is exactly:
  `HoldType uses the microphone to record speech you choose to transcribe.`
  The keyboard target has no microphone purpose string, permission adapter,
  AVFAudio dependency, or Speech permission.

## Provider consent

Before the first OpenAI request, HoldType explains and obtains explicit
agreement that:

- the current recording is sent directly to OpenAI for transcription;
- the selected model/language plus any configured transcription prompt,
  dictionary spelling guidance, and enabled emoji-command hints may be part of
  that request;
- enabled correction or translation may send transcribed text and the selected
  correction or translation prompt in additional requests before final
  acceptance; Translation also sends the resolved source/target language route;
  local emoji-command definitions and replacement rules are not sent as
  correction or translation configuration, although translated source text may
  already reflect local post-processing;
- the user's API key is stored only in the containing app's Keychain and is
  sent directly to OpenAI to authenticate each request;
- HoldType does not copy the key into the extension, App Group, logs, or a
  HoldType server;
- ordinary keystrokes and surrounding host-field text are not sent;
- in P4, completed audio is protected locally before the request and remains
  only until accepted-output cleanup or explicit Pending Retry/Discard; accepted
  text is the app-private Latest Result until confirmed Clear, atomic
  replacement, or its 24-hour safety expiry;
- P4 does not add accepted or failed History rows or Recording Cache. Enabling
  those P5 retention paths is a disclosure change that requires the then-current
  consent version before provider work continues.

Declining provider consent leaves local settings and typing available and
prevents provider requests. Consent can be reviewed later from Privacy &
Permissions.

`Withdraw OpenAI Processing Consent` is an explicit confirmed action on that
surface. It immediately blocks future provider requests, best-effort cancels an
active request, and makes any matching late result ineligible. Active capture
stops without upload; a valid completed/partial artifact follows explicit
Recover-or-Discard policy. Withdrawal does not delete the API key, settings,
History, latest result, recordings, or usage; each has its own control. A
request already received by OpenAI cannot be recalled, which the confirmation
states. Re-enabling provider work requires accepting the current disclosure
again.

HoldType stores the consent contract version and acceptance date locally. A
material change to provider, transmitted data categories, or purpose requires
renewed consent before the changed request path runs.

### P4 Provider-Consent Record And Gate

- The exact path, wire format, CAS, durability, reset, and authorization contract
  lives in `ios-provider-consent-record.md`. Provider consent contains only
  schema version, unique repository epoch, positive revision, disclosure-
  contract version, `accepted` or `withdrawn` state, and canonical decision date.
  It contains no content, key metadata, configuration, provider response, or
  device/scene identity.
- Missing, withdrawn, older-contract, corrupt, future-version, unavailable, or
  commit-uncertain data is not consent. It blocks provider dispatch and
  microphone activation for a new P4 attempt. Corrupt or unsupported data is
  preserved; Privacy & Permissions offers an explicit confirmed reset followed
  by review of the current disclosure rather than treating it as declined or
  accepted.
- The record is separate from `ios-app-settings.json`, Keychain, App Group, the
  keyboard, History, diagnostics, and provider payloads. It is never logged or
  reflected with a path or raw persistence error.
- One process-owned consent owner serializes review, acceptance, withdrawal,
  reset, and voice-preflight observations across scenes. Every mutation requires
  the exact observed epoch, revision, and process gate fence; each committed
  decision increments the revision, and an explicit unreadable-data reset
  requires a fresh epoch. Withdrawal or Reset advances the fence before file
  I/O, so even a failed write invalidates every earlier observation. A scene-
  local Boolean or a previously rendered status never authorizes provider work.
- Acceptance commits the current disclosure version, epoch, and revision before
  P4 may resolve the credential, request microphone permission, activate audio,
  or continue the same explicit Start action. A stale queued Accept cannot
  overwrite a later confirmed Withdrawal.
- Every provider stage, including transcription, correction, and translation,
  is bound to the same current accepted consent epoch, revision, exact consent-
  file revision, gate fence, and canonical physical repository root. Every
  register, launch, result handoff, and result consume rereads that durable
  snapshot and revalidates the root before its non-suspending gate transition.
  Validation, cancellation registration, and launch permission are one atomic
  gate operation; result authorization is consumed once under that same gate. A
  stage holding older, same-root-replaced, deleted, unavailable, or alternate-
  root authority cannot dispatch, and a result that returns after withdrawal,
  reset, supersession, root substitution, or duplicate consumption cannot
  become accepted output.
- Withdrawal first closes the process-wide dispatch gate and invalidates the
  accepted revision, then atomically persists `withdrawn`. The UI does not claim
  completion until persistence is confirmed. If persistence fails, the process
  stays fail-closed and shows a retryable local error; it does not restore the
  old in-memory authorization merely because old durable bytes may survive.
- After the gate closes, arming ends; active capture stops without upload; a
  valid partial or completed local artifact becomes `awaitingRecovery`; and an
  active provider task is cancelled through its normal authorization-retirement
  path. Matching late output is rejected. Already committed accepted output
  remains available, and Retry stays blocked until the current disclosure is
  explicitly accepted again.

## Quick Session consent

Before the first Quick Session, HoldType separately explains and obtains
agreement that:

- the microphone session remains active while the five-minute session is
  armed, including while HoldType is in the background;
- the system microphone indicator remains visible;
- samples in `ready` are discarded immediately and are neither saved nor sent;
- only an explicit keyboard mic action begins retaining the current utterance;
- the session uses battery and ends through Stop, expiry, interruption, app
  termination, or force quit;
- provider work after recording does not justify keeping the microphone active.

Provider consent does not substitute for Quick Session consent. Declining Quick
Session consent preserves foreground one-shot dictation.

`Withdraw Quick Session Consent` immediately runs Stop Voice Session, blocks
future Quick Sessions, and preserves foreground one-shot dictation. If an
utterance is active, valid partial audio becomes Recover-or-Discard and is not
uploaded automatically; an already journaled provider attempt follows its own
processing state. Withdrawal does not revoke microphone permission or OpenAI
processing consent. Re-enabling Quick Session requires accepting its current
disclosure again.

## Full Access disclosure

Before routing the user to enable Full Access, HoldType states:

- it enables extension-to-app voice commands and insertion acknowledgements for
  an already active bounded session;
- it does not give the extension microphone access;
- allowed bridge data is limited to versioned command/session/transcript IDs,
  compact state, requested output intent, an opaque source document identifier,
  schema/revision and creation/expiry timestamps, accepted-result
  acknowledgement, and the content-free readiness heartbeat;
- final normalized accepted text is published only by the containing app in a
  short-lived read-only result snapshot under the same contract whether Full
  Access is on or off; Full Access does not authorize the extension to write or
  upload that text;
- the API key, raw audio, prompts, history, ordinary keystrokes, surrounding
  text, host-app identity, provider payloads, and analytics are excluded;
- ordinary typing still works without Full Access, and explicit Insert works
  after M0B proves the read-only path. Copy is always available in the
  containing app; keyboard-level Copy requires a separate M0C physical-device
  validation and is not promised in the no-Full-Access mode.

## Data and disclosure boundaries

- `NSMicrophoneUsageDescription` uses product-specific language.
- For truthful insertion acknowledgement and safe Undo, the active extension
  may compare the immediately available post-insert text suffix with the exact
  text it just submitted. This narrow in-memory comparison is not Nearby Text
  Context: it is never persisted, bridged, logged, or sent to OpenAI, and no
  unrelated surrounding text is retained.
- Every executable bundle includes the privacy manifest required by the APIs it
  actually uses.
- P4D-5 freezes the containing-app manifest as non-tracking collection of
  `Audio Data` and `Other User Content` for App Functionality. Both categories
  are conservatively marked linked because each provider request is
  authenticated to the user's configured OpenAI account. The containing app
  also declares File Timestamp reason `C617.1` for `stat`, `fstat`, and `lstat`
  metadata checks restricted to its app and App Group containers.
- The P4 keyboard manifest declares no tracking domains, collected data, or
  required-reason API category. It reads only the local Phase-0 App Group
  snapshot and sends nothing off-device. A future keyboard API or bridge change
  must update this contract before its Release build is approved.
- System Boot Time reason `35F9.1` is not declared merely because HoldType uses
  monotonic deadlines: the current production sources call `clock_gettime`,
  which is not in Apple's current System Boot Time required-reason list. If the
  generated Xcode privacy report detects a covered API, this spec and manifest
  must be updated together before release.
- App Store privacy answers describe the real Audio Data and Other User Content
  path plus OpenAI as the third-party processor.
- Nearby Text Context is unavailable on iOS in the first release.
- Live Activity, notifications, and Lock Screen surfaces never display
  transcripts or other sensitive content.
- No analytics, telemetry, advertising identifiers, contact access, location,
  or cloud sync is added implicitly.
- Default logs and diagnostic bundles exclude API keys, transcripts, prompts,
  dictionary entries, replacement rules, surrounding text, raw audio, ordinary
  keystrokes, host-app identity, and full provider payloads.

## Invariants

- No microphone capture without explicit user action and authorization.
- No hidden, indefinite, or ambiguously labelled background microphone session.
- No provider request before the applicable provider consent.
- No Quick Session before its separate microphone-session consent.
- No Full Access dependency for ordinary offline typing.
- No private `prefs:` URL or undocumented automatic return mechanism.
- No passive Keychain read merely to refresh a permission screen.
- Revoking permission or Full Access cannot expose secrets or silently broaden
  fallback behavior.

## Edge cases and failure policy

- If microphone permission is revoked during capture, recording stops. A valid
  partial that can be finalized and durably journaled becomes explicit
  recovery; an invalid or unprotected partial is removed. Setup then shows the
  denied state and nothing uploads automatically.
- If Full Access is revoked, extension writes stop, stale acknowledgements are
  ignored, ordinary typing remains available, and voice falls back to explicit
  app actions or read-only insertion.
- If the keyboard is disabled or rejected by a host app, HoldType explains the
  platform limit and does not classify it as a failed voice session.
- If system Settings cannot be opened, HoldType keeps written navigation steps
  visible.
- If a privacy manifest or purpose string is missing from a built artifact,
  release verification fails; the UI must not be used as substitute evidence.

## Route / state / data implications

- Privacy & Permissions is an app Settings destination.
- Setup progress distinguishes microphone, keyboard guidance, Full Access
  verification, API-key readiness, provider consent, and Quick Session consent.
- Consent records contain only versioned boolean/date metadata, not user
  content.
- Keyboard heartbeat and Full Access verification are short-lived App Group
  state governed by `ios-keyboard-shared-state.md`. A supported heartbeat is
  fresh for five minutes; expiry immediately presents only `not currently
  verified`, and the extension physically removes its record when it next runs
  with the required access.

## Verification mapping

- Test microphone states, first explicit request, denial, revocation, and public
  Settings-route fallback with fakes.
- Test provider and Quick Session consent independently, including decline and
  later review, withdrawal during idle/listening/processing, exact data
  isolation, and explicit re-consent.
- Test Full Access stale-state presentation and no confident containing-app
  `disabled` claim.
- Inspect built app and extension privacy manifests and purpose strings.
- Generate the Xcode privacy report and inspect the App Privacy Report on a
  physical device before release.
- Test default-log, bridge, and diagnostic export redaction using forbidden
  sample values.

## Unknowns requiring confirmation

- Final legal privacy-policy wording and App Store privacy answers are release
  artifacts derived from the implemented data paths.
