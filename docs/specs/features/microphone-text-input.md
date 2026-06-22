# Microphone Text Input

## Goal

Define the first user-visible contract for turning microphone input into text
inside the VibeType macOS menu bar app.

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
- session-level state transitions

## Non-goals

- defining the exact OpenAI HTTP contract
- defining global shortcut registration details
- defining transcript history or persistence
- defining final UI layout, styling, or app architecture

## User-visible behavior

- The app must not capture microphone input until the user takes an explicit
  start action and required permissions are available.
- A recording start action may prepare a temporary local audio file only after
  microphone permission is allowed.
- Start/stop must be available from the menu bar menu.
- A global hotkey should start and stop recording once the hotkey feature is
  implemented.
- While microphone capture is active, the app must show an unmistakable
  recording state.
- The user must be able to stop an active recording session.
- Stopping an active recording returns a completed local recording artifact
  with the file URL, captured duration, and byte size before transcription may
  begin.
- The user must be able to cancel a session before accepting or handing off the
  generated text.
- After capture stops, the app may enter a processing state while
  transcription completes.
- Start, stop, and cancel actions must be serialized through one active
  session. Repeated or overlapping actions may be ignored or shown as blocked,
  but must not enqueue duplicate recorder, transcription, or output work.
- Processing must not wait indefinitely. If transcription cannot finish within
  the configured timeout, the session fails with a visible, recoverable error.
- A successful session must expose the final transcript as the last transcript
  and pass it to the configured output workflow.
- Streaming or live partial transcription is not part of the MVP.
- Failure states should explain the immediate problem in product language, such
  as microphone unavailable, permission denied, no speech detected, or
  transcription timed out.
- The temporary audio file should be removed after successful transcription
  unless debug behavior explicitly keeps it.

## Invariants

- No background or hidden recording is allowed.
- Repeated start actions must not create parallel recordings.
- Repeated stop or completion actions must not produce duplicate transcription
  uploads, duplicate output handoffs, or multiple accepted transcripts for one
  recording.
- Stopping or cancelling capture must not silently accept unfinished text.
- A failed session must not overwrite previously accepted text.
- Recording, transcribing, done, and error states must be mutually
  understandable to the user.
- External transcription or media operations must have explicit maximum wait
  times.

## Edge cases and failure policy

- If microphone permission is denied, the app should explain that microphone
  access is required and provide a path to retry after the user changes
  permissions.
- If no microphone is available, the app should fail before entering a false
  recording state.
- If the user stops recording immediately, the app should either produce an
  empty/no-speech result or a clear no-input message.
- If transcription produces low-confidence or empty output, the app should not
  pretend the result is final useful text.
- If a late transcription result arrives after cancellation or failure, it must
  be discarded rather than accepted as a new last transcript.
- If the app is interrupted by platform lifecycle events, the session should
  stop or fail visibly rather than continue recording invisibly.
- If the recording is too short, the app should show a clear error instead of
  sending misleading empty input through the normal success path.
- Missing, empty, or too-short completed recording artifacts must be treated as
  failed recording results and must not be sent to OpenAI.

## Route / state / data implications

The product-level session states are:

- idle
- requesting permission
- recording
- transcribing
- done
- error

Audio and raw transcription artifacts are treated as ephemeral session data
unless a future persistence or debug spec explicitly says otherwise.
The recording service should create unique temporary `.m4a` audio artifacts for
capture attempts and keep those paths local to the current session until stop,
cancel, cleanup, or failure handling decides their next state.
Completed recording artifacts carry file URL, duration, and byte-count metadata
so downstream transcription can validate input without reading raw audio into
default logs.

## Verification mapping

- Add tests or manual QA for permission denied, microphone unavailable,
  start/stop, cancel, timeout, empty speech, recording-too-short, temp-file
  cleanup, and successful transcription states when implementation code exists.
- Use fakes or bounded local fixtures for transcription tests instead of
  waiting on uncontrolled external services.

## Unknowns requiring confirmation

- Deployment target: macOS 14+ or macOS 13+ if it stays simple.
- Exact OpenAI transcription model and timeout target.
- Supported languages for the first version.
- Whether hold-to-record is mandatory for MVP or toggle mode is acceptable
  first.
