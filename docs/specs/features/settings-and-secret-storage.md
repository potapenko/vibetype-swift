# Settings And Secret Storage

## Goal

Define the first settings and secret-storage contract for HoldType.

The app needs simple local settings for dictation behavior while keeping the
OpenAI API key out of plain text settings and logs.

## Platform boundary

This document is the macOS Settings and persistence contract. Its
`UserDefaults`, macOS Keychain, Finder, Login Item, and Sparkle clauses remain
unchanged for the macOS compatibility facade. iOS reuses the shared domain
behavior and documented defaults, but its canonical UI and persistence
ownership are governed by `ios-settings-and-secret-storage.md`; iOS does not
inherit or write these macOS `UserDefaults` keys.

## Scope

This spec covers:

- settings visible in the Settings window
- UserDefaults-backed non-secret settings
- Keychain-backed OpenAI API key
- automatic insertion, app clipboard, recording, stop-tail, and indicator controls
- recording cache retention, size display, Finder reveal, and clear actions
- transcript recovery history toggle and clear action, including recoverable
  failed transcription attempts
- prompt and custom dictionary settings
- built-in and custom voice emoji command settings inside Dictionary
- text correction settings
- configurable OpenAI translation shortcut settings
- local OpenAI usage estimates and projected API cost
- local diagnostics and crash-report discovery/export
- software update preferences

## Non-goals

- account management
- cloud sync
- team policy management
- full hotkey customization UI
- provider marketplaces, local model downloads, self-hosted transcription
  endpoints, or multi-provider settings beyond the OpenAI MVP
- microphone input device selection
- account usage dashboards, telemetry, cloud billing sync, or cloud-backup
  controls
- cloud, account-backed, or always-on raw-audio archives
- secure enclave or enterprise secrets management
- cloud dictionary sync
- automatic learning from corrections in other apps
- automatic crash upload, analytics, telemetry, or account-backed support
- deleting, moving, or rewriting macOS system crash reports

## User-visible behavior

- Before concrete settings fields exist, Settings may open a native placeholder
  window titled for HoldType settings. The placeholder must not show fake or
  nonfunctional form controls.
- The Settings window should use sidebar navigation once it contains multiple
  settings groups. The sidebar should put Permissions first and provide stable
  entries for Permissions, API key, Billing, Transcription, Text Correction,
  Translation, Dictionary, Shortcut, Behavior, Recording Cache, Updates, and
  Diagnostics, with the selected entry shown in the detail pane.
- The Settings window title should identify both the app and the current
  section using the format `HoldType: <section title>`, such as
  `HoldType: Permissions` or `HoldType: Recording Cache`.
- Switching Settings sidebar sections should update the window title without
  reopening the window. Menu bar entry labels may remain shorter, such as
  `Settings…`.
- Permissions should be the default selected Settings section when no explicit
  Settings target is requested. Settings should not include a separate General
  section that duplicates permission status or compact setup protocols.
- The Settings window should include OpenAI API Key.
- The OpenAI section should explain in plain language that an API key lets
  HoldType send recordings to OpenAI for transcription through the user's
  OpenAI Platform account.
- The OpenAI section should provide a compact setup guide with links to OpenAI
  API keys, API billing, and API key safety guidance.
- The setup guide should make clear that API billing is separate from ChatGPT
  subscriptions. If the guide mentions a minimum prepaid credit amount, it
  should frame that as current OpenAI billing guidance rather than a HoldType
  price or in-app purchase.
- The OpenAI API key should be saved locally in macOS Keychain.
- HoldType may keep the readable API key in memory for the current app process
  after an explicit user-initiated credential resolution or after the user
  changes the key. Keychain remains the persistent store; the in-memory value
  is only a runtime credential cache.
- HoldType must not read Keychain at app launch just to warm the runtime
  credential cache.
- HoldType should store the OpenAI API key in one stable Keychain item. Replacing
  the key should update that item instead of creating a new Keychain item.
- When a saved API key exists, Settings should show that HoldType is configured
  without revealing or unnecessarily reading the full saved key. The key input
  acts as a replacement field, but its empty saved-key state should still show a
  non-secret masked value so the field does not look unset after app restart.
- Entering or pasting a non-empty OpenAI API key should save it to Keychain
  automatically. The OpenAI section should not require a separate Save API Key
  button.
- The API key input row should expose an adjacent icon-only paste control that
  reads plain text from the macOS clipboard into the API key input and follows
  the same automatic Keychain save behavior. If the clipboard has no non-empty
  plain text, the control should leave the current input unchanged.
- The full saved key must not appear as plain visible text in Settings.
- A saved API key may be replaced by entering a new key, and the user may
  remove the saved key from Settings.
- The Settings window should include a required permission status surface for
  microphone permission, Accessibility permission when enabled behavior needs
  it, and Input Monitoring for global hotkeys.
- The required permission status surface must not mention the OpenAI API key or
  use saved-key presence or Keychain readability as a permission state.
- The Settings window should include a Billing section for local OpenAI usage
  estimates.
- Billing must be described as an estimate from this Mac's successful local
  transcriptions, not the user's actual OpenAI invoice, balance, or account
  usage dashboard.
- Billing should show today's estimated usage, recent average usage per day,
  the recent 30-day total, and a projected 30-day cost based on the recent
  local daily average.
- Billing should show a compact daily chart for recent local usage, with a
  user-selectable view for estimated cost or audio minutes.
- If the selected transcription model has known local pricing, Billing may show
  estimated USD. If a model is unknown, Billing must still show minutes and
  explicitly mark cost as unavailable or partial instead of inventing a price.
- Billing may include a local Reset Usage Estimate action. Resetting usage must
  not remove the API key, app settings, transcript history, raw audio, or
  external OpenAI account data.
- The Settings window should include transcription model.
- The Settings window should include language setting with Auto, common preset
  language codes, and Custom.
- Transcription model, language, and prompt settings apply to the OpenAI
  file-transcription MVP only. Settings should not expose local model
  downloads, provider tabs, self-hosted endpoints, or account-backed
  transcription modes unless a future spec changes scope.
- Technical text inputs in Settings, including API keys, model names, language
  codes, dictionary entries, replacement rules, and OpenAI prompt instruction
  fields, should render with leading alignment and left-to-right text direction
  regardless of the system locale or the current field contents.
- OpenAI prompt instruction fields should fill the available Settings content
  width. Header actions such as Reset should not consume textarea width, and
  prompt fields should have a visible vertical gap below their header row.
- The Settings window should include hotkey display.
- The hotkey row is read-only for MVP and shows the active shortcut,
  activation mode, and unavailable/fallback status when known.
- The Settings window should include an Insert transcripts automatically
  toggle.
- Insert transcripts automatically controls whether accepted transcripts are
  inserted into the active app after transcription succeeds.
- The Settings window should include a Keep last result toggle.
- Keep last result controls the app-owned recovery slot used by
  `Control+Command+V` and Paste Last Result. It must not copy transcripts to the
  macOS system clipboard and must not disable automatic insertion.
- The Settings window should include toggles for short dictation start/stop
  sounds and the floating recording indicator.
- The Settings window should include a Behavior control for `Recording tail
  after release`.
- `Recording tail after release` lets the user choose how long HoldType keeps
  recording after a stop action before finalizing the audio file. The choices
  should be Off, 0.5 seconds, 1.0 second, 1.5 seconds, and 2.0 seconds.
- The default recording tail is Off. Off stops recording immediately.
- The recording tail is a fixed post-release delay. It must not perform silence
  detection, speech analysis, or automatic endpoint detection.
- The Settings window should include a `Start HoldType at login` control in
  Behavior and duplicate the same control in Permissions availability setup.
  This control lets the user ask macOS to launch HoldType when the user logs in
  so global dictation shortcuts are available after restart.
- `Start HoldType at login` is off by default and must require explicit user
  action before HoldType registers itself as a Login Item.
- The `Start HoldType at login` control should reflect the current macOS Login
  Item state. If macOS reports that user approval is still required, Settings
  should show a clear approval-needed state and provide a way to review that
  existing request in System Settings > General > Login Items.
- Dictation sounds should be short, non-verbal cues. The start cue should make
  recording start noticeable without requiring the user to watch the screen.
- The Settings window should include a dedicated Recording Cache section.
- Recording Cache should expose a top-level `Keep completed recordings` toggle.
  This setting is off by default, which deletes completed recordings after each
  attempt finishes.
- When `Keep completed recordings` is off, the cache retention controls and
  recording list are disabled or replaced by an off-state message. Existing
  app-owned cached files, if any, may still be cleared from this section.
- When recording cache retention is enabled, Settings should let the user choose
  between keeping the last N recordings and unlimited retention. The default N
  is 10.
- Recording Cache must show current cache size on disk and the number of
  app-owned cached recording files.
- Recording Cache should list cached recordings with file name, date, and file
  size, and provide per-recording Reveal in Finder and Delete actions.
- When Recording Cache is enabled, Transcript History may show Play for accepted
  transcript rows whose app-owned cached recording files still exist.
- Recording Cache should refresh after completed recording cleanup or retention
  changes so the list reflects newly kept or deleted recordings without
  requiring a Settings window reopen.
- Recording Cache should provide Reveal Cache in Finder and Clear Cache actions.
- Deleting or clearing cache must affect only app-owned recording cache files.
  It must not remove API keys, settings, transcripts, usage estimates, or
  unrelated files.
- The Settings window should include a Keep Transcript Recovery History toggle
  and a Clear Transcript History action once the recovery history surface is
  implemented.
- Keep Transcript Recovery History controls session-only recovery entries. When
  turned off, it immediately clears current recovery entries and stops future
  history writes until it is turned back on.
- Recovery entries include accepted transcript rows and bounded recoverable
  failed transcription attempts. Clearing or disabling recovery history also
  removes temporary failed-attempt retry audio, but does not clear the normal
  recording cache, API key, usage estimates, or settings.
- The Settings window should include an optional prompt field for transcription
  guidance.
- The Settings window should include a Use Nearby Text Context toggle for the
  OpenAI transcription prompt. It is off by default.
- When Use Nearby Text Context is enabled, HoldType may read a bounded excerpt
  from the active editable text field through Accessibility and send that
  excerpt to OpenAI as prompt context for the current transcription only.
- The Settings window should include a dedicated Dictionary section where the
  user can manually add and remove local words or phrases that should be
  recognized with exact spelling when spoken.
- The Dictionary add field should be a single-line input. Pressing Enter in
  the field should add the current word or phrase, clear the input, and keep
  focus in that input so the user can quickly enter another dictionary item.
- The Dictionary section should include built-in emoji command controls. Emoji
  commands should be presented as a small Dictionary feature, not as a separate
  Settings navigation item.
- Emoji command settings and behavior are governed by
  `voice-emoji-commands.md`.
- The Settings window should include a dedicated Text Correction section for
  optional post-transcription cleanup.
- OpenAI text correction must be off by default because it consumes additional
  OpenAI resources after transcription.
- Local plain-typography cleanup may be on by default because it does not make
  remote requests.
- Text correction settings and behavior are governed by `text-correction.md`.
- The Settings window should include a dedicated Translation section for the
  default-enabled `Right Command+Option` translation shortcut.
- The Translation section should include source behavior, target language,
  translation model, and an editable translation prompt with a Reset action.
- Translation source behavior should default to Same as Transcription. This
  means translation normally uses the transcript produced by the Transcription
  settings instead of maintaining a separate default source language.
- Translation source behavior may expose an advanced source-language override
  with common preset language codes plus Custom.
- Translation target language should start unconfigured on new installs and
  should include common preset language codes plus Custom.
- The Shortcut area may still display that `Right Command+Option` is the
  translation shortcut, but detailed translation configuration belongs in the
  Translation section.
- Translation shortcut settings and behavior are governed by
  `post-transcription-actions.md`.
- Missing API key should be reported as a user-visible blocked state before
  transcription is attempted.
- Missing API key should not open the Permissions section. Missing-key recovery
  belongs to the full OpenAI Settings surface.
- On launch, OpenAI setup in Settings should not read Keychain or block startup.
  Required permission setup remains the only automatic launch setup surface.
- When OpenAI setup needs attention after a user action that requires a
  credential, the app should open the full Settings window focused on OpenAI.
  The OpenAI section should show a warning banner above the Settings content
  explaining that transcription needs an API key.
- The OpenAI Settings surface should use the same Keychain save, replace, and
  remove behavior in automatic setup recovery and manual Settings navigation. It
  should show the process-local credential-cache state without revealing or
  passively reading the full saved key.
- When HoldType needs to confirm that the saved key is usable for dictation, it
  should first use the process-local runtime credential cache. If that cache is
  empty during an explicit recording start or provider action, HoldType may make
  one lazy non-interactive credential read, cache the result for the current
  process, and continue only when a key is available. If the credential cannot
  be resolved, recording should stay blocked before microphone capture starts
  and Settings should focus the OpenAI setup surface.
- If a completed recording later fails during transcription because OpenAI
  rejects the runtime credential, the app must not automatically open Settings.
  It should show a menu bar recovery prompt with an explicit Open OpenAI
  Settings action.
- Recording-start and failed-attempt retry flows must use one resolved runtime
  credential gate before any OpenAI upload. Transcription, correction, and
  translation request services receive the already-resolved credential for that
  session and must not read Keychain or any developer key source themselves.
- `Invalid API key` means OpenAI returned a credential rejection for a request
  sent with a resolved non-empty runtime credential. Missing, unreadable,
  locked, or not-yet-authorized Keychain state must be reported as missing or
  unavailable credential state before upload, not as an invalid provider key.
- macOS Keychain authentication prompts must not appear during recording,
  key-release handling, transcription, correction, translation, launch setup,
  permission refresh, or passive OpenAI Settings viewing and refresh.
- The OpenAI Settings surface must not expose a Keychain authorization action.
  If a saved Keychain item cannot be read without system authentication UI,
  HoldType should report the API key as unavailable and ask the user to paste
  the key again.
- A macOS Keychain authentication prompt is acceptable only as a direct result
  of the user saving or replacing the OpenAI API key from Settings. After the
  user grants persistent access for a stable signed app, later launches should
  read the same stable item without prompting.
- Automated XCTest, UI test, and repository runtime QA launches must never open
  the macOS Keychain authentication dialog. HoldType may select a
  non-interactive Keychain policy from XCTest-injected environment. Explicit
  repository automation environment such as `HOLDTYPE_AUTOMATION=1` must avoid
  live Keychain access entirely; `HOLDTYPE_KEYCHAIN_AUTHENTICATION_UI=skip` may
  be used only as a narrower non-interactive Keychain policy. These policies
  must not be applied automatically to a normal Xcode Run launch or to an
  installed app.
- Debug builds may support an explicit local developer key-file source for
  live manual debugging. This source must require an opt-in environment setting,
  must be ignored in Release builds, must be ignored when
  `HOLDTYPE_AUTOMATION=1`, must read lazily only when a credential is needed,
  and must not write API keys back to the file.
- Saving, replacing, or deleting the OpenAI API key in Settings should update
  the in-memory runtime credential immediately, without requiring an app
  restart.
- Transcription failure handling outside Settings must not save, replace,
  delete, clear, or rewrite the OpenAI API key. The only recovery behavior it
  owns is showing the error and offering explicit navigation or retry actions.
- Closing Settings during OpenAI setup defers the visible OpenAI setup surface
  for the current app run; it does not save, remove, or validate an API key and
  does not let recording proceed without a saved key.
- Settings should include a Permissions section that shows microphone,
  Accessibility, and Input Monitoring status and provides the next action for
  blocked permission items.
- When the Permissions section is visible, Settings should keep microphone,
  Accessibility, and Input Monitoring status current through lightweight
  polling and refresh the visible statuses again when HoldType becomes active
  or the Settings window becomes the focused/key window again.
- Settings changes that affect required setup, such as automatic insertion or
  nearby text context, should immediately refresh permission statuses and the
  setup warning instead of waiting for the next polling tick.
- Secure storage access should not be refreshed from the Permissions section.
  Keychain readiness belongs to the OpenAI Settings surface and the runtime
  credential cache.
- Settings should include a dedicated Diagnostics section for local crash-report
  discovery and support bundle export. Diagnostics behavior is governed by
  `diagnostics-and-crash-reports.md`.
- Settings should include an Updates section for current app version display
  and update preference controls. Software update behavior is governed by
  `software-updates.md`.
- Diagnostics should show a compact recent runtime-events view when app-owned
  runtime logs exist, with actions to copy recent events, reveal the runtime-log
  directory, refresh diagnostics, and export the full diagnostic bundle.
- Runtime-log viewing and copying must use the same redacted, bounded
  app-owned diagnostics defined by `diagnostics-and-crash-reports.md`; Settings
  must not expose raw transcripts, prompts, API keys, provider payloads, or raw
  audio through Diagnostics.

## Default settings

The MVP non-secret settings default to:

- transcription model: `gpt-4o-transcribe`
- language: Auto
- custom language code: empty
- prompt: empty
- custom dictionary: empty
- emoji commands: on
- enabled emoji command sets: English
- use nearby text context: off
- OpenAI text correction: off
- text correction model: `gpt-5.5`
- text correction prompt: standard minimal-correction prompt
- local plain-typography cleanup: on
- user text replacement rules: empty
- translation shortcut: on
- translation source behavior: Same as Transcription
- translation source language override: unconfigured
- translation target language: unconfigured
- translation model: `gpt-5.4-mini`
- translation prompt: standard translation prompt
- insert transcripts automatically: on
- keep last result: on
- dictation start/stop sounds: on
- floating recording indicator: on
- recording tail after release: off
- start HoldType at login: off
- keep transcript recovery history: on
- do not keep recording cache: on
- recording cache retention count when enabled: 10
- automatic update checks: on
- automatic update downloads: off

Existing installs that carry a legacy saved off value for transcript recovery
history should migrate once to the current on-by-default behavior. After that
migration, the user's explicit Settings toggle choice persists normally.

The OpenAI API key has no UserDefaults value or default. It is Keychain-only.

## Invariants

- API key must not be stored in UserDefaults.
- API key must not be logged.
- OpenAI transcription, correction, and translation requests should use the
  runtime credential cache instead of reading Keychain on every request.
- OpenAI transcription, correction, and translation request services must not
  resolve credentials as a side effect. They may only use a credential resolved
  by recording-start preflight, failed-attempt retry preflight, or an explicit
  user Settings save/replace action.
- If the runtime credential cache is empty, recording must be blocked before
  microphone capture starts unless a lazy user-initiated credential resolution
  succeeds first.
- Recording setup checks, key-release handling, and permission refreshes must
  not read Keychain as a side effect. The explicit recording-start preflight is
  the allowed lazy credential-resolution point.
- Keychain reads and status checks must be non-interactive. If macOS would
  require Keychain authentication UI for a read, the app must show an in-app
  unavailable-key state instead of the system password dialog.
- Keychain saves and replacements happen only from the OpenAI Settings surface
  after explicit user input. They should update the same stable item so a
  previously granted persistent Keychain access decision remains applicable.
- In automated XCTest, UI test, and repository runtime QA execution, Keychain
  saves and replacements must not open system authentication UI. In explicit
  repository automation launches, HoldType should not read, save, replace, or
  delete live Keychain items at all; the operation should behave as missing or
  fail in-app/test instead of opening the system dialog. Automation must also
  ignore any configured debug key-file source.
- Prompt text, nearby active-text context, custom dictionary entries,
  correction prompts, replacement rules, transcript text, and raw audio must
  not be stored in usage estimate records or logged by default.
- Settings should be local-only for the MVP.
- No account, subscription, telemetry, or server-side billing setting should
  appear in the MVP.
- Usage estimates must be local-only and must not call live OpenAI billing,
  usage, or balance APIs during normal app use or automated tests.
- Settings changes should not require a manual external setup step after the app
  is built and launched.
- Unsupported reference settings such as accounts, analytics, cloud backup,
  system audio capture, local model management, and raw-audio retention should
  not appear in the MVP settings surface.
- Diagnostics must not add automatic telemetry, analytics, cloud upload, or
  account-backed support to the MVP settings surface.
- Diagnostics runtime-log actions must remain local user actions. They must not
  upload, email, or otherwise transmit diagnostic bundles or logs automatically.
- Update settings must remain local-only and must not introduce accounts,
  telemetry, or a custom backend.

## Edge cases and failure policy

- If Keychain save fails, the app should show a visible error and not pretend
  the key was saved.
- If the runtime credential cache cannot be populated from Keychain at launch or
  after an explicit Settings action, the app should show OpenAI setup before
  recording begins instead of starting capture and failing during transcription.
- If an older Keychain item was saved under a stale local debug signing
  identity, HoldType should not try to authorize or migrate that item through a
  system password prompt. The recovery path is to save a new key from the
  OpenAI Settings surface.
- If a previous HoldType build stored API keys under per-save Keychain item
  identifiers, HoldType may ignore those legacy items rather than reading them
  during startup. The recovery path is to save the current key again, creating
  the stable item used by current builds.
- If the runtime credential becomes unavailable before transcription, the app
  should show missing or inaccessible API key instead of making an
  unauthenticated request.
- If the Custom language field is empty, the app should fall back to Auto. If
  the field is non-empty and not a two- or three-letter language code, Settings
  should show a clear validation error.
- If model is empty, the app should use the configured default model or show a
  setup-needed state.
- Custom dictionary entries should trim surrounding whitespace, ignore empty
  entries, and remove duplicates case-insensitively while preserving the first
  spelling the user entered.
- If nearby text context is enabled but Accessibility is not trusted or the
  active field cannot be read safely, transcription should proceed without that
  context.
- If no usage has been recorded, Billing should show an empty state rather than
  fake chart data.
- If usage estimate storage cannot be read, Billing should show a clear local
  estimate error without blocking dictation or key management.
- A failed or canceled transcription should not create a successful local usage
  estimate record.
- If OpenAI correction fails after a successful transcription, Settings should
  not imply that transcription failed. The optional correction stage should be
  skipped and the transcript should remain usable.
- If Diagnostics cannot read crash reports, Settings should show a local
  diagnostics error without blocking other settings sections.

## Route / state / data implications

UserDefaults may store:

- selected model
- language
- automaticallyInsertTranscripts
- saveTranscriptsToAppClipboard
- soundEnabled
- showFloatingIndicator
- recording stop tail duration
- saveTranscriptHistory
- recording cache retention policy
- prompt
- custom dictionary entries
- emoji command enabled state and enabled command sets
- use nearby text context
- text correction enabled
- text correction model
- text correction prompt
- local plain-typography cleanup enabled
- literal text replacement rules
- translation shortcut enabled
- translation source behavior
- translation source language override
- custom translation source language code
- translation target language
- custom translation target language code
- translation model
- translation prompt
- JSON-encoded local OpenAI usage estimate records

Keychain stores:

- OpenAI API key

A local debug key file may contain an OpenAI API key only for explicit Debug
developer launches. It is not a production persistence store, must be gitignored,
and must not be used by normal automated verification.

Local OpenAI usage estimate records may store:

- timestamp
- transcription model
- audio duration in seconds
- known price per minute when available
- estimated cost when available
- local pricing source label

Transcript recovery history retention, failed-attempt retry audio, and clearing
behavior are governed by `transcript-history.md`.

Recording cache entries are app-owned local audio files. Settings may show their
metadata and disk usage, but UserDefaults should store only the cache retention
policy, not per-file metadata.

The selected Settings sidebar entry is window-local UI state. Changing the
selected entry must not start, stop, cancel, or otherwise affect dictation.

## Verification mapping

- Add tests or manual QA for saving/loading settings, saving/loading/deleting
  API key, missing key errors, local usage price calculation, projection math,
  unknown-model cost handling, recording cache listing/clear/retention, reset
  behavior, and ensuring logs do not contain the API key when implementation
  exists.

## Unknowns requiring confirmation

- Whether settings need import/export.
- Whether the language Custom field is free text or a constrained code.
