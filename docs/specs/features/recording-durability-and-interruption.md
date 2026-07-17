# Recording Durability And Interruption

## Goal

Make every retained microphone attempt recoverable when recording, local
finalization, app lifecycle, or provider work ends unexpectedly. A user must
not lose non-empty audio because an internal state write, task cancellation,
route change, process exit, or other non-user event was interpreted as
Discard.

This cross-platform contract governs macOS capture and iOS Voice/keyboard
capture. More specific feature specs may define presentation and platform
mechanics, but they must preserve these ownership rules.

## Terminal causes

Every terminal recording event has exactly one product cause:

- `userFinished`: the user requests transcription;
- `configuredLimit`: the frozen user-selected limit finishes capture and
  requests transcription;
- `platformInterrupted`: the operating system, audio route, recorder, or
  lifecycle prevents capture from continuing;
- `internalFailure`: HoldType cannot publish state, finalize metadata, or
  complete another local operation;
- `ownerTeardown`: an app/controller task is cancelled, replaced, or the
  process is terminating;
- `explicitUserDiscard`: the user explicitly requests that the current audio
  be deleted.

Only `explicitUserDiscard` may intentionally delete a non-empty retained
recording. A descriptor- or file-handle-proven zero-byte source may enter
cleanup-only Discard state without a user action. Every other cause preserves
positive bytes under one durable owner.

## Capture ownership

- HoldType creates durable attempt identity and capture ownership before the
  recorder is allowed to retain audio.
- Before a recovery checkpoint exists, the active macOS capture and its
  journal live in non-purgeable Application Support storage. A purgeable
  recording cache is never the sole owner of retained audio; the finalized
  original may move there only after a separate durable History owner commits.
- Active and finalizing recordings are protected from cache Clear, individual
  cache Delete, and retention pruning.
- Stop, recorder completion, the configured deadline, lifecycle termination,
  and delegate callbacks race through one exact-once terminal boundary.
- A finalization error must keep a recoverable source handle or path. Duration,
  media probing, metadata reads, and state publication are never authority to
  delete or hide positive bytes.
- A normal quit or updater relaunch requests bounded finalization. If the
  process exits before that finishes, launch repair promotes the journaled
  positive-byte source to a provider-free Saved Recording.
- A crash, force quit, or operating-system process eviction may prevent an
  immediate user notice, but the next launch must recover the same source
  without automatically uploading it.

## iOS cancellation and handoff

- App Group state-publication failure affects coordination UI only. It must not
  cancel or discard the retained recorder.
- Generic Swift task cancellation, controller deinitialization, scene
  replacement, or handoff supersession maps to `ownerTeardown`, not
  `explicitUserDiscard`.
- Once the recorder may have retained a byte, arming races preserve the
  original Done, configured-limit, interruption, or teardown cause. They must
  not collapse those causes into Cancelled.
- A new keyboard handoff checks real live/durable capture ownership, not only a
  presentation phase. It may supersede only a proven pre-capture or empty
  attempt.
- `Stop Keyboard Session` while Listening finalizes a non-empty partial to
  provider-free Saved Recording. During Finalizing or Processing it disarms
  the warm session without cancelling the owned finalization or provider task.
- Closing a handoff surface is not destructive authority after capture starts.
  Only a separate explicit destructive action may delete retained audio.
- Loss of an auxiliary warm-input keeper disables warm reuse but does not stop
  a recorder that is otherwise still active.
- Scene inactivity by itself is not proof that capture failed. HoldType stops
  only when the platform/audio boundary cannot continue or the product has an
  explicit user Finish, configured limit, or explicit Discard. If continued
  capture becomes impossible, it preserves the partial as
  `platformInterrupted`.

## Saved Recording and History

- Before provider work, every finalized non-empty source has one durable,
  playable owner.
- Involuntary or internal termination is provider-free unless the user had
  already requested Finish or the configured limit had already elapsed.
- A provider-free Saved Recording offers Play, Transcribe, and Delete. Delete
  is explicit and affects only that attempt.
- A provider failure keeps Play and Retry/Transcribe. Ambiguous provider
  outcome remains non-retryable by default, but may offer an explicit
  warning-gated `Transcribe Again` action that explains possible duplicate
  billing.
- Local finalization or persistence failure must become visible in the current
  process; recovery must not require an app restart merely to appear.
- Accepted-History publication and audio cleanup form a recoverable
  transaction. HoldType does not remove the final playable owner until the
  accepted row or an equivalent durable repair marker commits.
- Unresolved Saved Recordings are never silently evicted by a count-based
  retention limit. Storage pressure may block new provider work and ask the
  user to review recordings, but only explicit Delete removes unresolved
  positive-byte audio.

## User feedback

- An involuntary stop immediately reports `Recording interrupted — saved to
  History` or an equivalent platform-appropriate message.
- The active handoff sheet remains the owner of keyboard-originated failure and
  recovery presentation.
- Failure UI never claims that audio was saved unless a durable playable owner
  can be loaded.
- Default logs record the terminal cause, attempt identifier, durability
  outcome, and whether provider work was authorized. They do not contain raw
  audio, transcript text, secrets, or local paths.

## Verification

For every platform terminal cause, tests assert:

- positive bytes result in exactly one durable playable owner unless the user
  explicitly requested Discard;
- zero-byte cleanup never deletes another attempt;
- provider dispatch occurs at most once and only after durable ownership;
- involuntary/internal termination performs no provider dispatch unless Finish
  or the configured limit already owned that authority;
- late callbacks cannot accept text, delete audio, or create a second owner;
- relaunch repair is bounded and never automatically uploads recovered audio.

Fault injection covers state-publication failure, feedback/arming races,
generic task cancellation, handoff supersession, warm-input failure, cache
clear/delete/prune, finalization and metadata failure with positive bytes,
normal quit, updater relaunch, process loss, and History write failure.
