# iOS Voice Session And Audio

Status: foreground-audio reference for V1.1. `ios-v1-release.md` is authoritative
for current release scope. Every Quick Session clause in this document is
historical design exploration, not an active product requirement. V1.1 has no
standalone Quick Session duration contract; promoting one requires a new product
review and an explicit active-spec update.

## Goal

Provide reliable foreground dictation in the iOS app without hiding microphone
activity or losing completed recordings.

## Scope

- foreground one-shot recording in the containing app
- microphone and audio-session lifecycle
- configurable 1-15 minute per-utterance maximum, five minutes by default
- historical Quick Session design hypotheses, retained only as non-normative
  reference
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
- A single retained utterance has the maximum selected in Settings: one through
  fifteen whole minutes, five minutes by default. The value is frozen when Start
  succeeds; changing Settings affects only the next attempt. Reaching the frozen
  limit performs a normal automatic Finish: HoldType closes capture, protects
  the completed artifact as Pending, and continues normal provider processing
  exactly once.
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

- Automatic provider admission requires a trusted finalized duration from 300
  milliseconds through the attempt's frozen recording limit plus 2,000
  milliseconds and a positive byte count below the Pending limit. The absolute
  supported-media ceiling is 902,000 milliseconds. If the media probe reports
  invalid metadata or less than 300 milliseconds, the recorder's frozen
  monotonic elapsed time is the fallback; that fallback is clamped to the
  attempt-specific finalized-media bound and committed durably before provider
  work. A media value beyond that bound is suspect and uses the same bounded
  fallback or unknown `0`.
- Exact empty Done is removed. Every non-empty bounded finalized source is
  durably completed instead of being deleted: without a trusted media or
  monotonic duration it stores the internal unknown/suspect value `0`, remains
  playable and discardable, and is excluded from automatic provider dispatch.
  Explicit Transcribe/Retry may make one user-authorized provider attempt from
  that descriptor-validated source.
- Reaching the frozen capture deadline is a successful automatic Finish,
  not a maximum-duration failure. For a bounded positive-byte artifact, a
  duration beyond the post-close tolerance uses the clamped monotonic fallback
  or unknown duration `0`; it remains recoverable and is never deleted solely
  because of duration. Oversize or identity/protection uncertainty remains
  blocked local recovery.
- Frozen monotonic elapsed time at or beyond the selected deadline outranks the recorder
  delegate's `successfully` flag when choosing the terminal cause. A false flag
  remains diagnostic evidence, but the attempt still follows the one
  maximum-duration completed path, protected retention, and exactly-once
  provider continuation.
- The recorder writes only through the descriptor-bound capture-source owner in
  `ios-history-and-storage.md`. A finalized source is durably marked completed
  before it is copied to Pending. If process loss occurs in that gap, relaunch
  offers Recover Recording or confirmed Discard and never auto-uploads it.
- Normal same-process Done prepares `readyForTranscription` with the frozen
  Settings snapshot. Explicit recovery prepares `awaitingRecovery` with current
  compact transcription settings. Passive Voice recovery still requires a
  separate explicit Retry. The Saved Recording Transcribe/Retry action may
  perform those two exact durable steps as one user action; if promotion fails,
  the completed source remains playable and recoverable. In every case the
  provider sees only the protected Pending reader.

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
- Warnings are relative to the selected boundary: 60, 30, 10, 8, and 6 seconds
  remaining, then every second from 5 through 1. A one-minute limit omits the
  warning at Start, so its first audible warning has 30 seconds remaining. The
  boundary closes the recorder before its distinct stopped-at-limit feedback.
- In-capture warning tones play only when the current route is private, such as
  headphones or AirPods. The built-in speaker uses haptics for warning
  milestones and countdown text during the final 15 seconds so warning audio is
  not captured in the utterance.
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
  descriptor-validates the bytes already written: every bounded non-empty
  regular partial enters recovery, using duration `0` when short, over-bound,
  invalid, or timed-out metadata cannot be trusted. Exact empty enters
  Discard-only state without provider work; identity, protection, size, or read
  uncertainty preserves the exact source as blocked local recovery. During
  finalization it preserves the current source or Pending
  checkpoint and starts no provider. Media reset clears stale audio objects and
  reconstructs them only for a later explicit Start.
- The audio session permits haptics during recording so the final-minute
  speaker-route warnings remain tactile. HoldType itself never plays those
  warning pips through the built-in speaker; audible in-capture warnings remain
  private-route only. Boundary haptics occur before retained capture or after
  recorder stop. The start cue
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

### P4D-2 Adapter And Recorder Feasibility Gate

- P4D-2 keeps UIKit and AVFAudio production adapters in the containing-app
  target. `HoldTypeIOSCore` remains cross-platform and receives no UIKit,
  `AVAudioSession`, `AVAudioRecorder`, permission, or background-task type.
- Before a live permission request exists, the containing app declares exactly
  `NSMicrophoneUsageDescription = HoldType uses the microphone to record speech
  you choose to transcribe.` The keyboard plist, entitlements, and link graph
  receive no microphone or audio addition. No Speech-recognition purpose string
  or audio background mode is added.
- The iOS 17 permission adapter reads
  `AVAudioApplication.shared.recordPermission`, requests only from an explicit
  Start while the value is undetermined, and fails closed for an unknown value.
  A late completion cannot bypass the current attempt token, active-scene,
  consent, credential, or storage revalidation.
- Persistence creates and pins the descriptor-bound source before a recorder
  receives its transient URL. `AVAudioRecorder` may be used only as a
  fail-closed candidate: source identity, xattrs, protection, link count, mode,
  and path agreement are revalidated after initialization and
  `prepareToRecord()` and again after close. It never starts retained capture
  after a failed proof.
- Release approval additionally requires a bounded physical-device probe around
  a short real recording. Apple documents that `prepareToRecord()` creates and
  may overwrite its URL but does not promise inode or metadata preservation;
  simulator behavior is not sufficient evidence. If the device proof fails,
  HoldType uses a descriptor-backed AudioToolbox/AVAudioEngine writer without
  weakening the frozen capture-source contract.
- `AVAudioRecorderDelegate` is not the sole stop authority because an audio
  interruption may omit its finish callback. Session interruption, route,
  input-mute, media-lost, scene, token, watchdog, and explicit actions all
  converge on one idempotent owner stop. Interruption end and media reset never
  resume automatically.
- Recorder time is presentation-only. Canonical duration and byte count come
  from bounded post-close descriptor media validation because recorder time may
  reset after stop. Complete-protection unavailability after lock or background
  is blocked local recovery, never absence, corruption, success, or a reason to
  weaken protection.
- iOS 26 high-quality Bluetooth recording and iOS 26.2 far-field input remain
  outside P4D-2. No availability guard or dormant reference to either API is
  added in this milestone.
- P4D-2 may implement and fully fake-test capture source, permission, session,
  route events, cues/haptics, bounded finalization, and the fail-closed recorder
  candidate without production composition or UI. P4D-3 remains the first
  milestone that binds those adapters into the process Voice workflow.

### P4D-3 Production Composition

- The containing-app composition constructs exactly one process-lifetime Voice
  workflow, `IOSForegroundVoiceController`, permission adapter, audio-session
  adapter, feedback adapter, finalization owner, and recorder factory. Every
  scene receives that same controller and workflow identity. The controller is
  still constructed when secure credentials are unavailable: provider-free
  observation, Recover Recording, and confirmed Discard remain available,
  while Start or Retry that requires OpenAI routes to its owning setup state.
- One process scene registry tracks opaque scene identities and aggregate
  foreground-active state. Start binds consent and microphone-prompt
  presentation to the initiating active scene. That ownership is never
  transferred; if the initiating scene disappears before either decision
  finishes, arming ends and late completions cannot activate audio or start a
  provider.
- Production Start follows the frozen preflight order above without parallel
  lookahead. After an allowed microphone request returns, and again after the
  start cue, the workflow revalidates the current attempt token, initiating
  scene, aggregate foreground state, durable storage owner, Settings and
  Library snapshot, consent, credential generation, permission, and input route
  before retained capture begins.
- Aggregate scene inactivity is tolerated only while the current initiating
  scene owns an expected system microphone-permission sheet. Audio activation
  waits until that scene is active again. Any other last-active-scene loss uses
  the one idempotent stop owner, rejects late callbacks, and follows the frozen
  partial-capture matrix. Interruption end, media reset, scene reactivation,
  and permission completion never auto-resume or create another attempt.
- Process-launch recovery is provider-free and ordered: first run one bounded
  orphan repair for canonical `recording` or `finalizing` capture metadata,
  then reconcile the capture-source namespace, run the existing containing-app
  lifecycle recovery, and derive one combined source-and-Pending observation
  before Start can be offered. The repair validates the exact descriptor-open
  media with the existing two-second validator. Every bounded non-empty regular
  source becomes durable completed recovery; short, over-bound, invalid, or
  timed-out metadata uses unknown/suspect duration `0`, stays visible with
  Play/Transcribe/Discard, and never auto-dispatches. Exact empty media remains
  Discard-only without deletion, while protected-data uncertainty or write
  failure remains blocked and retriable at a later process launch. Foreground
  opportunities never run this orphan repair. If the first ordinary capture
  observation is blocked unknown and containing-app lifecycle recovery
  completes, the same process-launch opportunity reconciles the capture-source
  namespace exactly once more unless the orphan repair itself was blocked.
  The resulting capture observation is final for that opportunity: another
  blocked-unknown result remains blocked and starts no loop, timer, or follow-up
  signal. Recovery never reads Keychain, requests permission, activates audio,
  constructs a provider request, or automatically retries retained work.
- The workflow depends on one process-owned History-playback arbitration
  protocol. Until History playback UI exists, production supplies an explicit
  no-active-playback implementation. The preflight still performs the same
  stop-and-deactivate handoff through that boundary before recording-session
  activation, so later History playback cannot bypass or reorder the contract.
- The process credential bridge resolves only the canonical `.voicePreflight`
  purpose. A successful preflight returns an opaque process-local proof bound
  to the exact credential generation, never the credential itself. The proof,
  controller, workflow request, UI state, reflection, and diagnostics contain
  no API key or traversable credential owner.
- Immediately before an initial provider call or provider-authorized local
  Retry, the bridge resolves `.voicePreflight` again and materializes only the
  exact current credential. Replacement, removal, coordinator-known provider
  rejection, coordinator loss, access failure, or a mismatched or already-
  consumed proof fails before Core receives a provider request. A replacement
  from generation A to B cannot use A's proof, even when both keys are otherwise
  valid. A rejection first learned from the current network request remains a
  Core/provider outcome rather than a preflight promise.
- Missing credential coordination does not prevent construction of the Voice
  graph. Explicit provider preflight reports unavailable, a confirmed missing
  item reports setup required, and provider-free observation and local Retry
  remain available. A provider-free local Retry bypasses credential resolution
  completely and cannot read Keychain as a side effect.
- The credential bridge only validates authority and maps the frozen workflow
  request or fresh Retry authorization into the Core processor. It adds no
  connectivity probe, provider call, retry loop, or timeout; external timeout
  and cancellation ownership remain inside the Core/provider boundary.
- P4 boundary haptics are always enabled. Audible start and success cues follow
  the existing Voice & Recording cue preference; P4D-3 adds no haptic setting.
- After aggregate foreground loss, bounded local finalization may protect the
  exact stopped source or Pending checkpoint, and already-dispatched work may
  finish only as iOS permits, but no new provider dispatch may begin. P4D-3
  adds no Voice UI, Quick Session, background-audio mode, App Group
  publication, keyboard command, or keyboard dependency.
- A same-process local-recovery result separately states whether its retained
  checkpoint is provider-free or requires current provider authority. The
  coarse attempt stage and Saving disposition never imply that requirement.
- Retained work that may still start Transcription, correction, or Translation
  resumes only after the explicit Retry supplies a newly resolved credential
  generation and a current accepted consent observation. HoldType validates and
  binds that fresh pair before any provider dispatch; a missing or stale pair
  leaves the same local checkpoint blocked without progress or mutation. A
  retained credential or consent observation from the failed invocation is
  never reused after replacement, removal, withdrawal, or reacceptance.
- Provider-free checkpoints do not resolve Keychain, inspect consent, or require
  provider authority. They include durable recovery commits, retained accepted
  text and output saving, provider-free local post-processing, and a persisted
  `transcribing` state whose live one-shot dispatch is gone. Retrying those
  checkpoints may finish only their exact local work and never repeats a
  completed or lost Transcription, correction, or Translation request.

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
  - listening or a still-cancellable tail stops immediately. A bounded non-empty
    partial is protected without automatic upload: source-only
    active/finalizing/completed truth presents Recover Recording or Discard,
    while a successfully journaled `awaitingRecovery` owner presents Retry or
    Discard. Untrusted duration metadata enters unknown-duration recovery; only
    exact empty enters non-provider Discard-only state, while validation
    uncertainty remains blocked;
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

This section is retained as historical design exploration. It does not define
current production behavior, and no fixed Quick Session duration may be inferred
from it.

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
- Only this explicitly invoked Cancel/Discard action owns destructive cleanup.
  Task cancellation, controller teardown, scene replacement, bridge-state
  publication failure, and supersession preserve any possibly non-empty source.
- `Stop Voice Session` exists only for Quick Session. In `ready` it disarms
  immediately. During `listening` it stops capture and ends the session; a
  bounded non-empty partial reaches only provider-free durable recovery: a
  source presents Recover Recording or Discard, while an `awaitingRecovery`
  Pending presents
  Retry or Discard. It is not uploaded automatically. Short, over-bound,
  invalid, or timed-out duration metadata records unknown duration rather than
  deleting the bytes; exact empty remains non-provider Discard-only. If an utterance
  was already finalizing because of `Finish Utterance`, Stop disarms the
  session but lets that finalization/provider handoff continue. During
  `processing`, Stop ends the armed microphone/audio state but does not cancel
  the journaled provider attempt.
- `Cancel Processing` is available only for a journaled active provider chain.
  It cancels that owned task and rejects its late result by attempt ID. The
  playable audio remains durable. Cancellation before transcription dispatch
  preserves Retry or Discard; cancellation after dispatch began is provider-
  outcome-uncertain, hides ordinary Retry, and preserves Play and Discard. It
  does not imply Stop Voice Session; the user may stop the session separately.

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
  not begin until its retryable or outcome-uncertain recovery is resolved.
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

### Frozen P5H Foreground History Handoff

P5H-0 freezes the P5 transition while production remains on the P4 app-only
path. P5H-2 lands and tests the following History-capable foreground internals
behind production disclosure version `1` and app-only selection. P5H-3 lands the
combined local History facade/state owner without activating them. P5H-4 first
lands the native History and Storage & Recovery controls, then atomically
selects captured foreground mode, makes provider disclosure version `2`
current, and publishes its copy. P5H-2 through P5H-4 are one
non-release-qualified train until that final activation passes. Once activated:

- New Voice provider work requires a durable current version-2 observation
  before credential or microphone preflight continues. The disclosure decision
  does not enable History or capture a policy generation by itself.
- Successful final text uses the canonical History capture and acceptance path.
  With History on, the accepted row decision is made before result publication;
  with History off, the mandatory Latest/Pending result remains independent and
  no row is created.
- An eligible recoverable Transcription or Translation failure with History on
  transfers exact audio ownership from Pending Recording to one failed row.
  After that durable boundary Voice offers `Open History` and cannot present a
  Pending Retry or Discard command for the retired owner.
- With History off or when transfer is full, unavailable, or uncertain, Pending
  Recording remains the sole visible Retry-or-Discard owner. No UI guesses that
  transfer succeeded, and no second attempt starts against unresolved ownership.
- A failed accepted-row append remains a non-blocking History warning after the
  mandatory accepted-output record commits. It never replays provider work or
  hides an otherwise recoverable accepted result.
- Failed-row Retry is a separate explicit History action. It uses the same
  process-owned consent stage executor and cannot compete with active Voice.

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
- `outputDelivery` begins only after accepted text is available and the exact
  Pending owner durably reaches output delivery. It covers app-private accepted-
  result persistence and, in later milestones, passing a runtime
  `OutputDeliveryRequest` to a platform adapter. It does not prove that an
  adapter exists or that insertion was eligible, attempted, submitted, or
  confirmed.

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

### P4D-1 Payload-Free Processing Progress

- The foreground processor reports progress only as the existing
  `VoiceAttemptStage`. A progress event contains no text, error, identifier,
  timestamp, output intent, configuration, retry eligibility, durable owner, or
  provider authority. It is runtime-only, non-Codable, and never enters a log,
  journal, App Group, or keyboard surface.
- A rejected request, invalid preflight, competing busy call, or cancellation
  before durable transcription admission reports no progress. `transcription`
  is reported only after the fresh transcription ID and one-shot dispatch are
  durable; `postProcessing` only after that Pending phase is durable or its
  same-phase durability confirmation succeeds; and `outputDelivery` only after
  accepted text exists and that Pending phase is durable or confirmed.
- Correction, Translation, local cleanup, Usage bookkeeping, and persistence
  reconciliation create no extra progress cases. Case declaration order remains
  meaningless and is never a resume algorithm.
- One processor invocation reports each current semantic stage at most once. A
  local-recovery invocation first reports its retained coarse stage and may then
  report only later newly confirmed boundaries. Repeating a stage across two
  invocations means local resumption, not a repeated provider request. Retained
  `beginning` work is the exception: it reports nothing until reconciliation
  confirms the matching durable `transcribing` admission and returns the same
  live one-shot dispatch. Persisted `transcribing` bytes without that live
  authority never report progress and move through explicit recovery instead.
- A local-recovery resolution carries a separate payload-free kind:
  `processingCheckpoint` while accepted output is not yet being saved, or
  `savingResult` once final accepted text is retained for output persistence.
  The coarse stage alone never decides whether Voice presents Retry Local
  Checkpoint or Retry Saving Result.
- Once final accepted text exists in retained work, task cancellation preserves
  the `savingResult` checkpoint or finishes that exact local commit. It never
  downgrades the attempt to Pending provider Retry and never repeats
  transcription, correction, or Translation.
- The nonthrowing reporter is process-internal and presentation-only. It cannot
  authorize cancellation, Retry, Discard, provider launch, result acceptance, or
  a durable transition. The processor's returned resolution remains terminal
  truth. The shared owner cancels the active task itself and rejects late
  reporter calls with its private operation token.
- Receipt of current-token `transcription` progress may enable the Cancel
  Processing control because that event is delayed until durable dispatch
  admission. The progress value still grants no cancellation authority; only
  the controller's retained task and private token can be cancelled.
- Reporter delivery is ordered on the main actor, retained only for the current
  processor operation, and cleared on every terminal path. The processor
  rechecks operation identity and cancellation after each actor hop before any
  later side effect.

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
ordinary user cancellation or blocked preflight. `expired` remains only as a
compatibility outcome for a legacy attempt that was already terminal; an idle
session TTL never ends retained Listening or Processing. If the platform can no
longer continue capture, the positive-byte partial is `interrupted`; the frozen
per-utterance maximum is the only automatic Listening deadline.

Accepted-output retention expiry and detected delivery-record clock rollback
are not `VoiceAttemptOutcome.expired`. They produce separate content-free output
recovery observations and never produce `resultReady`, Copy, Share, or Use in
Practice while temporally ineligible, even if protected bytes remain available
internally for Clear or later trustworthy maintenance.

Quick Session expiry while merely `ready` creates no attempt outcome. Session
expiry is suspended while `listening` or `processing` and does not overwrite
the still-valid attempt; its eventual terminal result remains authoritative.
Reaching the per-utterance maximum automatically finishes capture and follows
the ordinary Pending/provider path; its eventual provider result determines the
terminal outcome.

The outcome carries no text, error, reason, identifier, timestamp, retry flag,
setup destination, output-delivery state, user-facing copy, or stable
logging/telemetry category. It is `Equatable`, `Sendable`, non-raw-valued, and
non-Codable. It is runtime
presentation state, not a durable journal, App Group record, keyboard command,
or authority to retry, discard, insert, record, or call a provider.

The value is independent of `VoiceWorkPhase`, `VoiceAttemptStage`, setup, and
the bridge-owned output-delivery observations. P1 macOS compatibility may
project only a non-empty accepted final result as `resultReady`, or the current
failed presentation as `recoverableFailure` when its eligible attempt is still
retained. Ordinary cancel projects no outcome, and macOS does not synthesize
`interrupted` or `expired`. iOS interruption/expiry adapters, detailed portable
failure categories, and durable outcome reconciliation remain later milestone
work.

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
- Voice never exposes Pending recovery actions after failed-row ownership is
  durably confirmed, and never exposes `Open History` while Pending remains the
  canonical owner.
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
- Empty, missing, oversized, or unsupported audio is not uploaded. Unknown or
  suspect non-empty audio is never auto-uploaded, but an explicit Transcribe or
  Retry may authorize one descriptor-bound provider attempt.
- If journaling fails, HoldType preserves the protected artifact where possible,
  reports local recovery failure, and does not start provider work.
- A preserved source becomes visible to Saved Recording presentation in the
  same process. Process-launch repair remains a crash-recovery fallback, not a
  requirement for ordinary local failure visibility.
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
  An exact empty partial enters cleanup-only discarding state; any bounded
  non-empty partial remains completed recovery even when duration metadata is
  suspect or unknown. The
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

- Verify that composition creates one Voice controller/workflow and one set of
  platform-adapter owners, injects the same identities into two scenes, and
  remains passive on construction even when credentials are unavailable.
- With two scenes, verify aggregate activation, loss of one active scene,
  last-active-scene stop, initiating-scene disappearance, the exact
  permission-sheet inactivity exception, no prompt transfer, and no automatic
  resume after permission, interruption, reset, or foreground return.
- Unit-test preflight ordering, state transitions, duplicate actions, tail
  cancellation, timer separation, journaling-before-provider, late-result
  rejection, and bounded cancellation with fakes and clocks.
- Verify every preflight short circuit and both post-permission revalidation
  points, including History-playback stop before audio activation and no new
  provider dispatch after aggregate foreground loss.
- Verify passive launch ordering as bounded orphan repair, capture-source
  reconciliation, existing containing-app lifecycle recovery, the one
  conditional second Capture read, and combined source/Pending observation.
  Prove bounded non-empty valid, short, and invalid-metadata raw media becomes
  completed (using unknown duration for short, over-bound, invalid, or timed-out
  metadata), exact empty is retained as Discard-only, protected-data or write
  failure remains blocked, foreground skips the repair, History pending performs
  no recheck, a second blocked result remains
  blocked without a loop, cancellation at every Capture boundary stops later
  loads, and the whole opportunity performs no Keychain, permission, audio,
  provider, App Group, or keyboard work.
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
