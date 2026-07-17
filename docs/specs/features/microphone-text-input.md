# Microphone Text Input

## Goal

Define the first user-visible contract for turning microphone input into text
inside the HoldType macOS menu bar app.

The MVP records speech from the microphone, sends the temporary audio file to
the OpenAI transcription API, and makes the returned text available to the
output workflow.

## Scope

This spec covers:

- starting and stopping a microphone text-input session
- visible recording and processing states
- temporary audio capture
- OpenAI transcription result handoff
- cancellation and failure behavior
- recording cache retention and cleanup behavior
- session-level state transitions

## Non-goals

- defining the exact OpenAI HTTP contract
- defining global shortcut registration details
- defining transcript history or persistence
- defining final UI layout, styling, or app architecture

## User-visible behavior

- The app must not capture microphone input until the user takes an explicit
  start action and required permissions are available.
- Skipping a setup prompt for microphone permission may dismiss that prompt for
  the current app run, but it must not count as microphone consent and must not
  let recording start while microphone permission is missing.
- A recording start action may prepare a temporary local audio file only after
  microphone permission is allowed.
- Start/stop must be available from the menu bar menu.
- A global hotkey should start and stop recording once the hotkey feature is
  implemented.
- While microphone capture is active, the app must show an unmistakable
  recording state.
- The user must be able to stop an active recording session.
- When `Recording tail after release` is enabled in Settings, a stop action
  keeps microphone capture active for the selected fixed tail duration before
  the completed recording file is finalized. The default tail setting is Off.
- The recording tail is a fixed delay only. It must not wait for detected
  silence, analyze speech, or extend indefinitely.
- A single recording attempt has a user-selected maximum from 1 through 15
  whole minutes. The default is five minutes. Reaching the selected limit is a
  normal automatic Finish: HoldType closes the recorder, protects the completed
  non-empty artifact, and continues the same transcription workflow exactly
  once.
- The selected maximum is frozen when recording starts. Changing it in
  Settings affects the next attempt and never shortens or extends capture that
  is already active.
- Monotonic elapsed time or finalized media duration at the configured limit
  is authoritative for the automatic Finish even when the recorder callback
  reports `successfully = false`. HoldType still diagnoses and logs that false
  callback as an anomaly, but it must not downgrade or delete a limit-length
  recording. An early completion with no limit evidence is unexpected, keeps
  any non-empty artifact, uses normal stop feedback, visibly reports that the
  recording ended unexpectedly and was saved to History, and does not start a
  provider request unless user Finish had already claimed authority. The
  provider-free Saved Recording offers an explicit Transcribe action and never
  claims that the configured limit elapsed.
- The last minute is visible as a countdown. HoldType warns with 60, 30, 10,
  8, and 6 seconds remaining, then once per second from 5 through 1. With a
  one-minute limit, countdown begins immediately but the 60-second warning at
  recording start is omitted. At the selected limit HoldType closes the
  recorder before presenting a distinct stopped-at-limit cue.
- A controller-owned monotonic watchdog matching the frozen selected limit
  must request finalization even if the recorder's completion delegate is lost.
  The watchdog, delegate, and key-up paths race through the same exact-once
  finalization boundary.
- During active capture an audible warning may play only on a private output
  route that will not feed the microphone, such as connected headphones.
  Speaker routes use the visual countdown and platform haptic feedback; they
  must not inject warning sounds into the retained recording.
- Stopping an active recording returns a completed local recording artifact
  with the file URL, captured duration, and byte size before transcription may
  begin.
- The user must be able to explicitly discard a session before accepting or
  handing off the generated text. The destructive action must be labelled as
  Discard/Cancel Recording and must not be inferred from task cancellation,
  lifecycle teardown, an internal error, or closing an unrelated surface.
- Explicitly discarding active capture stops the recorder, removes only the
  current app-created temporary audio artifact, returns the session to idle,
  and must not start transcription or output handoff.
- Explicitly discarding during the recording tail must cancel the pending stop
  delay, stop and remove only the current recording artifact, and must not
  start transcription or output handoff. Any non-user interruption during the
  same interval preserves positive bytes under the durability spec.
- After capture stops, the app may enter a processing state while
  transcription completes.
- Before any provider request, a non-empty completed artifact becomes a local
  recovery checkpoint visible from History with Play. While processing it is
  labelled accordingly; if transcription fails it remains available with
  Transcribe/Retry and Delete.
- If HoldType cannot first create an app-owned recovery copy, the original
  completed artifact remains playable and deletable but cannot be uploaded.
  History offers a local Retry Save/Repair action; provider Retry becomes
  available only after that ownership repair succeeds.
- When the checkpoint belongs to an automatic Finish at the configured limit and
  transcription succeeds, it becomes a durable `Saved and transcribed` row
  containing the accepted text. Its protected audio remains playable and
  explicitly deletable, but is never retryable.
- Start, stop, and cancel actions must be serialized through one active
  session. Repeated or overlapping actions may be ignored or shown as blocked,
  but must not enqueue duplicate recorder, transcription, or output work.
- While a recording tail is pending, the user-visible state remains recording.
  Repeated stop actions must not enqueue duplicate stops or transcription work.
- Processing must not wait indefinitely. If transcription cannot finish within
  the configured timeout, the session fails with a visible, recoverable error.
- A successful session must expose the final transcript as the last transcript
  and pass it to the configured output workflow.
- Streaming or live partial transcription is not part of the MVP.
- Failure states should explain the immediate problem in product language, such
  as microphone unavailable, permission denied, no speech detected, or
  transcription timed out.
- The completed recording file remains a temporary app-owned audio artifact. By
  default, HoldType deletes it after the current attempt finishes. For a
  successful automatic Finish at the configured limit, this normal cache
  cleanup deletes the original capture artifact while the separate bounded
  History recovery copy remains.
- If the user explicitly enables recording cache retention in Settings, HoldType
  may keep completed `.m4a` recordings after transcription so the user can open
  or save them from Finder.
- The recording cache should default to keeping only the 10 most recent
  recordings when retention is enabled. The user may switch retention to
  unlimited, in which case Settings must make clear that the user is
  responsible for clearing the cache.
- Settings must show the current recording cache size on disk and provide a
  clear action for app-owned cached recordings.

## Invariants

- No background or hidden recording is allowed.
- Repeated start actions must not create parallel recordings.
- Repeated stop or completion actions must not produce duplicate transcription
  uploads, duplicate output handoffs, or multiple accepted transcripts for one
  recording.
- Key up, the selected recording deadline, and recorder completion may race,
  but only one of them may finalize the active attempt and start provider work.
- If key up wins that race, finalized media at or above one half-second below
  the frozen selected limit retains the maximum-duration completion identity.
  Callback scheduling must not downgrade the result to ordinary ephemeral
  cleanup.
- A recorder callback reporting failure cannot override monotonic or finalized
  media evidence at the selected-limit boundary. The anomaly remains observable
  in diagnostics while History retention follows the maximum-duration identity.
- Stopping or cancelling capture must not silently accept unfinished text.
- Cancelling capture must clean up only the current recording artifact and must
  leave unrelated temporary files untouched.
- A failed session must not overwrite previously accepted text.
- Recording, transcribing, done, and error states must be mutually
  understandable to the user.
- External transcription or media operations must have explicit maximum wait
  times.
- Finalized-media duration inspection has a two-second maximum wait. If the
  media API fails or ignores cancellation beyond that boundary, finalization
  continues with the recorder's captured duration metadata and leaves every
  positive-byte artifact untouched.
- Recording cache growth must be bounded by default. The app must not keep
  accumulating audio files indefinitely unless the user explicitly chooses
  unlimited retention.
- Active, finalizing, and unresolved recovery audio is not ordinary recording
  cache. Cache Clear, individual Delete, and retention pruning must exclude it.
- Every attempt must follow
  `recording-durability-and-interruption.md`; internal cancellation is never
  destructive user authority.

## Edge cases and failure policy

- If microphone permission is denied, the app should explain that microphone
  access is required and provide a path to retry after the user changes
  permissions.
- If no microphone is available, the app should fail before entering a false
  recording state.
- If the user stops recording immediately, an empty artifact produces a clear
  no-input message. A non-empty artifact is preserved and may continue to the
  provider, which may still return an empty/no-speech result.
- If transcription produces low-confidence or empty output, the app should not
  pretend the result is final useful text.
- If a late transcription result arrives after cancellation or failure, it must
  be discarded rather than accepted as a new last transcript.
- If a platform lifecycle or audio event makes capture impossible, the session
  stops visibly and preserves a positive-byte partial as a provider-free Saved
  Recording. Lifecycle notification alone is not destructive authority.
- If the recording reaches the maximum duration, HoldType stops capture,
  reports that the selected recording limit was reached and the recording was saved,
  and continues normal processing.
- A stopped recorder's volatile elapsed clock is not authoritative. HoldType
  validates duration from the finalized media artifact and never deletes a
  positive-byte recording solely because the stopped clock reports zero or
  disagrees with the file.
- Missing or empty completed recording artifacts are failed recording results
  and must not be sent to OpenAI. Any positive-byte completed artifact is
  preserved for recovery; duration metadata alone must not delete or hide it.
- Turning off recording cache retention affects future attempts immediately:
  completed recordings from those attempts are deleted after the attempt
  finishes, whether transcription succeeds or fails.

## Route / state / data implications

The product-level session states are:

- idle
- requesting permission
- recording
- transcribing
- done
- error

Audio and raw transcription artifacts are treated as ephemeral session data
unless recording cache retention is explicitly enabled in Settings. An
unfinished attempt is an exception: its recovery checkpoint survives ordinary
history/cache policy until transcription succeeds or the user explicitly
deletes it. A successful automatic Finish at the configured limit remains as a
second bounded exception until explicit Delete or recovery-retention pruning.
The recording service should create unique app-owned temporary `.m4a` audio
artifacts for capture attempts and keep those paths local to HoldType until
stop, cancel, cache retention, cleanup, or failure handling decides their next
state.
Completed recording artifacts carry file URL, duration, and byte-count metadata
so downstream transcription can validate input without reading raw audio into
default logs.

## Verification mapping

- Add tests or manual QA for permission denied, microphone unavailable,
  start/stop, cancel, timeout, empty speech, empty-file rejection, temp-file
  cleanup, recording cache retention, configurable auto-Finish, warning cadence,
  finalized-media duration, false recorder callbacks at the maximum boundary,
  exact-once finalization, recovery playback, and successful transcription
  states when implementation code exists.
- Use fakes or bounded local fixtures for transcription tests instead of
  waiting on uncontrolled external services.

## Unknowns requiring confirmation

- Deployment target: macOS 14 Sonoma and newer.
- Exact OpenAI transcription model and timeout target.
- Supported languages for the first version.
- Whether hold-to-record is mandatory for MVP or toggle mode is acceptable
  first.
