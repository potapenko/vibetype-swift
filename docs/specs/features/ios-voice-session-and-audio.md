# iOS Voice Session And Audio

## Goal

Provide reliable foreground dictation in the iOS app and validate a bounded,
visible Quick Session for keyboard-triggered voice input without hiding
microphone activity or losing completed recordings.

## Scope

- foreground one-shot recording in the containing app
- microphone and audio-session lifecycle
- five-minute per-utterance maximum
- fixed five-minute Quick Session hypothesis
- recording tail, cues, interruptions, routes, lock, and background behavior
- completed recording journaling and provider handoff
- cancellation, expiry, and recovery

## Non-goals

- microphone capture inside the keyboard extension
- realtime or streaming OpenAI transcription
- indefinite background recording
- silence detection or automatic endpointing
- keeping the microphone active to finish network work
- bypassing M0B/M0C physical-device gates

## Foreground one-shot behavior

- An explicit Voice action in the containing app starts the foreground flow.
- HoldType checks microphone authorization, provider consent, API-key
  availability, configuration validity, and local storage before capture.
- If authorization is not determined, the explicit action may request it.
- A blocked preflight does not activate `AVAudioSession`, create an audio file,
  or contact OpenAI.
- Active capture shows `listening`, elapsed time, Cancel, and Done.
- The start cue completes before retained audio begins; the stop cue plays only
  after retained audio is finalized so cues are not recorded into the
  utterance.
- Done applies the configured fixed recording tail and then finalizes one local
  recording artifact. The default tail is Off; choices are Off, 0.5, 1.0, 1.5,
  and 2.0 seconds.
- While a tail is pending the state remains `listening`; repeated Done actions
  do not create duplicate finalization or provider work.
- Cancel during capture or tail stops the recorder, removes the current
  incomplete artifact, deactivates the audio session, and makes no provider
  request.
- A single retained utterance has a five-minute maximum. Reaching it fails the
  utterance visibly and does not upload the maximum-duration artifact as a
  successful recording.
- A valid completed runtime artifact carries an opaque descriptor-bound capture
  capability plus duration and byte count. Only the AVFoundation adapter sees
  its transient app-local URL. Before any provider request, Persistence maps
  the capability to a stable attempt-owned Pending relative identifier; the
  runtime URL is never a durable or provider-facing identity.
- The P2 handoff first publishes an app-private protected copy and then commits
  the strict single-record journal defined by `ios-history-and-storage.md`.
  Provider work receives the copy only after its local transcription UUID is
  durable. The recording service's source remains untouched until the complete
  handoff returns, so a local persistence failure cannot trigger provider work
  or destroy the only completed artifact.

### P4D Capture Validity And Durable Finalization

- A P4 foreground artifact is valid only when its canonical validated duration
  is at least 300 milliseconds and strictly less than 300,000 milliseconds,
  with a positive byte count below the Pending limit. The Persistence wire
  format keeps its broader structural range for old and test data; P4D enforces
  the product minimum before a source may become `completed-v1`.
- Done below 300 milliseconds is `Too Short`: HoldType removes only the exact
  active capture source, makes no Pending record or provider request, and keeps
  the prior Latest Result unchanged. An interrupted partial follows recovery
  only at or above 300 milliseconds; a shorter partial is removed.
- Reaching 300,000 milliseconds is the existing maximum-duration failure, not a
  successful partial. It is never uploaded or accepted through ordinary Retry.
- The recorder writes only through the descriptor-bound capture-source owner in
  `ios-history-and-storage.md`. A finalized source is durably marked completed
  before it is copied to Pending. If process loss occurs in that gap, relaunch
  offers Recover Recording or confirmed Discard and never auto-uploads it.
- Normal same-process Done prepares `readyForTranscription` with the frozen
  Settings snapshot. Explicit recovery prepares `awaitingRecovery` with current
  compact transcription settings, then still requires a separate explicit
  Retry. In both cases the provider sees only the protected Pending reader.

### P4 Foreground Preflight And Ownership

- The process owns exactly one foreground voice state across every iPhone and
  iPad scene. A scene may observe and control that owner, but it never creates a
  recorder, provider pipeline, pending-recording store, or recovery slot.
- A new one-shot preflight starts only from an explicit Voice action while the
  process-local owner is inactive. Durable preflight separately proves whether
  a Pending attempt already owns recovery.
- The explicit P4 preflight runs in this order:
  1. atomically acquire the process-local Start admission and reject concurrent
     voice/provider work without disturbing its current owner;
  2. require at least one foreground-active HoldType scene; the initiating
     scene owns any consent or permission presentation;
  3. open and reconcile the canonical app-private storage boundary; a valid,
     unreadable, corrupt, future-version, or commit-uncertain pending slot blocks
     a second capture and presents its owning recovery action;
  4. capture one current durable Settings and Library snapshot and validate the
     requested Standard or Translate intent before any credential operation;
  5. verify the current provider-consent contract and, when absent, obtain an
     explicit durable acceptance before continuing;
  6. resolve one credential generation through the process-owned voice
     preflight; missing, locked, or rejected credentials route to OpenAI setup;
  7. read microphone authorization and request it only when it is not determined;
  8. stop active History playback and deactivate its playback session, then
     configure and activate the foreground recording session, finish any
     enabled start cue, and begin retaining the utterance.
- Failure or cancellation at one step prevents every later step. In particular,
  concurrent work does not disturb its current owner, blocked storage or
  configuration does not inspect consent or read Keychain, missing consent does
  not read Keychain or request microphone access, and denied microphone access
  does not activate audio or create a recording.
- Accepting the provider disclosure is an explicit continuation of the same
  user-started flow. Declining or dismissing it returns to inactive without a
  microphone prompt, file, or provider request.
- Preflight performs no connectivity probe and contacts no provider. Offline or
  transport failure is handled only after a completed artifact is protected and
  journaled.

## Audio-session behavior

- The containing app owns `AVAudioSession` configuration, activation, and
  deactivation for recording, cues, and local playback.
- Recording start/stop cues are short and non-verbal. Haptics/text state remain
  available when audio cues are muted by system behavior.
- Calls, Siri, alarms, route loss, Bluetooth/AirPods changes, built-in mic mute,
  lock, scene changes, and media-services lost/reset produce explicit
  interruption or recoverable failure state.
- HoldType never continues capture invisibly after an interruption.
- A route change never silently switches into a new recording attempt or
  duplicates the current one.
- Deactivation occurs when capture ends, is cancelled, expires, fails, or is no
  longer needed for local playback/cues.

### P4D Foreground Audio Configuration

- P4D uses one process-owned `AVAudioSession` configured while inactive as
  `playAndRecord`, mode `default`, with only `allowBluetoothHFP` and
  `defaultToSpeaker`. This supports recorder input and start/stop cues; when no
  accessory is active, cues use the built-in speaker rather than the receiver.
- HoldType does not force a preferred input or call the transient speaker-port
  override. iOS owns user route selection. Immediately before retained capture
  begins, HoldType freezes the active input port UID, port type, and selected
  input data-source ID when iOS exposes one for the attempt.
- P4D does not enable `mixWithOthers`, `duckOthers`,
  `interruptSpokenAudioAndMixWithOthers`, `allowBluetoothA2DP`, `allowAirPlay`,
  `overrideMutedMicrophoneInterruption`, or the preference that suppresses
  system-alert interruptions. It also leaves iOS 26 high-quality Bluetooth
  recording and far-field input for a later availability-gated physical-device
  decision.
- HFP/AirPods input is eligible. During retained capture or its tail, a missing,
  muted, or changed frozen input stops the attempt under the existing
  valid-partial policy. An output-only route change may continue only when the
  same frozen input tuple remains present and unmuted, the recorder still
  reports active capture, and its input format, sample rate, channel count, and
  I/O status remain valid. Any uncertainty or recorder/format failure stops
  under the valid-partial policy. Route callbacks are serialized through the
  process owner and rejected when their attempt token is stale.
- HoldType observes the stable iOS 17 interruption, route-change, input-mute,
  media-services-lost, and media-services-reset surfaces behind an adapter.
  Interruption end never auto-resumes, even when iOS suggests resume. Media
  services lost during arming cancels the attempt and retires its token. During
  retained capture it immediately retires audio objects and the token, then
  descriptor-validates the bytes already written: a valid partial of at least
  300 milliseconds enters recovery, a short or invalid partial is removed, and
  uncertain validation or removal preserves the exact source as blocked local
  recovery. During finalization it preserves the current source or Pending
  checkpoint and starts no provider. Media reset clears stale audio objects and
  reconstructs them only for a later explicit Start.
- Haptics and system sounds during recording remain disabled. Enabled boundary
  haptics occur before retained capture or after recorder stop. The start cue
  must finish or hit a two-second watchdog before recording begins; failure or
  timeout stops its player and may continue only after scene, route, permission,
  and attempt-token revalidation. The success stop cue plays only after the
  recorder is closed. Cancel or interruption plays no success cue.
- Session activation occurs only after the complete ordered preflight.
  Deactivation first stops every recorder/player, then uses
  `notifyOthersOnDeactivation` on every terminal path. HoldType does not promise
  that the Ring/Silent switch suppresses enabled cues; the Voice & Recording cue
  toggle is the reliable product control.
- Finalization acquires at most one named `UIApplication` background assertion
  before backgrounding can occur. Local recorder close, source completion,
  protected-copy, and Pending-journal work have one ten-second monotonic
  watchdog and the system expiration is an earlier deadline. The assertion is
  always ended. Expiration preserves the exact source or Pending checkpoint,
  starts no provider, and resumes only through foreground reconciliation. This
  assertion never keeps the microphone alive and P4 declares no audio
  background mode.

### P4 Foreground Lifecycle

- P4 declares no audio background mode and does not expose Quick Session. One-
  shot recording is foreground-only even when more than one app scene exists.
- Losing one scene does not interrupt voice work while another HoldType scene
  remains foreground-active. When the last foreground-active scene resigns:
  - an expected microphone-permission prompt may temporarily make the app
    inactive during arming, but audio activation waits until an initiating scene
    is active again;
  - any other aggregate scene loss during arming cancels the start cue, stops
    any recorder or audio I/O already being prepared, deactivates
    `AVAudioSession`, retires the attempt token, rejects late callbacks, and
    returns inactive without retained capture or provider work;
  - listening or a still-cancellable tail stops immediately. A valid partial is
    protected without automatic upload: source-only active/finalizing/completed
    truth presents Recover Recording or Discard, while a successfully journaled
    `awaitingRecovery` owner presents Retry or Discard. An invalid partial enters
    cleanup-only discarding state;
  - already-stopped finalization may use only bounded system-granted execution
    to finish protecting local audio, but it never starts a new provider dispatch
    after the app is no longer foreground-active;
  - an already-journaled processing task deactivates audio and may finish only
    while iOS permits its bounded foreground transport. Suspension or process
    loss preserves explicit Retry-or-Discard recovery and never causes an
    automatic replay.
- Returning to foreground reconciles durable truth and chooses the exact action
  matrix rather than treating every journal as Retry. A positive-byte active,
  finalizing, or completed source without Pending presents Recover Recording or
  confirmed Discard. Preparing state with empty Pending inventory has the same
  actions; exact resumable staging/final audio without a journal presents
  Recover Recording only. A preparing source plus matching journal whose final
  audio is directory-durably absent also presents Recover Recording only. A valid
  `readyForTranscription` or `awaitingRecovery` Pending with valid audio presents
  Retry or confirmed Discard; later Pending phases retain their Saving,
  cancellation, or local-recovery actions. Foreground reconciliation never
  restarts capture or provider work automatically.
- Interruption, input-route loss or change, media-services lost, microphone
  revocation, and input mute use the same visible stop-and-recover policy during
  retained capture. An output-only route notification does not fail an attempt
  only when the complete continuation proof above remains true. Media-services
  reset rebuilds audio objects only for a later explicit Start.

## Quick Session hypothesis

- Quick Session is fixed at five minutes for the first implementation and is
  separate from the five-minute maximum for one utterance.
- It starts only after an explicit foreground action and separate Quick Session
  consent.
- The Voice screen shows `Voice session on`, remaining time, current phase, and
  immediate Stop. The system microphone indicator remains visible.
- In the armed `ready` phase, input samples are discarded immediately in memory
  and are never written, journaled, logged, or uploaded.
- An explicit keyboard mic command during an active session changes to
  `listening` and begins retaining only that utterance.
- Cancel during a Quick Session removes only the unfinished current utterance
  and returns to armed `ready` when the session deadline still permits it.
- Only a justified Full Access bridge may send the explicitly named voice
  actions in this spec and insertion acknowledgements. The extension still
  never receives microphone access.
- The user manually returns to the host app and may need Globe re-selection.
  HoldType never attempts a private automatic return.
- Stop, five-minute expiry, interruption, app termination, and force quit end
  the armed session and microphone deterministically.
- With Full Access off, Quick Session commands are unavailable; foreground
  one-shot recording and read-only/explicit insertion fallback remain.

## Action Semantics

HoldType uses four distinct actions and never labels them all `Stop`:

- `Finish Utterance` (`Done`) is available while `listening`. It applies the
  selected tail, finalizes and journals the current utterance, then starts the
  provider chain. In Quick Session, the armed session may return to `ready`
  after that attempt reaches a terminal result and time remains.
- `Cancel Utterance` is available during `listening` and the still-cancellable
  recording tail. It moves only the unfinished current artifact through durable
  cleanup-only discarding state. In one-shot mode it returns to idle; in Quick
  Session it returns to `ready` while time remains. Once a completed artifact is
  journaled, this action is unavailable.
- `Stop Voice Session` exists only for Quick Session. In `ready` it disarms
  immediately. During `listening` it stops capture and ends the session; a
  valid partial reaches only provider-free durable recovery: a source presents
  Recover Recording or Discard, while an `awaitingRecovery` Pending presents
  Retry or Discard. It is not uploaded automatically, and an invalid partial
  enters discarding cleanup. If an utterance
  was already finalizing because of `Finish Utterance`, Stop disarms the
  session but lets that finalization/provider handoff continue. During
  `processing`, Stop ends the armed microphone/audio state but does not cancel
  the journaled provider attempt.
- `Cancel Processing` is available only for a journaled active provider chain.
  It cancels that task, rejects its late result by attempt ID, and preserves one
  Retry-or-Discard recovery attempt. It does not imply Stop Voice Session; the
  user may stop the session separately.

The containing app presents every action that applies to its current phase.
After M0C, the keyboard may send the same explicitly named action only while a
matching Quick Session/attempt is published and Full Access is live. Without
Full Access, none of these extension-to-app commands is available.

### P4 Voice Action Matrix

- Inactive with no pending recovery presents `Start Dictation`. Translate stays
  visible; an invalid Translation route is unavailable and opens its owning
  Settings destination instead of beginning arming.
- Arming presents progress and `Cancel Start`. Repeated Start is ignored. A
  system permission sheet may finish its own interaction, but a cancelled
  attempt never activates audio afterward.
- Listening presents elapsed time, `Done`, and `Cancel Utterance`. During the
  configured tail, Done is disabled or ignored and Cancel remains available
  until retained capture stops.
- Finalizing presents one non-interactive finishing state. Once protected
  finalization has begun, neither Done nor capture cancellation can create a
  second outcome.
- Processing before accepted text presents the current understandable provider
  stage and `Cancel Processing`. The action is unavailable before the pending
  journal and dispatch identity are durable.
- After accepted text exists, unresolved delivery commit, replacement,
  destination confirmation, Pending-audio removal, or journal retirement
  presents `Saving Result` and `Retry Saving Result`. Provider work is already
  complete, so Cancel Processing is unavailable and Retry Saving resumes the
  last local checkpoint without repeating it. For an `outputDelivery` Pending
  owner, `Recover Recording` appears only when the coordinator proves that no
  accepted destination or ambiguous mutation exists; that explicit action moves
  the exact Pending owner to Retry-or-Discard without another provider request.
  Once a destination exists, local retirement failure can retry only the exact
  remaining cleanup checkpoints.
- While a new result is in `Saving Result`, Voice may also display the preceding
  confirmed, unexpired Latest Result. The new accepted bytes do not become
  Latest until atomic replacement is durably confirmed. A failed invisible
  replacement preserves the prior result; an uncertain replacement blocks Clear
  or another replacement until reconciled. A discarded, expired, or tombstoned
  predecessor is never restored as prior text.
- A valid positive-byte `active-v1`, `finalizing-v1`, or `completed-v1` source
  presents `Recover Recording` and confirmed `Discard`. Preparing state has both
  actions only with empty Pending inventory. Recover Recording finishes the
  source-to-Pending checkpoint as `awaitingRecovery` and starts no provider.
- Valid resumable preparing state with exact staging/final audio but no journal
  presents `Recover Recording` only. Discard is unavailable while any matching
  or ambiguous Pending destination remains. Unknown or malformed source state
  is preserved and presents a local recovery problem rather than a destructive
  action.
- A fresh exact zero-byte `active-v1` source presents confirmed `Discard` only;
  it has no valid recording to Recover. The same exact source may be cleaned up
  automatically only after the bounded one-hour rule.
- A valid `preparing-pending-v1` source with a matching Pending journal but
  directory-durably absent final audio presents `Recover Recording` only. The
  action recreates and validates the exact protected audio, confirms the same
  journal phase, and still starts no provider; ordinary Retry remains
  unavailable until that local repair is durable.
- Recoverable pending audio presents `Retry` and confirmed `Discard`. A new
  Start remains unavailable until one of those actions reaches a durable result.
- Result-ready presents selectable final text, Copy, Share, Use in Practice,
  and confirmed Clear under `ios-output-actions.md`. A prior valid latest result
  may remain visible while a later attempt runs and is replaced only by a newer
  accepted result or explicit Clear.
- P4 never presents `ready`, Quick Session `expired`, or `Stop Voice Session`;
  those states and actions remain behind P6/M0C.
- Every action is at-most-once for its current phase and identity. Repeated taps,
  stale callbacks, another scene, or a late provider completion cannot create a
  parallel recording, duplicate request, second accepted output, or discard a
  newer attempt.

## Provider handoff

- A valid completed recording is recoverable before provider work starts.
- Provider work begins only after capture ends and the recording is journaled.
- Provider work reads the protected recording through the one-shot
  descriptor-backed source defined by `ios-history-and-storage.md`; no provider
  adapter may reopen its app-private absolute URL or materialize an equivalent
  path-based handoff.
- While provider work is processing, the Quick Session may remain visibly
  armed until its own deadline, but another utterance cannot begin until the
  current attempt reaches a terminal state. Stop or expiry deactivates audio
  without deleting the journaled attempt.
- The microphone and audio session are not kept active merely to extend network
  execution.
- Background completion must use a bounded supported execution path. If it
  cannot finish, HoldType preserves the journaled attempt and resumes only when
  allowed, normally after the app returns to foreground.
- `Cancel Processing` follows the action contract above. A new utterance does
  not begin until that pending recovery is resolved.
- OpenAI transcription, optional correction, translation, accepted output, and
  history behavior remain governed by their dedicated specs.
- Quick Session expiry ends the armed microphone/audio state but does not
  cancel an already journaled provider attempt. Late provider results are
  discarded only after explicit processing cancellation, attempt replacement,
  terminal failure, or a mismatched session/attempt identity.

### P4 Provider-Stage Completion

- Transcription, optional remote correction, and Translation each obtain their
  own consent-gated dispatch registration and one-shot result authorization. A
  completed earlier stage never authorizes launch or result consumption for a
  later stage.
- After a non-empty Transcription outcome is consent-consumed, the exact Pending
  owner advances from `transcribing` to `postProcessing` before optional
  correction, local processing, or Translation can produce final output.
- Remote correction remains fail-open. If consent withdrawal cancels correction
  or makes its result ineligible, Standard processing discards that correction
  result and may continue locally from the already consent-consumed
  transcription; it starts no replacement provider request.
- Translation remains strict. If withdrawal prevents Translation launch or
  result consumption, the untranslated intermediate is never accepted, copied,
  shared, or saved as translated output. After provider authority is retired,
  the exact Pending attempt must durably reach `awaitingRecovery` before Retry
  or Discard is offered.
- A failed same-process Pending transition retains the normalized provider
  result only as provider-free local recovery work. It does not return to an
  earlier provider stage or issue another request automatically.
- After any thrown local transition, the attempt owner reloads the exact
  Pending attempt. A visible destination phase is not sufficient evidence of a
  durable commit: the owner must perform the idempotent same-phase durability
  confirmation before continuing. A missing, mismatched, or otherwise
  ambiguous observation keeps provider-free local recovery blocked rather than
  discarding text or replaying provider work.
- Successful-transcription usage is handed off exactly once immediately after
  the normalized non-empty Transcription outcome is consent-consumed. Later
  cancellation, Translation failure, or local transition uncertainty does not
  remove that usage event, and local recovery does not create another one.

## Product states

Active voice work uses one payload-free runtime phase:

- `inactive`
- `arming`
- `ready` (`Voice session on`)
- `listening`
- `finalizing`
- `processing`

`inactive` means no capture, finalization, or provider chain is currently
running. It does not erase a setup requirement, latest result, recoverable
failure, interruption/expiry reason, or delivery outcome. `arming` begins when
an explicit start is accepted and covers preflight, any allowed permission
request, and audio-session activation before retained capture or armed-ready
operation. A blocked arming attempt returns to `inactive` with its separate
setup or failure outcome. `ready` means a Quick Session is already active and
armed; it is not a promise that setup or app activation can begin later. The
configured recording tail remains `listening`. `finalizing` begins after
capture stops and covers completed-artifact validation plus the stable relative
identity and durable journal commit. `processing` begins only after that
recoverable journal commit and covers transcription, correction, translation,
and accepted-result preparation. It may continue after Quick Session Stop or
expiry when the journaled provider attempt remains valid.

The successful-transcription usage handoff is synchronous local bookkeeping
inside `processing` and is non-fatal and non-gating for the voice result. It
never holds or reactivates the microphone, changes `VoiceWorkPhase`, decides
the terminal voice outcome, or repeats a provider request when local usage
persistence fails. Persistence moves off the latency-critical path before this
contract is described as non-blocking.

### Runtime Attempt-Stage Attribution

`VoiceAttemptStage` is a coarse, payload-free runtime classifier for the
operation being attempted when HoldType attributes a failure, recovery
decision, or compact diagnostic event:

- `recordingFinalization` covers the configured recording tail, recorder stop,
  completed-artifact validation, and the recoverable pre-provider handoff after
  retained capture. Recording start, initial preflight, and ordinary retained
  capture are not attempt stages.
- `transcription` begins when the controller commits to provider-specific audio
  transcription and covers request preparation/dispatch, response validation,
  echo rejection, and non-empty transcription acceptance. It does not prove
  that network dispatch was reached.
- `postProcessing` covers output-intent validation plus optional correction,
  local final-text processing, translation, and final accepted-text validation.
  It does not by itself prove that transcription completed.
- `outputDelivery` begins only after accepted text is available and the
  containing app is passing a runtime `OutputDeliveryRequest` to its platform
  output adapter. It does not mean insertion was eligible, attempted,
  submitted, or confirmed.

The stage is runtime attribution, not a state machine or ordered progress
record. It carries no error, text, identifier, timestamp, output intent,
recovery destination, retry eligibility, or user-facing copy. It is independent
of `VoiceWorkPhase`: a recording tail may remain `listening`, transcription and
post-processing normally occur during `processing`, and delivery can outlive
active voice work after accepted text is safe. A stage is not an outcome;
cancellation, interruption, expiry, recoverable failure, and success remain
separate. Observing or changing it never starts work or authorizes Retry,
Discard, delivery, microphone access, or provider access.

For the iOS product flow, a blocked microphone, consent, credential,
configuration, or storage preflight before capture creates no attempt stage.
Legacy platform adapters may retain narrower compatibility mappings while P1
extracts the value, but those mappings do not redefine iOS preflight behavior.

### Runtime Attempt Outcome

`VoiceAttemptOutcome` is the payload-free terminal result presented for one
voice attempt. It has exactly four cases: `resultReady`, `recoverableFailure`,
`interrupted`, and `expired`.

`resultReady` means non-empty accepted text is safe in the containing app; it
does not claim insertion or acknowledgement. `recoverableFailure` means the
completed capture is retained under an eligible failed-attempt owner; the exact
Retry, Discard, setup, and repair actions remain separate. A transient error
without that retained ownership is not recoverable.
`interrupted` is reserved for a real audio/platform lifecycle interruption, not
ordinary user cancellation or blocked preflight. `expired` is reserved for a
listening attempt ended by the independent five-minute Quick Session deadline,
not a provider timeout or the separate per-utterance maximum.

Accepted-output retention expiry and detected delivery-record clock rollback
are not `VoiceAttemptOutcome.expired`. They produce separate content-free output
recovery observations and never produce `resultReady`, Copy, Share, or Use in
Practice while temporally ineligible, even if protected bytes remain available
internally for Clear or later trustworthy maintenance.

Quick Session expiry while merely `ready` creates no attempt outcome. Expiry
while `processing` does not overwrite the still-valid attempt; its eventual
terminal result remains authoritative. Reaching the per-utterance maximum keeps
its distinct visible recording failure and projects `recoverableFailure` only
if a later adapter has actually retained an eligible recovery artifact;
otherwise it produces no `VoiceAttemptOutcome`.

The outcome carries no text, error, reason, identifier, timestamp, retry flag,
setup destination, output-delivery state, user-facing copy, or stable
logging/telemetry category. It is `Equatable`, `Sendable`, non-raw-valued, and
non-Codable. It is runtime
presentation state, not a durable journal, App Group record, keyboard command,
or authority to retry, discard, insert, record, or call a provider.

The value is independent of `VoiceWorkPhase`, `VoiceAttemptStage`, setup, and
`OutputDeliveryState`. P1 macOS compatibility may project only a non-empty
accepted final result as `resultReady`, or the current failed presentation as
`recoverableFailure` when its eligible attempt is still retained. Ordinary
cancel projects no outcome, and macOS does not synthesize `interrupted` or
`expired`. iOS interruption/expiry adapters, detailed portable failure
categories, and durable outcome reconciliation remain later milestone work.

The containing app and keyboard presentations derive their understandable
user-facing state from separate sources instead of persisting or transporting
the phase as a complete product state:

- setup availability presents `needsSetup` or `needsActivation`;
- active work presents `arming`, `ready`, `listening`, `finalizing`, or
  `processing`;
- the attempt outcome presents `resultReady`, `recoverableFailure`,
  `interrupted`, or `expired` while active work may already be `inactive`;
- output delivery presents `confirmedInserted` or `deliveryUnverified` under
  `ios-output-actions.md`.

Each observer presents one understandable projection at a time, but these
underlying concerns are not one mutually exclusive enum. Interruption and
expiry remain distinct terminal reasons even when a compact surface gives them
the same recovery layout. The UI must not label an armed background microphone
session as inactive, and must not label setup-dependent behavior as ready.

## Invariants

- No hidden or automatic recording.
- One active capture and one finalization/provider chain per attempt.
- History playback and retry cannot compete with an active voice phase; their
  ownership and handoff follow `ios-history-and-storage.md`.
- A completed artifact is journaled before provider dispatch.
- Quick Session and per-utterance timers remain independent.
- Armed samples are discarded and never persisted or uploaded.
- Provider execution never justifies keeping the microphone active.
- No raw audio enters the App Group or keyboard extension.
- Every external wait is bounded and cancellation-aware.
- A failed or interrupted attempt never overwrites previously accepted text.
- Runtime attempt-stage case order has no meaning and is never used as a
  persisted resume position.

## Edge cases and failure policy

- Missing permission, key, consent, configuration, or storage fails before
  capture and routes to the owning setup surface.
- Too-short, empty, missing, corrupt, or unsupported audio is not uploaded.
- If journaling fails, HoldType preserves the protected artifact where possible,
  reports local recovery failure, and does not start provider work.
- If the app is suspended after recording, the furthest durable source or
  Pending checkpoint remains authoritative. Source-only positive-byte active,
  finalizing, completed, or empty-inventory preparing state offers Recover
  Recording or Discard. Fresh zero-byte active is Discard-only. Preparing state
  with exact resumable Pending audio offers Recover Recording only; a valid
  `awaitingRecovery` Pending offers Retry or Discard. None auto-uploads.
- An interruption or Quick Session expiry during `listening` stops capture. A
  valid minimum-duration partial first becomes a recoverable source and, only
  if bounded local handoff completes, an `awaitingRecovery` Pending. The former
  presents Recover Recording or Discard; the latter presents Retry or Discard.
  An invalid/too-short partial enters cleanup-only discarding state. The
  terminal outcome is `interrupted` for the actual lifecycle interruption and
  `expired` for the Quick Session
  deadline; recovery actions remain separate from that reason.
- Quick Session expiry in `ready` simply disarms the session. Expiry in
  `processing` stops audio and preserves the active provider/pending state;
  its matching result may still complete normally.
- If Quick Session background behavior uses unacceptable battery, fails to stop
  deterministically, or is rejected by App Review, M0C fails and the product
  retains foreground one-shot dictation.
- If the current host field identity is absent or changes, audio processing may
  still finish, but automatic insertion is disabled under the output spec.

## Route / state / data implications

- Voice is a top-level containing-app destination.
- The containing app is the sole audio-session and recording owner.
- Quick Session state may publish only compact, expiring non-secret status to
  the App Group.
- `VoiceWorkPhase` is a runtime domain value, not a Codable journal or App Group
  schema. A production bridge maps it into its own versioned transport record.
- Protected recording files and pending journals remain app-private and are
  excluded from backup.
- Recording cache policy is separate from pending-attempt recovery.

## Background Audio Release Gate

- The foreground one-shot P4 build must not declare `UIBackgroundModes=audio`
  or an equivalent background-audio capability.
- That capability may be added only in the isolated P6/M0C physical-device
  spike for a Quick Session that the user explicitly started while HoldType was
  foreground-active. It must never be used merely to extend extension or
  network execution.
- M0C inspection must verify the final processed app `Info.plist`, entitlement
  set, system microphone indicator, and deterministic Stop/expiry behavior.
- If M0C fails for reliability, battery, review, or policy reasons, the
  capability is removed from the release target before shipment and Quick
  Session remains unavailable. Foreground one-shot dictation stays complete.

## Verification mapping

- Unit-test preflight ordering, state transitions, duplicate actions, tail
  cancellation, timer separation, journaling-before-provider, late-result
  rejection, and bounded cancellation with fakes and clocks.
- Test every action in every phase, including Stop Voice Session during ready,
  listening, Finish-triggered finalizing, and processing, with valid/invalid
  partial artifacts and no accidental provider cancellation.
- Simulator-test foreground state and route presentation without live provider
  or microphone dependence.
- Physical-device M0C must cover background/foreground transitions, Stop,
  expiry, force quit, lock, calls, Siri, alarms, Bluetooth/AirPods routes,
  media-services reset, Low Power Mode, and battery behavior.
- Physical evidence must prove provider completion/resume without retaining the
  microphone solely for network work.
- Build inspection must prove P4 has no background-audio declaration and that
  only an M0C-approved release configuration contains it.
- Record every physical pass in `docs/qa/runs/` with device, OS, state,
  expectation, result, and gate decision.

## Unknowns requiring confirmation

- Whether Live Activity is included after the basic M0C path passes. It is a
  visibility/control surface, not a background-execution mechanism.
