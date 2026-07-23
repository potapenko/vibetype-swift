# Text Correction

## Goal

Define the optional post-transcription correction stage for HoldType.

Text correction should make dictated text cleaner after transcription without
turning dictation into a rewriting product. The default behavior must preserve
the transcribed wording and avoid a second OpenAI call unless the user turns
model-based correction on.

## Scope

- Settings for post-transcription text correction.
- Local typography cleanup for common AI-looking punctuation artifacts.
- Built-in voice emoji command replacement before user replacement rules.
- User-managed literal search/replace rules.
- Optional OpenAI-powered minimal transcript correction.
- Failure behavior when correction is unavailable or returns unsafe output.
- Handoff of corrected text to last transcript, history, clipboard, and
  automatic insertion.

## Non-goals

- A persistent transcript editor.
- Review-before-insert workflow.
- Automatic learning from corrections in other apps.
- Regex, scripting, or arbitrary code replacement rules.
- Translation, summarization, tone rewriting, or content expansion.
- Immediate selected-text and Draft Fixes, which are governed by
  `text-fixes.md`.
- Live OpenAI calls in normal tests.

## User-visible behavior

- Settings must include a dedicated Text Correction section.
- OpenAI text correction is off by default.
- When OpenAI text correction is off, the app must not make a second OpenAI
  text-generation request after transcription.
- When OpenAI text correction is on, a successful transcription may be sent to
  OpenAI for one additional minimal correction pass before it becomes accepted
  output.
- The default correction model is `gpt-5.5`. The user may choose a cheaper or
  faster model such as `gpt-5.4` or `gpt-5.4-mini`, or enter a custom model.
- The default correction prompt must ask for the smallest possible edits only:
  obvious transcription errors, spacing, capitalization, and punctuation. It
  must explicitly forbid rewriting style, adding facts, removing facts,
  translating, summarizing, or making uncertain changes.
- The correction prompt field should show the standard correction prompt as
  editable text by default, not as a hidden empty override.
- The Text Correction section must provide a Reset action that restores the
  standard correction prompt after the user edits it.
- The correction prompt may be edited or reset while OpenAI correction is off;
  editing the prompt must not enable or trigger the additional OpenAI request.
- OpenAI correction should return only the corrected text, without notes,
  markdown, explanations, alternatives, or diagnostics.
- Local plain-typography cleanup is on by default because it does not consume
  OpenAI resources.
- Local plain-typography cleanup may replace typographic quotes, typographic
  apostrophes, long dash variants, single-character ellipsis, non-breaking
  spaces, and word-joiner characters with plainer informal text equivalents.
- User replacement rules are an ordered list of literal, case-insensitive
  search/replace pairs. They are empty by default.
- Replacement rule search text is matched literally, not as a regular
  expression. The replacement text is inserted exactly as configured.
- Replacement rules with empty or whitespace-only search must be ignored.
- On iOS, Replacement Rules is a searchable Library list with UUID detail
  editors and explicit Save. Add, per-row enablement, confirmed delete, and
  reorder are separate atomic actions. Reorder is unavailable while the list
  is filtered. A new rule requires non-whitespace Search before its first Save;
  an existing empty-search row remains visible, editable, and preservable as
  inactive. A new rule is enabled and appended after the current last rule on
  its first Save. An identical Search value is valid and is not a duplicate.
- The iOS Replacements destination presents local plain-typography cleanup
  before custom replacement rules. It exposes the existing cleanup preference
  as an automatic-cleanup toggle, states that it is on by default and local,
  and lists the complete user-relevant transformation groups: typographic
  quotes and apostrophes, long-dash variants, single-character ellipsis,
  special spaces, word joiners, and repeated spacing. This is another control
  for the same durable preference shown in Writing & Correction, not a second
  setting or synthetic replacement-rule collection.
- The Library summary calls the durable rows custom rules and reports their
  count and effective active count: `0 custom rules` when empty, otherwise
  `N custom rules · M active`. A rule is active only when it is enabled and
  has non-whitespace Search. The list preserves
  durable order and shows Search, Replacement, and one clear `Active`, `Off`,
  or `Inactive — empty search` status. Empty Search never renders as an
  unexplained blank row. Empty Replacement is a valid visible value and is
  explained as removing matched text; whitespace-only Replacement remains
  distinct and is labeled as containing only whitespace. Duplicate Search
  values remain separate UUID-addressed rows. Status priority is exact:
  empty/whitespace-only Search is Inactive regardless of the saved enablement
  preference; otherwise a disabled row is Off and an enabled row is Active.
- Search filters both raw Search and Replacement values without changing their
  order or merging duplicates. Only a non-whitespace ephemeral query activates
  filtering, and matching is case-insensitive without mutating either stored
  field. Starting an active search leaves list edit mode, hides reorder
  affordances, and cannot reorder a filtered subset. Clearing search restores
  the complete durable order.
- Reorder is available through native list editing and equivalent VoiceOver
  move actions. Each move submits one expected complete UUID sequence and one
  requested sequence containing exactly the same IDs. Any optimistic ordering
  state contains only UUIDs, uses the latest durable row fields, and rolls back
  to durable order after failure or conflict.
- The detail draft owns only raw Search and Replacement text. Enabled state
  remains a separate list action. Editing does not trim, case-fold, deduplicate,
  autocorrect, capitalize, or otherwise rewrite either field. Both fields are
  multiline and preserve leading/trailing whitespace and newlines. Per-field
  UIKit rewriting traits such as smart quotes, smart dashes, inline completion,
  and Writing Tools are disabled. System-wide keyboard shortcuts that UIKit
  does not expose per field remain system-owned; HoldType stores their resulting
  string without another normalization pass. An existing
  blank Search may be saved, and an empty Replacement may be saved for both new
  and existing rules. Confirmed Delete is available from the list and existing
  detail; deleting a dirty detail draft discards it only after confirmation.
- Built-in emoji command replacement is governed by
  `voice-emoji-commands.md`. When enabled, it runs after local typography
  cleanup and before user replacement rules.
- Local cleanup and user replacement rules run after OpenAI correction when
  OpenAI correction is enabled, and run directly on the transcript when OpenAI
  correction is disabled.
- Translation mode may run one final local plain-typography cleanup pass on the
  translated output as defined in `post-transcription-actions.md`; that final
  pass must not include emoji command replacement or user replacement rules.
- The app's Last Transcript, transcript recovery history, Last Result,
  and automatic insertion receive the final corrected text.
- If correction is disabled or every correction stage is skipped, the accepted
  transcript is the normal transcription result.
- The immediate built-in Fix action may force this saved correction model and
  prompt for one captured text target without enabling automatic correction.
  It changes no dictation, Latest, History, or Usage state.

## Invariants

- Text correction must never overwrite a previous successful transcript after
  a failed transcription.
- Text correction must fail open: if an optional correction stage fails, times
  out, returns empty text, or returns an unsafe output, the app should preserve
  the successful transcription result.
- OpenAI correction must have an explicit timeout and must never wait
  indefinitely.
- Cancelling an active dictation session during OpenAI correction must cancel
  the in-flight provider transport, not only ignore its eventual result. A
  cancelled correction must finish as cancelled at the provider boundary, and
  any response that arrives later must not become accepted text.
- Provider timeout remains distinct from user cancellation: expiry must still
  finish as a correction timeout while also stopping the in-flight transport.
- Cancellation and timeout completion must be bounded at the provider adapter:
  the correction call must finish without waiting for a cancelled loader to
  cooperate, and any abandoned late completion is ignored.
- Cancellation is safe to repeat and is a no-op when no correction is active.
  Finishing or cancelling an older request must not cancel a newer correction,
  and a later request must be able to complete independently.
- API keys, raw transcript text, correction prompts, replacement rules, and
  provider responses must not appear in default logs.
- Normal tests must use fakes or fixtures and must not call the live OpenAI
  API.
- User replacement rules must be literal text replacements, not executable
  scripts.

## Runtime Correction Request

`TextCorrectionRequest` is the transient containing-app input to the optional
correction and local post-processing pipeline. It contains exactly one
validated `AcceptedTranscript`, one `TextCorrectionConfiguration`, and one
`TranscriptPostProcessingConfiguration`. The normal path projects it from the
attempt's captured settings snapshot; an explicit failed-attempt Retry projects
fresh current settings once and keeps that snapshot for the retry.

The OpenAI adapter receives only the accepted transcript and correction
configuration. `OpenAICredential` remains a separate transient argument.
Emoji-command configuration and user replacement rules are local pipeline
inputs and never enter the correction provider request. When remote correction
is disabled, the request still runs local cleanup, emoji commands, and ordered
literal replacements without contacting the provider.

The request is runtime-only, `Equatable`, `Sendable`, and non-Codable. It has no
session, attempt, history, document, or target identity; output intent;
timestamp; recovery policy; provider response; platform result; or user-facing
copy. It is not persisted, logged, placed in App Group, sent to the keyboard,
or used as a durable correction journal. Provider transport, timeout, and real
cancellation remain platform-adapter concerns.

## Edge cases and failure policy

- Missing API key blocks OpenAI correction but must not discard the successful
  transcription result.
- Invalid API key, rate limit, network failure, provider failure, timeout, or
  unreadable response should skip OpenAI correction and keep the transcription
  result.
- Explicit cancellation follows the same correction-pipeline fail-open rule:
  the provider adapter reports cancellation, while the correction wrapper keeps
  the already accepted transcription unless the containing session itself has
  been cancelled.
- Empty correction output should be ignored.
- Correction output that is much longer or much shorter than the transcript may
  be treated as unsafe and ignored.
- If local cleanup turns a non-empty transcript into empty text, the app should
  keep the pre-cleanup transcript.
- User replacement rules run in the configured order, so later rules may see
  text changed by earlier rules.
- If multiple replacement rules search for the same text, each enabled rule is
  still applied in order.
- Replacement rule matching ignores source-text capitalization, so one rule can
  replace uppercase, lowercase, and mixed-case instances.
- Empty Replacement removes each literal match. If the complete processed value
  becomes empty or whitespace-only, accepted-transcript normalization retains
  the previous non-empty fallback; otherwise that normalization trims only the
  final accepted value's outer whitespace and newlines.

## Route / state / data implications

On macOS, the compatibility facade may continue to store these values in its
existing `UserDefaults` keys:

- whether OpenAI correction is enabled
- selected correction model
- correction prompt text, defaulting to the standard minimal-correction prompt
- whether local plain-typography cleanup is enabled
- ordered literal replacement rules

On iOS, correction enablement, model, prompt, and local-cleanup preference live
in the app-private general settings repository. Ordered
`TextReplacementRule` values live in the app-private Library v1 repository.
Neither repository uses `UserDefaults` or the App Group.

The Replacements destination may read and update the local-cleanup preference
through the process-owned Settings state owner while it reads and updates
custom rules through the process-owned Library state owner. These remain two
independent records: a cleanup-toggle save failure must not hide, disable, or
rewrite durable custom rules, and a Library save failure must not roll back the
cleanup preference.

Library persistence preserves replacement-rule identifiers, enabled state,
search and replacement strings, duplicates, and array order. It does not trim,
case-fold, deduplicate, reorder, or silently remove an empty-search row. Empty
or whitespace-only search is ignored only when the local replacement pipeline
executes.
Edit/delete use the UUID plus the expected full row, enablement uses the UUID
plus its expected prior Boolean, and reorder uses expected and requested full
UUID sequences. A stale or missing target never recreates or mutates another
row; concurrent sequence changes conflict without writing.

Keychain still stores only the OpenAI API key.

OpenAI correction uses the same Keychain API key as transcription but is a
separate request from the audio transcription request.

Usage estimates for audio transcription remain governed by
`openai-transcription.md`; text-correction token accounting requires a future
usage-estimate spec before the Billing section may claim correction costs.

## Verification mapping

- App settings tests should cover defaults, prompt reset, persistence, ignored
  empty/whitespace-only Search rules, and resolved correction model fallback.
- Local cleanup tests should cover dash normalization, quote normalization,
  ellipsis normalization, non-breaking space normalization, ordered
  case-insensitive replacement rules, and empty-output fallback.
- OpenAI correction service tests should cover request construction, output
  parsing, timeout mapping with transport cancellation, explicit cancellation,
  bounded completion with a non-cooperative loader, late-response rejection,
  independent next requests, provider error mapping, and no live API calls.
- Runtime request tests should cover exact value preservation, all enabled and
  disabled configuration paths, `Sendable`, and the absence of a Codable
  transport contract through a normal consumer-module import.
- Controller tests should cover correction disabled, local cleanup enabled,
  OpenAI correction success, and OpenAI correction failure preserving the raw
  transcript.
- Settings presentation tests should cover the Text Correction navigation item
  and section.

## Unknowns requiring confirmation

- Whether local plain-typography cleanup should remain default-on after
  real-world dictation testing.
- Whether correction usage should appear in the Billing estimate.
- Whether future presets should expose style modes beyond minimal correction.
