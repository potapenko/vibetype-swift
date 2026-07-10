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
- A valid completed runtime artifact carries its current app-local file URL,
  duration, and byte count. Before any provider request, the app maps that file
  to a stable attempt-owned relative identifier and writes the identifier to
  the minimal `PendingRecording` journal; the runtime URL is never the durable
  identity.
- The P2 handoff first publishes an app-private protected copy and then commits
  the strict single-record journal defined by `ios-history-and-storage.md`.
  Provider work receives the copy only after its local transcription UUID is
  durable. The recording service's source remains untouched until the complete
  handoff returns, so a local persistence failure cannot trigger provider work
  or destroy the only completed artifact.

## Audio-session behavior

- The containing app owns `AVAudioSession` configuration, activation, and
  deactivation for recording, cues, and local playback.
- Recording start/stop cues are short and non-verbal. Haptics/text state remain
  available when audio cues are muted by system behavior.
- Calls, Siri, alarms, route loss, Bluetooth/AirPods changes, built-in mic mute,
  lock, scene changes, and media-services reset produce explicit interruption
  or recoverable failure state.
- HoldType never continues capture invisibly after an interruption.
- A route change never silently switches into a new recording attempt or
  duplicates the current one.
- Deactivation occurs when capture ends, is cancelled, expires, fails, or is no
  longer needed for local playback/cues.

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
  recording tail. It removes only the unfinished current artifact. In one-shot
  mode it returns to idle; in Quick Session it returns to `ready` while time
  remains. Once a completed artifact is journaled, this action is unavailable.
- `Stop Voice Session` exists only for Quick Session. In `ready` it disarms
  immediately. During `listening` it stops capture and ends the session; a
  valid partial is finalized only into Recover-or-Discard state and is not
  uploaded automatically, while an invalid partial is removed. If an utterance
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

## Provider handoff

- A valid completed recording is recoverable before provider work starts.
- Provider work begins only after capture ends and the recording is journaled.
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
- If the app is suspended after recording, the pending journal remains the
  source of truth; relaunch offers explicit recovery rather than auto-upload.
- An interruption or Quick Session expiry during `listening` stops capture. A
  valid minimum-duration partial artifact is finalized and journaled for an
  explicit Recover or Discard choice, but is not uploaded automatically. An
  invalid/too-short partial is removed. The terminal outcome is `interrupted`
  for the actual lifecycle interruption and `expired` for the Quick Session
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
