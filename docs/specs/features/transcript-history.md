# Transcript Recovery History

## Goal

Keep recent successful dictations recoverable during the current app session so
users do not need to re-dictate long text when active-app insertion fails, the
target input changes, or a completed recording fails to transcribe for a
recoverable provider or network reason.

## Decision

Accepted transcript recovery history is a session-only local feature. It is
enabled by default because successful transcript entries are kept in app
memory only and are cleared when the app quits.

An unfinished recording is a separate safety checkpoint. HoldType protects its
audio and compact recovery metadata on local disk before the first provider
request, so a long dictation or provider failure does not disappear. A
recording that reaches its configured limit remains in this bounded store even
after successful transcription, together with its accepted text. This is an
explicit recovery exception, not general durable transcript persistence or the
normal recording cache.

Users can disable accepted transcript history in Settings. Disabling it clears
accepted session entries and stops future accepted-history writes. It does not
delete an unfinished recovery checkpoint; only successful cleanup or the
user's explicit Delete/Discard action may do that.

Older local settings that stored the previous off-by-default value are migrated
once to the current on-by-default behavior. After that migration, a user's
explicit Settings toggle choice persists normally.

Last Transcript remains current-session state and does not require recovery
history to be enabled, but the menu bar dropdown does not display transcript
text.

## Scope

This spec covers:

- session-only storage of accepted transcript text
- protected local storage of one or more bounded unfinished transcription
  attempts
- default history setting
- retention limit and clear behavior
- history panel behavior
- history row system clipboard copy and deletion actions
- failed row retry and settings actions
- privacy and logging boundaries
- relationship to Last Transcript, Last Result, and system clipboard
  actions
- cache-gated local playback of completed recordings from history rows

## Non-goals

- durable disk-backed transcript persistence outside the bounded successful
  limit-completed recording exception
- durable raw audio retention outside bounded unfinished-attempt recovery, the
  successful limit-completed recording exception, or the explicit normal
  recording cache setting
- cloud sync, accounts, sharing, or telemetry
- full search, semantic notes, tags, folders, or review workflows
- SQLite or another database requirement for the MVP
- storing explicitly discarded or pre-capture setup failures; involuntarily
  stopped non-empty partials are durable Saved Recordings

## User-visible behavior

- Transcript recovery history is on by default for the current app session.
- Existing installs that still carry the legacy off default are switched on
  once during settings load.
- Settings exposes a Keep Transcript Recovery History toggle.
- Turning recovery history off immediately clears accepted transcript entries
  and stops future accepted-history writes. Saved recordings remain visible.
- Turning recovery history back on affects future successful dictations. It
  does not restore entries cleared earlier.
- When recovery history is on, each accepted non-empty transcript is added to
  recovery history after transcription succeeds and before active-app output
  handoff can fail.
- Every non-empty completed recording becomes a saved `Processing` recovery
  row before provider work begins, regardless of the accepted-history toggle.
- An automatic Finish at the configured limit uses the same saved row and starts
  transcription automatically exactly once.
- After that automatic Finish transcribes successfully, its row becomes
  `Saved and transcribed`, displays the accepted text, and keeps Play plus an
  explicit Delete action. It never offers Retry because its provider work has
  already succeeded.
- A successful limit-completed row is the sole History row for that result;
  HoldType does not add a duplicate session-only accepted row with the same text.
- The successful limit-completed row and protected audio survive relaunch,
  accepted History being disabled or cleared, normal recording-cache cleanup
  including `Delete immediately`, and normal app quit. Only explicit Delete or
  bounded recovery retention removes them.
- Unresolved Processing, failed, interrupted, internal-failure, or owner-
  teardown Saved Recordings are never removed by count-based retention. Only
  their explicit Delete/Discard action may remove positive-byte audio.
- A lifecycle- or internally-interrupted non-empty partial appears immediately
  as a provider-free Saved Recording with Play, Transcribe, and Delete. It does
  not require relaunch and does not automatically call the provider.
- A completed recording that fails during
  transcription for a recoverable OpenAI, network, timeout, rate-limit,
  unreadable-response, or empty-result reason changes that row to a failed
  attempt without deleting its audio.
- The maximum-duration completion identity is part of the durable checkpoint.
  If its first provider attempt fails, that identity survives relaunch; an
  explicit Retry success promotes the same row to `Saved and transcribed`
  instead of deleting its audio or creating a normal accepted-history row.
- The completion identity is durably associated with the protected recovery
  audio before provider work. If the main recovery index cannot be written
  after the audio copy succeeds, relaunch reconstruction must recover that
  identity from the app-owned audio filename or bounded local checkpoint
  metadata rather than treating a limit-completed recording as a normal
  ephemeral attempt.
- Provider work for any completed non-empty recording may start only after a
  durable dispatch seal is tied to its app-owned recovery audio. If the audio
  copy or dispatch seal cannot be written, provider Retry stays hidden and the
  row offers only Play, Delete, and a local Retry Save/Repair action.
  Successful local repair makes provider Retry available; repeated local
  repair failure never uploads the original emergency artifact.
- An accepted or still-unresolved provider dispatch keeps its compact
  fail-closed seal for the entire lifetime of that protected audio, including
  after a result is saved. Cleanup, clearing, startup pruning, and retention may
  remove that seal only after the exact owned audio file is confirmed gone. If
  metadata rollback and audio removal both fail, relaunch keeps the playable
  orphan non-retryable.
- A definitive pre-dispatch or provider-rejection failure may retire its seal
  only after the retryable row is durably written. Every later explicit Retry
  writes a fresh seal before its upload. Timeout, transport loss, or
  cancellation after dispatch began is not a definitive retryable failure: the
  seal remains for the lifetime of the audio and the playable row becomes
  `Transcription outcome uncertain` with ordinary Retry hidden. If any
  retryable transition cannot be persisted, the previous seal likewise remains
  and relaunch treats the outcome as uncertain and non-retryable.
- After a non-empty provider transcription is accepted, HoldType checkpoints
  that raw text before downstream correction or translation. A downstream
  failure leaves a fail-closed row labelled `Raw transcription recovered —
  post-processing failed`, containing the raw accepted text and a `Save Raw
  Transcription` action. Saving it preserves that truthful label; it cannot
  masquerade as a translated success or turn back into provider Retry.
- The immediate user-facing failure surface for a completed recording is the
  menu bar recovery prompt. Transcript History is the session recovery surface
  the user can open from the normal menu item.
- A failed attempt row must be visually distinct from accepted transcript rows.
  It should show `Not transcribed`, a compact reason, the attempt time, and any
  known duration/model/language metadata.
- Processing and failed rows offer Play whenever their protected audio is
  readable and no dictation is currently recording or processing. Play is local
  only and never starts or cancels provider work.
- Starting a new recording stops any saved-recording or cached-recording
  playback before the microphone recorder is activated, so speaker playback
  cannot continue into the new capture.
- A failed attempt row may offer Retry. Retry sends the saved temporary audio
  through the current transcription settings and current API key.
- Saved-recording Play, Retry, and Delete are unavailable while another
  dictation is recording or processing. The controller independently rejects a
  Retry that races with active recording, so recovery UI can never move the
  shared status away from Listening while the recorder remains live.
- A Processing row cannot be deleted. Its protected artifact remains owned by
  that provider operation until it succeeds or becomes a failed, explicitly
  deletable saved recording.
- A failed attempt row caused by invalid or unavailable API key should offer an
  Open API Key Settings action and may also allow Retry after the user fixes the
  key.
- A failed attempt row caused by invalid transcription settings should offer an
  Open Transcription Settings action and may also allow Retry after the user
  fixes the settings.
- Retry success replaces the failed attempt with a normal accepted transcript
  history row and updates Last Transcript. If Keep last result is enabled,
  the recovered transcript is saved there for manual insertion.
- Retry failure keeps the failed attempt row, updates its reason and retry
  count, and keeps the previous successful Last Transcript intact.
- A failed automatic insertion or Paste Last Result must not discard the
  current Last Transcript or the recovery history row created for the accepted
  transcript.
- Recovery history keeps at most the 20 most recent accepted transcripts and a
  small bounded set shared by recent failed attempts and successful
  limit-completed recordings. Older protected artifacts may be removed
  automatically only after no provider operation owns them and that
  saved-recording limit is exceeded.
- The menu bar exposes a Transcript History window.
- Opening Transcript History brings the window to the front, including when it
  already exists behind another app window.
- The Transcript History window title should identify the app as
  `HoldType: History`. The menu bar item and in-window heading may remain
  `Transcript History`.
- The Transcript History window lists entries newest-first and may group them
  by day.
- Each history row shows the entry time and transcript text.
- When Recording Cache is enabled, an accepted transcript row may offer Play for
  the completed recording that produced that row, but only while the app-owned
  cached recording file still exists.
- The Play action is a local debugging aid for comparing audio with the accepted
  transcript. It must not upload audio, retry transcription, update Last
  Transcript, write to either clipboard, or trigger active-app insertion.
- Turning Recording Cache off, clearing the cache, deleting a cached recording,
  or retention pruning the file must remove Play availability for affected
  accepted transcript rows.
- Each history row can copy only that row's text to the macOS system clipboard.
- History row system clipboard copy does not require the Keep last result
  setting, does not update the Last Result recovery value, and does not
  trigger active-app insertion.
- Each history row can delete only that row from current recovery history.
- The history window provides a Clear History action.
- Deleting one history row removes only that row. It does not delete Keychain
  secrets, settings, normal recording cache state, cached recordings linked for
  local playback, Last Transcript current-session state, or other history rows.
  Deleting a failed attempt or successful limit-completed recording also
  removes only that row's protected audio. The UI reports deletion only after
  both its recovery metadata and exact audio artifact were removed; if either
  operation fails, the saved row remains or is reconstructed and the failure
  is shown instead of a false success message.
- Clearing accepted history removes only accepted session entries. It does not
  delete Keychain secrets, settings, normal recording cache state, or Last
  Transcript current-session state. Saved recording rows require their own
  explicit Delete/Discard action.
- Quitting the app clears accepted transcript entries. Unfinished saved
  recordings and their compact recovery metadata remain available after
  relaunch.
- The main menu does not provide a manual Save Last Transcript action. When
  Keep last result is enabled, accepted transcripts are saved there
  automatically under `text-output-workflow.md`.

## Stored fields

Each accepted transcript history entry should store only:

- stable local id
- creation date
- transcript text
- transcription model
- language setting used for the request
- optional audio duration, if already known from the completed session
- optional session-only reference to an app-owned normal recording cache file
  for local playback, only when Recording Cache was enabled for that completed
  recording

History must not store raw audio, provider responses, authorization headers,
API keys, prompt text, custom dictionary entries, or debug payloads. Any
recording cache file reference on an accepted row is session-only metadata for
local playback and must not be persisted with transcript history.

Each saved recording entry should store only:

- stable local id
- creation date
- compact failure reason
- retry count
- transcription model
- language setting used for display
- optional audio duration, if already known from the completed session
- temporary app-owned audio file reference needed for retry
- optional accepted transcript text, present only after a limit-completed recording
  transcribes successfully
- completion kind identifying a normal attempt or automatic Finish at the
  configured limit

Saved recording entries must not store provider responses, authorization
headers, API keys, prompt text, nearby active-text context, custom dictionary
entries, rejected transcript candidates, or debug payloads.

## Privacy and storage

- Accepted transcript history is local-only and session-only for this MVP
  slice.
- Recovery metadata and audio are local-only, app-owned, and bounded. Unfinished
  rows persist until successful processing or explicit deletion. A successful
  limit-completed row additionally persists only its accepted transcript text
  until explicit deletion or retention pruning. No row contains provider payload,
  credential, prompt, nearby context, or raw log content.
- No history entry may be sent to a server except when the user later uses a
  separate feature that explicitly sends text and has its own spec.
- Default logs must not include transcript text or history entry contents.
- Default logs must not include recording cache paths, failed-attempt audio
  paths, playback paths, or retry payloads.
- Durable transcript history beyond the bounded successful limit-completed
  recording exception requires a future spec update before implementation.

## Edge cases and failure policy

- Empty or whitespace-only successful transcript text must not create accepted
  transcript entries. Provider empty-result failures may create failed attempt
  entries when completed audio exists.
- Cancelled recordings must not create history entries.
- Pre-capture setup failures such as a missing API key must not create failed
  attempt entries because no completed audio exists.
- If a failed attempt's temporary audio cannot be saved, the app should still
  show the immediate transcription error but must not show a fake Retry action.
  It must skip destructive recording-cache cleanup for that attempt so the
  completed artifact remains recoverable where possible.
- If a history append fails, the app should keep the current Last Transcript
  visible and continue output delivery where practical.
- Before transitioning Processing to `Saved and transcribed` after provider
  success, HoldType atomically writes bounded local repair metadata containing
  the accepted text and protected-audio identity. If the main recovery index
  transition then fails, HoldType must not publish a false saved state or
  repeat the provider request. It shows a visibly incomplete row with Play and
  only a local Retry Save action. Retry Save repairs metadata; it never uploads
  the audio again.
- When the accepted-text repair write succeeds, its fail-closed classification
  and accepted text survive relaunch. Startup restores that incomplete row,
  keeps provider Retry hidden, and never converts uncertain post-success
  metadata back into a retryable transcription attempt. Successful local repair
  removes the temporary repair metadata.
- If both the accepted-text repair write and the main recovery-index write fail
  after provider success, preserving the text across process death is
  impossible. HoldType keeps the accepted text in memory for the current
  process; after relaunch the earlier dispatch seal restores a playable
  `Transcription outcome uncertain` row with provider Retry permanently hidden.
  It must never claim that the unavailable text was durably saved.
- If the main Processing checkpoint write fails after its protected audio copy
  succeeds, bounded checkpoint metadata preserves the maximum-duration identity
  across relaunch. Before relaunch, the same owned checkpoint is reused for an
  emergency row; provider success immediately makes that row non-retryable even
  if its saved-state transition also fails.
- If compact recovery metadata is missing, unreadable, or corrupt, HoldType
  reconstructs a bounded set of retryable rows from its own non-empty regular
  `Recording-<timestamp>-<UUID>` and
  `Recording-Max-<timestamp>-<UUID>` files and atomically repairs the metadata
  when possible. The Max filename preserves maximum-duration retention even if both
  compact checkpoint writes fail. Reconstruction does not follow symbolic
  links and ignores directories, special files, malformed names, and unmanaged
  files.
- If a cached recording is missing or cannot be played, the history row should
  stop offering Play or report a compact playback failure without logging the
  file path.
- If the app terminates normally, accepted session history is cleared while
  unfinished and successful limit-completed saved recordings remain recoverable.

## Verification mapping

- Settings tests should prove recovery history is enabled by default,
  disabling it clears current entries, and the setting persists.
- History tests should cover accepted append, max-20 accepted retention, failed
  attempt append, failed-attempt retention and audio cleanup, clear,
  disabled accepted-history behavior, successful limit-completed saved-row
  round-trip and retention, saved-row survival while disabled, relaunch
  recovery, row deletion, recovery and cache-gated local playback, retry
  exclusion after success, retry success, retry failure, checkpoint-index
  failure before provider work, fail-closed saved-state repair across relaunch,
  local-only Retry Save, and exclusion of cancelled or pre-capture setup
  failures.
- Controller tests should prove output failure does not erase accepted recovery
  history.
- Log review should confirm transcript history contents are not emitted in
  default logs.
