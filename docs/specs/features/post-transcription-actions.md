# Post-Transcription Actions

## Goal

Define optional actions that may run after a successful transcription before
HoldType accepts and outputs final text.

The first action is a configurable OpenAI translation mode for dictation
started with a dedicated shortcut.

## Scope

- Shortcut-triggered post-transcription output intent.
- OpenAI translation after transcription.
- Settings for enabling the translation shortcut.
- Settings for translation source behavior, target language, model, and prompt.
- Handoff ordering with text correction, Last Transcript, history, clipboard,
  and automatic insertion.
- Failure behavior for translation requests.

## Non-goals

- Automatic language detection for translation mode.
- Review-before-insert UI.
- Chained actions inside the post-transcription pipeline.
- Immediate selected-text and Draft actions, which are governed by
  `text-fixes.md`.
- Live OpenAI calls in normal tests.

## User-visible behavior

- The normal `Right Command` hold shortcut keeps the existing dictation
  behavior and outputs the final transcript in the transcription language.
- Settings may expose a special `Right Command+Option` hold shortcut mode that
  translates the accepted transcript to the configured target language after
  transcription.
- The special translation shortcut is enabled by default. Translation still
  requires a configured target language before HoldType can make the additional
  OpenAI text request after transcription.
- Starting a translation-mode session with an unconfigured target language or
  invalid source override should fail immediately, show a user-visible error,
  and open Settings focused on Translation so the user sees the language warning.
  This recovery opening should not place keyboard focus into the translation
  model or prompt text fields.
- If an active normal recording is promoted to translation before stop, HoldType
  should stop the recording, fail before transcription or translation requests
  when translation languages are not configured, and focus Settings on
  Translation.
- The Translation Settings section should include source behavior, target
  language, translation model, and an editable translation prompt with a Reset
  action.
- Translation source behavior should default to Same as Transcription. In this
  mode, translation uses the transcript produced by the normal transcription
  settings and must not override the transcription language.
- If the normal transcription language is Auto, OpenAI translation instructions
  should omit a source-language code and translate the transcript as written.
- Translation source behavior may provide an explicit source-language override
  for users who need it. Source override choices should include common preset
  language codes plus Custom.
- Target language choices should include common preset language codes plus
  Custom.
- New installs should not silently default to a personal target language. The
  target language should start unconfigured.
- If the target language is unconfigured or invalid, or if an explicit source
  override is invalid, a translation-mode session must fail visibly before
  output delivery and must not make transcription or translation requests when
  the invalid configuration is known before those requests.
- If translation mode is disabled, the special shortcut must behave like normal
  dictation.
- Translation runs after successful transcription and after the existing
  optional text-correction and local cleanup stages.
- When local plain-typography cleanup is enabled, successful translation output
  receives one final local typography cleanup before it becomes accepted text.
  This final pass must not rerun OpenAI correction, emoji command replacement,
  or user replacement rules.
- The final translated text becomes the accepted output text. Last Transcript,
  recovery history, Last Result, and automatic insertion use the final
  translated text.
- Translation should return only the translated text, without notes,
  markdown, explanations, alternatives, diagnostics, or source text.
- The translation prompt should be editable even when the translation shortcut
  is off, so the user can prepare settings before enabling the shortcut.
- A blank or whitespace-only translation prompt should fall back to HoldType's
  default translation prompt.
- The immediate Translate Fix reuses this saved route and provider behavior but
  is not a post-transcription output intent. It changes only the captured text
  target and never Last Transcript, Last Result, History, or automatic
  insertion.

## Runtime Translation Request

`TextTranslationRequest` is the transient containing-app input to translation.
It contains exactly one validated `AcceptedTranscript`, one
`TranslationConfiguration`, and the final optional source-language code
resolved from the same captured settings snapshot. Same as Transcription + Auto
stores no source code; Same as Transcription + fixed/custom stores the effective
transcription code; Override stores its own validated override code. The value
does not retain all of `TranscriptionConfiguration`, so the transcription model
and freeform prompt cannot cross the translation boundary accidentally.

The normal path constructs the request only for an effective Translation intent
after transcription and the optional fail-open correction/local-processing
pipeline have produced non-empty accepted text. The controller keeps its
enabled/readiness preflight and uses one captured settings snapshot through
transcription, correction, translation, final acceptance, and output. Invalid
source override or missing target creates no translation request and no network
call. The current macOS failed-attempt Retry remains transcription-only and must
not invent Translation intent.

`OpenAICredential` remains a separate transient argument. The provider adapter
receives only the accepted source text, resolved source route, target/model/
prompt values from `TranslationConfiguration`, and that credential. It does not
receive full `AppSettings`, `TranscriptionConfiguration`, the transcription
prompt, nearby context, dictionary entries, emoji-command definitions,
replacement rules, History/retention settings, output preferences, audio, or
keyboard/App Group state.

The request is runtime-only, `Equatable`, `Sendable`, and non-Codable. It has no
session, attempt, history, document, or target identity; output intent;
timestamp; recovery policy; provider response; platform result; or user-facing
copy. It is not persisted, logged, placed in App Group, sent to the keyboard,
or used as a durable translation journal. Provider transport, timeout, and real
cancellation remain platform-adapter concerns.

Final plain-typography cleanup stays controller-owned and outside the request.
It may run once after successful translation using the captured setting, but it
must not rerun correction, emoji commands, or replacement rules. Translation
remains strict rather than adopting correction's fail-open behavior.

## Invariants

- Translation must never run after a failed or empty transcription.
- Translation must never overwrite a previous successful transcript after a
  failed transcription.
- Translation failure must not silently insert or save the untranslated
  transcript as if the special translation action succeeded. A protected
  recovery recording may retain the accepted raw transcription only in its
  clearly labelled recovery row; that row must say post-processing failed and
  must never imply that translation succeeded.
- The translation request must have an explicit timeout and must never wait
  indefinitely.
- Cancelling an active dictation session during translation must cancel the
  in-flight provider transport, not only ignore its eventual result. The
  translation call must finish as cancelled, and any response that arrives
  later must not become accepted or delivered text.
- Provider timeout remains distinct from user cancellation: expiry must still
  finish as a translation timeout while also stopping the in-flight transport.
- Cancellation and timeout completion must be bounded at the provider adapter:
  the translation call must finish without waiting for a cancelled loader to
  cooperate, and any abandoned late completion is ignored.
- Cancellation is safe to repeat and is a no-op when no translation is active.
  Finishing or cancelling an older request must not cancel a newer translation,
  and a later request must be able to complete independently.
- API keys, raw transcript text, translation prompts, and provider responses
  must not appear in default logs.
- Normal tests must use fakes or fixtures and must not call the live OpenAI API.

## Edge cases and failure policy

- Missing API key, invalid API key, rate limit, network failure, provider
  failure, timeout, unreadable response, or empty translation should fail the
  current translation-mode session visibly.
- Explicit translation cancellation remains strict rather than fail-open: the
  cancelled translation must not fall back to accepting or delivering the
  untranslated transcript.
- If translation fails, the previous Last Transcript remains intact and no
  output delivery or normal accepted recovery-history entry occurs for the
  failed session. For a protected recovery recording, the existing audio
  recovery row keeps the raw provider transcription under `Raw transcription
  recovered — post-processing failed`, with Play, Delete, and `Save Raw
  Transcription`; it does not become a translated result and never offers
  provider Retry.
- If text correction fails before translation, correction follows its existing
  fail-open policy and translation receives the accepted transcription text.
- If final typography cleanup would produce empty translated output, the app
  should keep the pre-cleanup translation result.
- If translation succeeds but automatic insertion fails, the translated text
  remains accepted and recoverable under the normal text-output workflow.
- If the shortcut key-up arrives without a matching translation-mode recording,
  it must not create an output action.
- If translation configuration failure opens Settings, the recovery action
  should target the Translation section rather than the OpenAI API key or
  Transcription sections.

## Route / state / data implications

UserDefaults may store:

- whether the translation shortcut is enabled
- translation source behavior
- translation source language override selection
- custom translation source language code
- translation target language selection
- custom translation target language code
- translation model
- translation prompt

Keychain still stores only the OpenAI API key.

Translation uses the same Keychain API key as transcription but is a separate
OpenAI text request from the audio transcription request.

The active dictation session state must carry an output intent so the
recording-start event can determine whether the stopped session should produce
normal output or translated output.

Usage estimates for audio transcription remain governed by
`openai-transcription.md`; translation token accounting requires a future
usage-estimate spec before the Billing section may claim translation costs.

## Verification mapping

- App settings tests should cover the default-on setting and persistence.
- Hotkey tests should cover carrying translation intent from key down to the
  matching key up.
- App settings tests should cover language preset resolution, custom code
  validation, default prompt reset, and legacy Russian-to-English setting
  migration.
- Controller tests should cover successful translation output, disabled
  translation falling back to normal output, invalid translation settings
  failing visibly without output, final translation typography cleanup without
  replacement rules, and translation failure preserving the previous accepted
  transcript.
- OpenAI translation service tests should cover request construction, output
  parsing, timeout mapping with transport cancellation, explicit cancellation,
  bounded completion with a non-cooperative loader, late-response rejection,
  independent next requests, provider error mapping, and no live API calls.
- Runtime request tests should cover exact accepted text/configuration/source
  preservation; Same as Transcription Auto, fixed/custom, and Override routes;
  `Sendable`; and the absence of a Codable transport contract through normal
  consumer-module import.
- Translation boundary tests should prove that no full `AppSettings`,
  transcription model/prompt, local replacement configuration, or output
  preference reaches the provider adapter.

## Unknowns requiring confirmation

- Whether Billing should estimate text translation costs.
