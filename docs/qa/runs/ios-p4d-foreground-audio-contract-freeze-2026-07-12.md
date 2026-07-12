# iOS P4D Foreground Audio Contract Freeze QA

Date: 2026-07-12
Milestone: P4D-0 audio, capture-source, validity, permission, and relaunch freeze

## Scope

- Close the four contract gaps found after P4C and before AVFoundation or Voice
  presentation implementation.
- Define explicit Retry for a process-loaded `readyForTranscription` record
  without automatic provider work or a new Pending phase.
- Freeze the 300-millisecond product minimum and exact five-minute boundary.
- Freeze one foreground audio-session category, mode, option, cue, route,
  interruption, mute, media-reset, and bounded-finalization policy.
- Replace an ordinary recorder-URL handoff with a descriptor-bound
  capture-source owner and bounded relaunch reconciler.
- Freeze the iOS 17 microphone-permission adapter and product purpose string.
- Add no Swift, target membership, purpose-string plist entry, entitlement,
  background mode, microphone request, recording, provider call, App Group
  publication, or keyboard dependency in this checkpoint.

## Frozen Product Contract

- Passive launch and foreground reconciliation leave
  `readyForTranscription` unchanged and perform no Settings, Library, consent,
  credential, microphone, audio, or provider work.
- Explicit Retry accepts either `readyForTranscription` or
  `awaitingRecovery`, requires a null transcription ID and exact CAS, captures
  current settings, and atomically commits a fresh transcription ID plus current
  compact model/language before receiving the one-shot Pending reader. The
  same-process initial path remains separately bound to its frozen configuration.
- A valid P4 capture is at least 300 milliseconds and strictly less than
  300,000 milliseconds. Too-short, maximum-duration, empty, missing, or corrupt
  capture never creates ordinary provider work. Interrupted audio is recoverable
  only when it meets the same 300-millisecond minimum.
- The foreground audio session is `playAndRecord`, mode `default`, with only
  `allowBluetoothHFP` and `defaultToSpeaker`. HoldType does not mix, duck,
  suppress system interruptions, force a preferred input, force the speaker
  port, opt out of microphone-mute interruption, or add A2DP/AirPlay routes.
- The attempt freezes the active input UID, port type, and exposed selected
  data-source ID immediately before retained capture. Missing, muted, changed,
  inactive, or format-invalid input stops under the valid-partial policy; an
  output-only change may continue only while the complete recorder/input proof
  remains valid. Interruption end and media reset never resume automatically.
- Media services lost cancels arming, retires active audio objects and the
  attempt token during capture, and routes only descriptor-validated partial
  bytes of at least 300 milliseconds into recovery. During finalization it
  preserves the current source or Pending checkpoint and starts no provider.
- Start cue completion is bounded to two seconds and precedes retained audio.
  Stop cue follows recorder close. Haptics occur outside capture, and the app
  does not claim that the Ring/Silent switch suppresses enabled cues.
- Local finalization has one ten-second monotonic watchdog and at most one named
  UIKit background assertion. System expiration is an earlier deadline. It
  preserves a source or Pending checkpoint, never keeps the microphone active,
  never starts a provider after aggregate foreground loss, and adds no audio
  background mode.

## Descriptor-Bound Capture Source

- Persistence owns `HoldType/Recordings/Capture`, one exact attempt-named `.m4a`
  source, owner-only mode and markers, Complete protection, backup exclusion,
  and an exclusive descriptor/creator lock before the recorder may write.
- The AVFoundation adapter receives only the lease's transient recording URL.
  Completed, provider, scene, diagnostic, App Group, and keyboard surfaces do
  not receive a path, descriptor, `FileHandle`, or ordinary
  `AudioRecordingArtifact`.
- Production capture is mono MPEG-4 AAC, 44.1 kHz, high encoder quality. The
  same descriptor is revalidated across active, finalizing, completed,
  preparing-Pending, and transferred checkpoints. Inode replacement, rename,
  hard link, symlink, wrong protection, wrong owner/mode, or path disagreement
  fails closed.
- Exact bounded binary descriptor xattrs bind the attempt-named source to its
  creation time, Standard-or-Translate intent, format, duration, byte count,
  device/inode/generation, stable modification time, and ordered phase. The
  active marker is synchronized before URL exposure and every later phase is
  committed before its guarded work. No prompt, Library content, credential,
  consent, provider payload, transcript, or scene identity enters the source
  record.
- A directory-durable creation intent and hidden creation grammar close every
  crash before URL exposure. Finalizing is durable before recorder close, and
  a finalizing or positive-byte active residue after relaunch is never
  age-deleted; both resume only through explicit Recover Recording.
- Cancel and typed invalid cleanup durably enter cleanup-only discarding state
  before recorder close or unlink, so cancelled bytes never reappear as
  Recover Recording after a crash.
- A distinct capability-only prepare/recover API shares the canonical Pending
  operation gate with legacy path-based preparation. Its exact attempt-bound
  staging/final transfer xattr lets explicit Recover distinguish empty Pending,
  every zero-byte pre-binding marker prefix, one resumable staging copy, one
  adoptable final orphan, a matching journal with missing audio, and
  ambiguous/foreign inventory. Ambiguity is preserved.
- Pending copies directly from the held descriptor. Normal Done creates
  `readyForTranscription`; explicit relaunch recovery creates
  `awaitingRecovery` with current compact transcription settings and still
  requires Retry. Provider launch requires the Pending commit plus confirmed
  source removal or a durable transferred marker.
- Relaunch removes only exact discarding or transferred state, exact preparing
  state whose matching Pending audio and journal durability are fully
  revalidated, proven pre-exposure residue, or unlocked zero-byte active source
  older than one hour.
  Positive-byte active, finalizing, completed, and resumable preparing state are
  never age-deleted and offer exact recovery actions; confirmed Discard first
  proves no matching or ambiguous Pending destination. A fresh zero-byte active
  source is Discard-only. Unknown or ambiguous state is preserved.
- Maintenance examines at most 128 entries, removes at most 16 artifacts and
  200,000,000 logical bytes, stops before 500 monotonic milliseconds, and uses
  at most eight consecutive `EINTR` retries. Default reporting is content-free.

## Apple Platform Evidence

- Apple defines `playAndRecord` for recording plus playback and recommends it
  over `record` unless the app needs to silence virtually all output:
  [playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord),
  [record](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record).
- Apple documents `measurement` as disabling some dynamics processing and
  lowering playback level, while voice-chat modes describe two-way
  communication. P4D therefore uses the neutral default mode:
  [measurement](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement),
  [audio-session modes](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct).
- HFP makes Bluetooth microphone input eligible, and `defaultToSpeaker` changes
  only the built-in default while respecting an attached accessory:
  [allowBluetoothHFP](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetoothhfp),
  [Apple QA1754](https://developer.apple.com/library/archive/qa/qa1754/_index.html).
- Apple requires interruption and route observation; media-services-lost marks
  the unavailable interval, while reset requires rebuilding audio objects
  without automatically restarting playback or recording:
  [handling interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions),
  [route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes),
  [media lost](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswerelostnotification),
  [media reset](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification).
- iOS 17 exposes app-level permission and input-mute state through
  `AVAudioApplication`:
  [AVAudioApplication](https://developer.apple.com/documentation/avfaudio/avaudioapplication),
  [input mute](https://developer.apple.com/documentation/avfaudio/avaudioapplication/inputmutestatechangenotification).
- UIKit background assertions are finite, may be unavailable, require an
  expiration handler, and must always be ended. They do not authorize
  background microphone use:
  [beginBackgroundTask](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:)).

## Review And Verification

- Architecture review verified that explicit Retry can widen semantically
  without a journal version, new phase, reconstructed provider authority, or
  passive Keychain work.
- Storage review found that the current URL-based prepare cannot prove it is
  copying the recorder-held inode. The descriptor-bound capability and phase
  protocol close that boundary before AVFoundation implementation begins.
- Apple-platform review verified the category/mode/options, permission API,
  interruption/route policy, cue order, and finite-background-task boundary
  against current official documentation and the installed Xcode SDK.
- Product review verified distinct Too Short, maximum-duration, Recover
  Recording, Retry, Discard, interruption, and setup outcomes.
- `git diff --check`: passed.

No review used a live API key, Keychain, microphone, audio route, clipboard,
provider, Full Access, or destructive storage action.

## Assessment

P4D-0 passes. The foreground audio and recorder-to-Pending boundaries are now
specific enough to implement without guessing about relaunch, source identity,
minimum duration, Bluetooth routing, system interruptions, or background
finalization. P4D-1 is next: add a payload-free processor progress seam and the
fake-backed process-owned shared Voice controller. AVFoundation adapters remain
P4D-2, followed by scene integration, native Voice/Privacy UI, simulator QA, and
a separate bounded physical-device foreground-audio smoke.
