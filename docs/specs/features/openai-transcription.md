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

- implementing URLSession upload code
- calling the live OpenAI API during normal automation or tests
- adding provider abstractions beyond the OpenAI MVP
- using the translations endpoint, realtime transcription, diarization, speaker
  labels, timestamps, subtitles, or streaming transcript deltas
- retaining audio for analytics, telemetry, or transcript history outside the
  explicit local recording cache setting
- auto-learning dictionary entries from edits in other apps
- snippets, text expansion, or cloud-synced dictionary behavior

## Evidence

- OpenAI Speech to Text guide, reviewed 2026-06-20:
  `https://developers.openai.com/api/docs/guides/speech-to-text`
- OpenAI Create transcription API reference, reviewed 2026-06-20:
  `https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create`

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
- If the audio file is missing, empty, too short to be useful, unsupported, or
  too large for the OpenAI file upload limit, the app must fail before or
  during transcription with a clear recording error.
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
- Try Again from the frontmost recovery prompt or menu recovery block should
  behave like a resumed dictation attempt for output delivery: when automatic
  insertion is enabled, a successful retry should insert the recovered
  transcript into the current active app. If insertion fails, the recovered
  transcript should remain available through Last Result when that setting is
  enabled.
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
audio reading, transport, timeout, and real cancellation remain platform-
adapter concerns; bounded file-backed upload remains required in P2.

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
  upload and response.
- If the timeout expires, the attempt fails visibly as `Transcription timed
  out`; the app returns to a recoverable state.
- The MVP does not silently retry transcription requests.
- The user may start a new recording after a timeout or provider failure.
- The user may retry a recoverable failed attempt from Transcript History.
- Retrying a failed attempt is an explicit user action and counts as a new
  bounded OpenAI transcription request.
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
- Unsupported file or file too large: show that the recording cannot be sent.
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
