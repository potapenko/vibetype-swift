# OpenAI Transcription

## Goal

Define the product contract for sending completed VibeType recordings to
OpenAI and turning the returned transcript into app text.

The MVP uses OpenAI's file-based transcription endpoint for bounded dictation
requests. It does not use realtime microphone streaming.

## Scope

This spec covers:

- the OpenAI transcription request and response contract
- model, language, prompt, and custom dictionary settings
- optional nearby active-text context for continuation quality
- timeout and retry behavior
- user-visible errors for common provider failures
- privacy and logging constraints for API keys, audio, prompts, and transcripts

## Non-goals

- implementing URLSession upload code
- calling the live OpenAI API during normal automation or tests
- adding provider abstractions beyond the OpenAI MVP
- using the translations endpoint, realtime transcription, diarization, speaker
  labels, timestamps, subtitles, or streaming transcript deltas
- retaining audio for history, analytics, telemetry, or recovery
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
- If both a freeform prompt and dictionary entries exist, the request prompt
  should include both, with the dictionary appended as spelling context.
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
  context, custom dictionary spelling context.
- If the provider returns only, or almost only, the dictionary hint itself, the
  app must reject the result instead of accepting it as dictated text.
- If the provider returns only a copied excerpt of nearby active-text context,
  the app must reject the result instead of accepting it as new dictated text.
- The MVP requests the normal JSON transcription response and reads the
  returned `text` field.
- A successful non-empty transcript becomes the app's last transcript and is
  passed to the configured output workflow.
- A whitespace-only or empty transcript is a failed session, not a successful
  accepted transcript.

## Invariants

- The OpenAI API key is read from Keychain and sent only as an authorization
  header for the transcription request.
- Missing or inaccessible API key blocks before upload.
- API keys, authorization headers, raw audio, prompt text, nearby active-text
  context, custom dictionary entries, raw transcript text, and full provider
  responses must not appear in default logs.
- Default logs should report only compact outcomes, such as transcription
  started, succeeded, timed out, or failed with a short error category.
- Transcription must have an explicit maximum wait time and must never wait
  indefinitely.
- A failed transcription must not overwrite a previous successful transcript.
- The temporary audio file should be deleted after successful transcription.
  Failed attempts must not persist audio beyond the current session unless a
  future debug spec explicitly allows it.
- Normal tests and automations must use fakes or fixtures and must not call the
  live OpenAI API.

## Timeout and retry policy

- The MVP transcription request has a default 60 second maximum wait covering
  upload and response.
- If the timeout expires, the attempt fails visibly as `Transcription timed
  out`; the app returns to a recoverable state.
- The MVP does not silently retry transcription requests.
- The user may start a new recording after a timeout or provider failure.
- A future implementation may add one bounded retry for clearly transient
  network or server failures, but it must not retry invalid credentials,
  invalid settings, unsupported audio, empty transcripts, or rate-limit
  responses without a user-visible delay policy.

## Edge cases and failure policy

- Missing API key: show that an OpenAI API key is required before
  transcription.
- Keychain read failure: show that the API key is unavailable and do not make
  an unauthenticated request.
- Invalid or revoked API key: show that OpenAI rejected the API key and direct
  the user back to Settings.
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
- The text-output workflow receives only accepted transcript text, not raw
  provider responses.

## Verification mapping

- Add fake-backed tests for missing key, invalid key, rate limit, timeout,
  network failure, bad settings, unsupported or empty audio, server failure,
  empty transcript, dictionary echo rejection, successful response parsing,
  compact error messages, and log redaction when implementation exists.
- Use controllable URLSession or service fakes rather than live OpenAI calls.
- Test timeout behavior with an injectable delay or clock so verification stays
  bounded.
- Test active-text context with fake Accessibility/context readers. Normal tests
  must not read live focused app contents.
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
