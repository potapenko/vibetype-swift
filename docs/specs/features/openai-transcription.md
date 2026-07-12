# OpenAI Transcription

## Goal

Define the product contract for sending completed HoldType recordings to
OpenAI and turning the returned transcript into app text.

The MVP uses OpenAI's file-based transcription endpoint for bounded dictation
requests. It does not use realtime microphone streaming.

## Scope

This spec covers:

- the OpenAI transcription request and response contract
- model, language, prompt, and custom dictionary settings
- optional nearby active-text context for continuation quality
- optional built-in emoji command prompt hints
- optional post-transcription text correction handoff
- optional post-transcription action handoff
- local usage estimate handoff for successful transcriptions
- failed transcription recovery handoff for retryable completed recordings
- timeout and retry behavior
- user-visible errors for common provider failures
- privacy and logging constraints for API keys, audio, prompts, and transcripts

## Non-goals

- background `URLSession` transfer or a P6 background-continuation claim
- calling the live OpenAI API during normal automation or tests
- adding provider abstractions beyond the OpenAI MVP
- using the translations endpoint, realtime transcription, diarization, speaker
  labels, timestamps, subtitles, or streaming transcript deltas
- retaining audio for analytics, telemetry, or transcript history outside the
  explicit local recording cache setting
- auto-learning dictionary entries from edits in other apps
- snippets, text expansion, or cloud-synced dictionary behavior

## Evidence

- OpenAI Speech to Text guide, reviewed 2026-07-10:
  `https://developers.openai.com/api/docs/guides/speech-to-text`
- OpenAI Create transcription API reference, reviewed 2026-07-10:
  `https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create`
- Apple `URLSession.uploadTask(withStreamedRequest:)`, reviewed 2026-07-10:
  `https://developer.apple.com/documentation/foundation/urlsession/uploadtask(withstreamedrequest:)`

## User-visible behavior

- After recording stops, the app may enter `transcribing` and upload the
  completed temporary audio file to OpenAI's transcription endpoint.
- The request must use `multipart/form-data` with the audio file and selected
  transcription settings.
- The default model is `gpt-4o-transcribe`. The model remains a local setting
  so a later release can change it without code changes.
- A blank model setting falls back to the default. A model rejected by OpenAI
  fails with a settings-focused error instead of silently changing providers.
- The app should produce an OpenAI-supported upload format for MVP recordings,
  preferably `m4a` or `wav`.
- The current adapter accepts only an existing regular `m4a` or `wav` file. It
  rejects an empty file and any file whose size is greater than or equal to
  25,000,000 bytes before provider contact.
- Multipart preparation must not load the complete audio file into memory. It
  copies audio into one app-owned scratch request body with reads no larger
  than 64 KiB. Form fields remain ordered as `model`, `response_format`,
  optional `language`, optional `prompt`, then `file`. The provider filename is
  controlled as `recording.m4a` or `recording.wav` from the validated format;
  the original local filename is never included.
- Non-audio multipart bytes are capped at 1 MiB, and the complete body size is
  calculated with overflow checking before upload. Oversized metadata is a
  request-settings failure rather than an audio-file failure.
- After the body has been written and synchronized, preparation must open a
  read-only descriptor and prove that it identifies the same private regular
  file as both the writer descriptor and the scratch pathname. Within the
  app-private random scratch namespace, it validates and removes that pathname,
  then retains only the read descriptor as the upload artifact. The file must
  have exactly one link before removal and zero links afterward; a hard-linked
  body is rejected. Replacing the former pathname after finalization cannot
  change the bytes sent and a stable replacement survives artifact cleanup.
- Darwin does not expose a kernel-level conditional unlink for this path. The
  boundary assumes the containing app's private sandbox without a hostile
  same-UID process interposing between the final identity check and `unlink`;
  protection against that out-of-scope race is not claimed.
- The foreground upload supplies a fresh descriptor-backed input stream when
  URLSession requests the initial body or an approved replay. Every stream has
  an independent offset, reads no more than 64 KiB per descriptor operation,
  and produces the complete finalized body byte-for-byte.
- The foreground transport accepts at most 1 MiB of provider response data.
  A larger declared or streamed response is cancelled and treated as an
  unreadable provider response.
- Language `Auto` sends no language parameter.
- Language `English` sends `en`; language `Russian` sends `ru`.
- A custom language must be a two- or three-letter ISO-639-style language code
  accepted by the implementation's validation. An empty custom value falls back
  to Auto. An invalid non-empty custom value blocks transcription with a
  settings error before upload.
- The optional prompt is sent only when non-empty after trimming whitespace.
- Prompt text should guide spelling, vocabulary, and style. It must not be
  treated as secret, but it may contain user content and must not be logged by
  default.
- The app may maintain a local custom dictionary of user-provided words or
  phrases that should be recognized with exact spelling when spoken.
- Custom dictionary entries are sent as transcription prompt context when at
  least one entry remains after trimming and duplicate removal.
- Built-in emoji command hints are sent as transcription prompt context when
  emoji commands are enabled and at least one command set is active. Emoji
  command behavior is governed by `voice-emoji-commands.md`.
- If a freeform prompt, nearby active-text context, emoji command hints, and
  dictionary entries exist, the request prompt should include all active parts
  with the dictionary appended as spelling context.
- When Use Nearby Text Context is enabled, the app may read a short excerpt
  from the currently focused editable text field and include it in the
  transcription prompt so continued dictation keeps topic, spelling,
  punctuation, and language continuity.
- Nearby text context is optional and best-effort. If Accessibility permission
  is missing, the focused app does not expose editable text, the field is
  secure, or the excerpt is empty, transcription continues with only the
  normal prompt and dictionary context.
- Nearby text context must be bounded to a short excerpt near the cursor. It is
  not a full-document import and must not read unrelated app content.
- The composed prompt should order context as: user prompt, nearby active-text
  context, built-in emoji command hints, custom dictionary spelling context.
- If the provider returns only, or almost only, the dictionary hint itself, the
  app must reject the result instead of accepting it as dictated text.
- If the provider returns only a copied excerpt of nearby active-text context,
  the app must reject the result instead of accepting it as new dictated text.
- The MVP requests the normal JSON transcription response and reads the
  returned `text` field.
- A successful non-empty transcript becomes the app's last transcript and is
  passed to the optional text-correction workflow before configured output
  delivery.
- Optional text correction is governed by `text-correction.md`. Transcription
  itself remains successful when a later correction stage is skipped or fails
  open.
- Optional post-transcription actions such as translation are governed by
  `post-transcription-actions.md`. They run only after a successful accepted
  transcription and may have their own failure policy.
- A successful transcription may create a local usage estimate record using the
  completed recording duration and selected model. This record is for local
  cost projection only and is not a provider usage receipt.
- A whitespace-only or empty transcript is a failed session, not a successful
  accepted transcript.
- If a completed recording cannot be transcribed because OpenAI rejects the API
  key, the network is unavailable, the request times out, OpenAI is temporarily
  unavailable, the response is unreadable, or another provider transcription
  failure happens after capture, the app should create a recoverable failed
  attempt when transcript recovery history is enabled.
- A recoverable failed attempt is not an accepted transcript. It must be shown
  as `Not transcribed` with a short reason and recovery actions such as Retry or
  Open Settings.
- After a completed recording fails during transcription, the app should show a
  frontmost recovery prompt that explains what happened and that the recording
  was not accepted as text. The app must not automatically open Settings or
  Transcript History for these post-capture transcription failures.
- The recovery prompt should appear only after the app has entered the
  terminal failure state, so recording/transcribing indicators and menu status
  do not remain visually active behind the prompt.
- The recovery prompt should offer only applicable direct actions: Try Again,
  Open OpenAI Settings, Open Transcription Settings, or Dismiss. It should not
  include a Transcript History shortcut; the normal menu item already exposes
  that recovery surface.
- The menu bar dropdown should retain a compact error status and matching
  recovery actions as a secondary surface if the user opens the menu after the
  prompt.
- Invalid or revoked API keys should show a recovery prompt with an explicit
  Open OpenAI Settings action, while keeping the failed attempt available for
  retry after the key is fixed.
- Invalid or revoked API key recovery applies only after OpenAI rejects a
  request that used a resolved non-empty runtime credential. If the credential
  is missing or inaccessible before upload, the app must stop before provider
  contact and show missing or unavailable OpenAI setup instead of an invalid-key
  provider error.
- Network, timeout, rate-limit, provider-unavailable, unreadable-response, and
  empty-transcript failures may offer Retry directly from the recovery prompt
  and from recovery history.
- Retry from a failed attempt reuses only the temporary audio artifact and
  current safe transcription settings. It must not reuse stored API keys,
  provider payloads, prompts, nearby active-text context, or custom dictionary
  text from the failed attempt.
- On macOS, Try Again from the frontmost recovery prompt or menu recovery block
  behaves like a resumed dictation attempt for output delivery: when automatic
  insertion is enabled, a successful retry should insert the recovered
  transcript into the current active app. If insertion fails, the recovered
  transcript should remain available through Last Result when that setting is
  enabled. P4 iOS Retry ends at app-owned accepted-result presentation and never
  inserts into whichever external app happens to be active.
- A Try Again action must not be dropped silently while the app is finishing a
  short recording, transcription, or failure-presentation state transition. If
  the retry cannot start immediately, the app should run it after the current
  transition completes.
- Retry from recovery history should not automatically insert into the active
  app by default, because the active app and cursor may have changed since the
  original dictation. When Keep last result is enabled, retry success should
  save the recovered transcript there and tell the user how to insert it.

## Runtime Prompt Composition

`TranscriptionPromptComposition` is the pure transient value that freezes the
provider prompt and its matching local echo-guard inputs. It receives exactly a
resolved optional freeform prompt, an optional already-acquired and already-
authorized `TranscriptionPromptContext`, one `EmojiCommandsConfiguration`, and
one normalized `CustomDictionary`. It receives no full `AppSettings`, model,
language, credential, audio, provider response, output preference, history, or
platform permission state.

The provider prompt keeps the exact existing section order: freeform prompt,
Nearby Text context, prefixed emoji-command hints, then prefixed dictionary
spelling guidance. Non-empty sections are joined with exactly two newline
characters. When all four sources are absent, the provider prompt is `nil`.
The composition also exposes only the unprefixed dictionary prompt text and the
context text used by the existing local dictionary/context echo filters, so the
sent prompt and rejection guards derive from the same frozen inputs.

The macOS compatibility projection may pass Nearby Text context into this value
only when the existing setting and Accessibility acquisition path have already
allowed it. The composition does not acquire focused text, inspect permission,
approve Nearby Text reuse on iOS, or weaken the separate iOS bounded-context
privacy gate.

The value is runtime-only, `Equatable`, `Sendable`, and non-Codable. Prompt,
dictionary, emoji, and Nearby Text content must not be persisted through this
value, logged, placed in App Group, sent to the keyboard, or treated as a
durable request journal. Multipart construction, audio reading/upload, provider
transport, timeout, and real cancellation remain platform-adapter work.

## Runtime Audio Transcription Request

`AudioTranscriptionRequest` is the narrow transient input to the file-based
transcription adapter. It contains exactly one app-local audio file URL, one
resolved non-empty model, one optional validated language code, and one frozen
`TranscriptionPromptComposition`. The initializer resolves these provider
values from one `TranscriptionConfiguration`; it uses but does not retain the
raw configuration, so the freeform prompt cannot be duplicated outside the
composition.

Blank model still falls back to the current default. Auto and blank Custom
language still omit the language field; fixed and valid Custom language use the
same normalized provider codes. A non-empty invalid Custom code produces a
typed request-validation failure before audio is read or uploaded. The macOS
adapter maps that failure to its existing user-visible transcription-settings
error without changing copy or failure attribution.

Normal recording constructs the request from the attempt's captured settings
snapshot and the already-gated Nearby Text context. Explicit failed-attempt
Retry resolves current safe settings exactly once and constructs a fresh
composition with no Nearby Text. It reuses only the retained audio URL; it does
not reuse a prior prompt, dictionary, context, credential, provider payload, or
request value.

`OpenAICredential` remains a separate transient argument. The request is
`Equatable`, `Sendable`, and non-Codable. It has no duration, byte count,
session/attempt/history identity, timestamp, recovery or output policy,
authorization, response, persistence, App Group, keyboard, or logging
semantics. File validation, MIME selection, multipart construction, in-memory
response reading, transport, timeout, and real cancellation remain platform-
adapter concerns. Multipart audio preparation is file-backed and bounded; the
runtime request value still does not own its scratch-file lifecycle.

### iOS Pending-Recording Audio Request

- The URL-based `AudioTranscriptionRequest` remains the macOS compatibility
  boundary. P4 iOS provider work uses a separate reader-based request supplied
  only inside the one-shot `IOSPendingTranscriptionHandoff.execute` operation.
- The iOS request exposes only validated format, duration, byte count, resolved
  model, optional language, frozen prompt composition, and bounded offset reads.
  It exposes no URL, path, `FileHandle`, raw descriptor, attempt identity, or
  durable storage identifier.
- The neutral request accepts only `m4a` or `wav`, a positive duration shorter
  than five minutes, and a positive byte count below the existing 25,000,000-
  byte exclusive limit. Invalid metadata fails before scratch creation or a
  source read.
- Every reader call has a nonnegative offset and a positive requested size no
  larger than 64 KiB. A reader that returns more bytes than requested, returns
  early EOF before the declared byte count, or returns data after the declared
  boundary fails as changed or unreadable audio rather than reaching OpenAI.
- Multipart preparation reads directly from that reader into the existing
  protected multipart scratch body in chunks no larger than 64 KiB. It validates
  positive size below 25,000,000 bytes, exact declared-byte completion, empty
  EOF at the declared boundary, overflow-safe body size, and the existing form-
  field order.
- The adapter never materializes or reopens an equivalent source-audio path.
  Its private multipart scratch path is an upload-body implementation detail,
  not a source-audio handoff, and contains no attempt or source identity.
- One 60-second deadline covers reader consumption, multipart preparation,
  upload, any approved redirect replay, and response parsing. Cancellation
  invalidates the one-shot reader, cancels the transport task, rejects late
  completion, and returns without waiting indefinitely for a blocked read or
  cleanup operation.
- Explicit P4 Retry receives a fresh one-shot reader authorization with a fresh
  transcription ID, current safe Settings and Library values, current consent
  and credential, fresh prompt composition, fresh multipart boundary, and fresh
  scratch body. It never reuses a prior URL request, prompt, credential, body,
  or provider result.
- The OpenAI package owns only a neutral bounded-reader contract; it does not
  import Persistence. The iOS containing-app adapter binds the Pending reader
  to that contract for the duration of one execution and cannot retain it.

## Invariants

- The OpenAI API key is loaded from local secure storage into a process-local
  runtime credential cache and sent only as an authorization header for the
  transcription request.
- Transcription must not trigger macOS Keychain authentication UI. Credential
  access must be resolved before microphone capture starts by using the runtime
  credential cache, by the user saving a key in Settings, or by one lazy
  non-interactive credential read from an explicit recording-start preflight. If
  the saved key cannot be read without system authentication UI, recording must
  be blocked and Settings must ask the user to paste the key again.
- The OpenAI transcription service must receive a resolved session credential
  from the dictation flow. It must not read Keychain, check key availability, or
  fall back to a developer key source while preparing or sending the request.
- Missing or inaccessible API key blocks before upload.
- The complete multipart body is uploaded from a pinned, unlinked file
  descriptor. The caller's provider request carries neither `httpBody` nor
  `httpBodyStream`; URLSession receives replayable descriptor-backed streams
  only through its upload delegate. The API key remains only in the
  authorization header rather than the scratch file.
- Multipart scratch storage is private to the containing app, protected and
  excluded from backup where the platform supports those attributes. It uses
  random path components that contain no source filename, attempt identity, or
  user content.
- Scratch cleanup is idempotent on success, validation failure, provider
  failure, timeout, explicit cancellation, and parent-task cancellation. A
  cancellation or timeout result must not wait behind a blocked source read,
  scratch write, synchronization, upload-body read, or concurrent cleanup.
  Descriptor cleanup may finish after the blocked operation returns, but the
  scratch pathname must be absent immediately after successful pinning and
  eventually absent after cancellation during preparation. Cleanup must never
  mutate or remove the source recording. The same private-namespace threat
  boundary applies to check-then-unlink cleanup during failed preparation.
- New scratch bodies use a crash-recoverable two-name creation protocol. The
  app first creates an owner-only `0600` staging file named exactly as an
  uppercase canonical UUID plus `.multipart`, applies Complete protection and
  backup exclusion, and writes the descriptor-bound extended attribute
  `com.holdtype.openai.multipart-scratch` with the exact UTF-8 value `v1`.
  The marker uses create-only xattr semantics and is read back exactly. The
  writer also acquires a non-blocking exclusive advisory lock on its descriptor
  and holds it until the pathname is pinned/unlinked or the writer closes.
  Before writing body bytes it publishes that same inode with
  `renameatx_np(..., RENAME_EXCL)` as
  `htmp-v1-<lowercase-canonical-uuid>.multipart`; there is no replacing-rename
  fallback. Directory, staging path, descriptor, and final path identities are
  verified around publication through one opened private-directory descriptor.
  A failed marker, protection, lock, or publish step removes only the staging
  or final inode whose identity the operation owns. The final and staging names
  contain no source filename, attempt identity, credential, or user content.
- Cancellation is checked after every potentially blocking local preparation
  operation and again before pinning or starting URLSession. Work that returns
  after its request already timed out or was cancelled must not launch an
  abandoned upload.
- The adapter uses a normal foreground URL session. File-backed transport does
  not by itself approve a background session or satisfy the separate P6 gate.
- The foreground session is ephemeral and stores no cookies, cache, or URL
  credentials. It follows only HTTP 307 or 308 redirects within the exact
  original scheme/host/effective-port origin. Each accepted replay request is
  rebuilt from the trusted original POST method and approved Accept,
  Content-Type, Content-Length, and Bearer authorization values; it replays the
  exact same artifact bytes from offset zero. Cross-origin redirects, 301, 302,
  303, unknown authorization schemes, authentication-driven or otherwise
  opaque replays, nonzero-offset resumptions, and requests that cannot be
  replayed from those trusted values are rejected before credentials or body
  bytes reach the destination.
- The original provider URL must use HTTPS and provider URLs containing user
  information are invalid. URLSession may use
  normal platform server-trust handling, but all HTTP authentication challenges
  are rejected instead of supplying a credential or granting another body
  stream.
- The fixed transcription endpoint permits at most one approved 307/308
  redirect per provider call. A second redirect is rejected before another
  task, credential, or body replay is created; the service's single total
  deadline continues to bound the original request and its one replay.
- Failure to open, read, or replay the pinned multipart artifact is a typed
  local multipart/preparation failure. It must not be presented as network
  unavailability or a provider rejection.
- A process crash can leave a protected scratch pathname. Each normal
  containing-app process schedules one asynchronous, non-blocking maintenance
  pass over only `<temporary-directory>/holdtype-openai-multipart/`; a missing
  namespace is a successful no-op and maintenance never creates it.
- The public startup hook is content-free: it takes no URL or payload, returns
  no filenames, counts, or errors, starts no provider/Keychain/audio work, and
  schedules at most once per process. The macOS app calls it only after ruling
  out the one-shot Input Monitoring recovery launch; the iOS containing app
  calls it during app initialization. The keyboard remains unlinked from
  `HoldTypeOpenAI` and cannot call the hook.
- The pass opens the exact namespace without following a symbolic link and
  proceeds only when it is an `0700` directory owned by the effective user. It
  does not create, chmod, protect, or otherwise repair the directory. It
  enumerates incrementally through that same directory descriptor and never
  recurses. Raw ASCII names must match either
  `htmp-v1-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}.multipart`
  plus the exact two-byte `v1` xattr, or the legacy/staging grammar
  `[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}.multipart`.
  Marked and unmarked legacy/staging names use the same 24-hour rule. Lower-
  case legacy-like, malformed, unmarked v1, wrongly marked, nested, or unrelated
  entries remain untouched; UUID parsing alone is not accepted as the grammar.
- A recognized candidate is removable only when it is a no-follow regular file
  owned by the effective user, has exact `0600` permissions, one link, a
  nonnegative size, and grants the scanner a non-blocking exclusive advisory
  lock. A live creator's lock therefore protects the pathname even across
  another containing-app process or a wall-clock jump. Immediately before
  descriptor-relative unlink, the scanner repeats descriptor and no-follow
  path status, identity, type, owner, mode, link-count, size, age, and budget
  checks; a v1 file's descriptor xattr is also reread and must still be exactly
  `v1`. Symbolic links, directories, hard links, active files, and a raced or
  mutated replacement are never removed. This still assumes the private
  sandbox without a hostile same-UID interposer in the final
  identity-check/unlink window; no kernel-level conditional-unlink guarantee is
  claimed.
- Age is measured from the newer of modification and change time. A marked v1
  file becomes eligible at exactly one hour; a legacy/staging filename becomes
  eligible at exactly 24 hours. Future timestamps remain untouched. Wall time
  is captured once and file times are compared at nanosecond precision. One
  pass inspects at most 256 directory entries other than the literal `.` and
  `..`, removes at most 32 files, and charges at most 512 MiB of logical
  `st_size` from each candidate's final pre-deletion snapshot. An exact
  count/byte boundary is allowed; a candidate whose final charge would exceed
  the byte budget is not removed and ends the pass.
- The pass also has a one-second monotonic work budget. An injected monotonic
  clock is checked before each new enumeration, open, metadata, lock, attribute,
  or deletion syscall; at elapsed time greater than or equal to one second no
  new inspection/deletion syscall starts. Required descriptor cleanup still
  runs. One already-started local syscall may finish later, so this is a
  bounded-work contract rather than a hard real-time deadline. Production uses
  one internal POSIX adapter plus wall/monotonic clocks; tests replace all three
  to prove exact age, race, and resource boundaries.
- Any namespace, entry, attribute, clock, or removal error fails closed for
  deletion: the candidate stays in place and app launch/provider use continues.
  The pass emits no path, filename, size, audio, prompt, credential, or content
  through its public API or default product logs. Repeated launches are
  idempotent and can finish work left beyond an earlier pass's bounds.
- Post-capture transcription failure handling must not save, delete, clear,
  rewrite, or validate Keychain API key storage. It may only explain the error
  and offer navigation to Settings as an explicit user action.
- API keys, authorization headers, raw audio, prompt text, nearby active-text
  context, custom dictionary entries, raw transcript text, and full provider
  responses must not appear in default logs.
- Default logs should report only compact outcomes, such as transcription
  started, succeeded, timed out, or failed with a short error category.
- Transcription must have an explicit maximum wait time and must never wait
  indefinitely.
- A failed transcription must not overwrite a previous successful transcript.
- Post-capture transcription failure UI must settle in this order: terminal
  failure status first, active recording/transcribing indicators hidden next,
  and any blocking recovery prompt only after those visible surfaces are no
  longer active. The user's first Try Again click must start the retry; it must
  not be consumed by stale UI cleanup such as hiding a still-visible
  transcribing indicator.
- The completed recording file should be deleted after the current attempt
  finishes when recording cache retention is off.
- When recording cache retention is on, the completed recording file may remain
  in the app-owned recording cache after successful or failed transcription so
  the user can reveal or save it from Finder.
- When recording cache retention is on, an accepted transcript history row may
  link to the app-owned cached recording for local Play from Transcript History.
  The link is available only while Recording Cache is still enabled and the
  cached file still exists.
- Recoverable failed attempts may keep one app-owned temporary audio artifact
  even when normal recording cache retention is off. This exception is
  session-only, visible in Transcript History, bounded by retention, and cleared
  when the attempt succeeds, is deleted, history is cleared, history is turned
  off, or the app quits.
- Recording cache retention must be bounded by default to the 10 most recent
  recordings. Unlimited retention is allowed only after the user explicitly
  selects it in Settings.
- Normal tests and automations must use fakes or fixtures and must not call the
  live OpenAI API.
- Usage estimate recording must not store API keys, authorization headers, raw
  audio, prompt text, nearby active-text context, custom dictionary entries, raw
  transcript text, or full provider responses.
- Tests for recovery prompts should use fakes to cover the ordering between
  terminal failure status, failed-attempt presentation, floating indicator
  hiding, and Try Again retry dispatch. Do not rely on live OpenAI, microphone
  input, or toggling real network connectivity to prove this ordering.
- Prompt-composition tests must cover each individual source, the exact
  four-source order and separators, disabled/empty emoji and dictionary inputs,
  gated versus omitted Nearby Text, echo-guard values, `Sendable`, and the
  absence of a Codable transport contract through normal iOS import.

## Timeout and retry policy

- The MVP transcription request has a default 60 second maximum wait covering
  multipart preparation, upload, and response.
- Cancelling an in-flight transcription must synchronously cancel the actual
  transport task. Repeated cancellation and cancellation with no active request
  are safe no-ops, and the cancelled call completes with the existing
  `cancelled` product error.
- Parent-task cancellation must reach the same transport task. A response that
  arrives after cancellation must be discarded before response validation or
  transcript parsing, even when a loader does not cooperate with cancellation.
- Cancellation and timeout completion must be bounded at the provider adapter:
  after the transport task is cancelled, the calling session must finish
  without waiting for the loader or any local file operation to cooperate.
  Any abandoned late completion is ignored and may perform only bounded,
  identity-safe cleanup.
- Request cleanup is identity-aware: completion or cancellation of an older
  request must not clear or cancel a newer request, and a later request can
  complete independently.
- If the timeout expires, the attempt fails visibly as `Transcription timed
  out`; the app returns to a recoverable state. Timeout cleanup cancels the
  transport task without changing the attempt from `timedOut` to `cancelled`.
- The MVP does not silently retry transcription requests.
- The user may start a new recording after a timeout or provider failure.
- The user may retry a recoverable failed attempt from Transcript History.
- Retrying a failed attempt is an explicit user action and counts as a new
  bounded OpenAI transcription request.
- Retry reuses the retained source recording but builds a fresh scratch body
  from current safe settings and a fresh multipart boundary. A prior scratch
  body is never retained or reused.
- A future implementation may add one bounded retry for clearly transient
  network or server failures, but it must not retry invalid credentials,
  invalid settings, unsupported audio, empty transcripts, or rate-limit
  responses without a user-visible delay policy.

## Edge cases and failure policy

- Missing API key: show that an OpenAI API key is required before
  transcription.
- Keychain read failure: show that the API key is unavailable and do not make
  an unauthenticated request.
- Invalid or revoked API key: show that OpenAI rejected the API key, keep any
  recoverable completed recording available, and offer an explicit Open OpenAI
  Settings action. Do not auto-open Settings.
- Inaccessible API key: show that HoldType could not read the saved key. Do not
  describe this as an invalid provider key, and do not change Keychain storage.
- Network unavailable: fail the attempt with a recoverable network error.
- Timeout: fail the attempt with a timeout message and no transcript update.
- Rate limit: show that OpenAI rate limits were reached and ask the user to try
  later.
- Provider unavailable or server error: show that OpenAI is unavailable and ask
  the user to retry later.
- Bad model, language, prompt, or file request: show that transcription
  settings or recording format need attention.
- Unsupported, changed-during-preparation, or too-large file: show that the
  recording cannot be sent.
- Multipart scratch creation, protection, or write failure: preserve the
  source recording and show that the request could not be prepared. Do not
  misreport local storage failure as a provider rejection.
- Empty transcript: show a no-speech or no-text-detected error and keep the
  previous transcript intact.
- User cancellation: stop the current session without uploading new audio if
  upload has not started; if upload is already in flight, cancel the request
  when practical and discard the result.

## Route / state / data implications

- The central dictation state should enter `transcribing` only after recording
  stops and an uploadable file exists.
- OpenAI settings include model, language mode, custom language code, prompt,
  custom dictionary entries, and whether nearby active-text context is enabled.
- Provider failures map to product errors before they reach menu, settings, or
  output views.
- Product errors expose a compact user-facing message plus a stable
  operator-log category. Default logs may use only the category and must not
  include request payloads, API keys, prompts, audio, or transcript text.
- Transcript text is accepted only after response parsing, trimming, and empty
  result validation.
- Failed transcription recovery stores only compact failure metadata plus a
  temporary local audio file reference needed for retry. It must not store API
  keys, authorization headers, provider responses, prompt text, nearby
  active-text context, custom dictionary entries, or transcript text.
- The text-correction workflow receives only accepted transcript text, not raw
  provider responses.
- The text-output workflow receives final corrected text when correction is
  enabled and accepted transcript text when correction is skipped.
- The post-transcription action workflow receives final corrected text when
  correction is enabled and accepted transcript text when correction is
  skipped.
- The text-output workflow receives the final post-action output text.
- The local usage estimate workflow receives only the selected model and audio
  duration after a successful transcription.
- The normal recording cache workflow receives only the completed audio file URL
  and retention setting. It must not store provider responses, API keys,
  prompts, nearby active-text context, custom dictionary entries, or transcript
  text.
- The transcript history playback workflow may receive a session-only reference
  to the completed recording cache file. It must use that reference only for
  local playback and must not upload, retranscribe, log, or persist the path.

## Verification mapping

- Add fake-backed tests for missing key, invalid key, rate limit, timeout,
  network failure, bad settings, unsupported or empty audio, server failure,
  empty transcript, dictionary echo rejection, successful response parsing,
  failed-attempt recovery rows, retry from failed attempts, compact error
  messages, and log redaction when implementation exists.
- Use controllable URLSession or service fakes rather than live OpenAI calls.
- Test timeout behavior with an injectable delay or clock so verification stays
  bounded.
- Test explicit cancellation with a loader that observes cancellation but does
  not return until released; the provider call must finish before that release.
- Test cancellation and timeout while source read, scratch write,
  synchronization, and upload-body `pread` are blocked. The provider call must
  finish promptly, the scratch pathname must be absent immediately or
  eventually as appropriate, and descriptor cleanup must complete after the
  blocked operation is released without a waiting cleanup state machine.
- Test that replacing the finalized scratch pathname still uploads the original
  pinned bytes and preserves the replacement; independent streams must each
  replay the whole body and support independent offsets.
- Test exact-origin 307 and 308 replay with the original Bearer credential and
  byte-identical body, and prove that cross-origin plus 301, 302, and 303
  destinations receive neither a credential nor body bytes.
- Test early EOF and descriptor read failures as redacted typed local multipart
  failures rather than network failures.
- Test that new bodies publish the exact v1 name and descriptor-bound marker
  before content writes; marker/protection/publish failure preserves source and
  cleans only the operation-owned staging inode.
- Test startup maintenance at `59:59`/one hour and `23:59:59`/24 hours; exact
  filename/xattr matching; missing namespace; symlink, hardlink, directory,
  nested, valid `m4a`/`wav` source-name, and replacement-race preservation;
  idempotency; and the exact 256-entry, 32-removal, 512-MiB, and one-second
  boundaries. An arbitrary old owner-only file deliberately placed inside the
  private namespace with the exact legacy grammar is indistinguishable from a
  legacy orphan and is not claimed as a protected source recording.
- Test that a creator-held advisory lock protects an otherwise old v1 file and
  that a crash-released/unlocked orphan can be removed. Repeat every final
  status/xattr/budget check after an injected pre-unlink mutation.
- Test that a normal macOS launch and iOS initialization schedule the content-
  free hook, while the one-shot Input Monitoring recovery launch does not.
  Inspect the built keyboard target to confirm it still has no
  `HoldTypeOpenAI` dependency.
- Test active-text context with fake Accessibility/context readers. Normal tests
  must not read live focused app contents.
- Test usage estimate handoff with fake storage and fake transcription services.
- Test recording cache cleanup, retention, and history playback availability
  with fake file-system boundaries; normal tests must not depend on live OpenAI
  calls.
- Keep app-run or manual QA for real microphone and provider behavior separate
  from normal automation.

## Unknowns requiring confirmation

- Whether 60 seconds remains the right timeout after real recordings are tested.
- Whether the default model should optimize for quality, cost, or latency after
  first user trials.
- Whether custom language input should accept only ISO-639-1 codes or a wider
  set when the UI is implemented.
- Whether dictionary auto-learn should be added after active-app text insertion
  is stable enough to observe user corrections safely.
- Whether nearby active-text context should become default-on after real-user
  privacy copy and host-app compatibility are validated.
