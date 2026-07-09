# Privacy And Permissions

## Goal

Define the first privacy and permission contract for a microphone-based text
input app.

HoldType handles spoken work content and sends audio to OpenAI for
transcription, so the product must make microphone capture, remote processing,
Keychain storage, and any transcript persistence explicit.

## Scope

This spec covers:

- microphone consent
- Accessibility consent for active-app paste automation
- Input Monitoring consent when native global-hotkey listening requires it
- recording visibility
- OpenAI remote-service disclosure
- local persistence defaults
- debug logging boundaries
- local diagnostics and crash-report handling boundaries
- user content handling before a dedicated storage spec exists

## Non-goals

- legal privacy-policy wording
- account, billing, or team administration
- concrete encryption implementation details
- provider-specific API contracts
- microphone device selection or system-audio capture settings
- account-backed or cloud-synced raw-audio retention controls
- automatic crash upload, analytics, or account-backed diagnostic support

## User-visible behavior

- The app must request microphone permission through the platform's normal
  permission flow before recording.
- The app must explain Accessibility permission when automatic insertion or
  Paste Last Result requires keyboard event simulation or control of the
  active app.
- The app must explain Input Monitoring permission when the native global
  hotkey implementation listens for key presses outside HoldType.
- The app must not imply that recording is active unless microphone capture has
  actually started.
- The product must disclose that audio is sent to OpenAI when OpenAI
  transcription is used.
- Settings must include a concise OpenAI audio-processing disclosure near the
  relevant transcription or permissions controls.
- If the user enables nearby text context, the product must disclose that a
  short excerpt from the active editable text field may also be sent to OpenAI
  with the recording to improve continuation quality.
- If the user enables OpenAI text correction, the product must disclose that
  the transcript text may be sent to OpenAI in a second request after audio
  transcription.
- When the translation shortcut is enabled, the product must disclose that the
  post-correction transcript text may be sent to OpenAI in a separate
  translation request before output delivery.
- Local plain-typography cleanup and literal replacement rules must run locally
  and must not send text to a remote service by themselves.
- API keys must be stored locally in macOS Keychain, not in UserDefaults or
  plain text files. The only plain-text exception is an explicit gitignored
  Debug developer key-file source for manual live debugging; Release builds and
  automated verification must ignore that source.
- Keychain readiness is part of OpenAI setup, not a separate system permission.
  Permission surfaces must not ask users to authorize Keychain access as though
  it were a macOS privacy permission.
- The MVP must not require accounts, subscriptions, telemetry, analytics,
  server-side state, or cloud sync.
- The default product contract is no retained audio. When recording cache
  retention is off, completed audio files are deleted after each attempt
  finishes.
- Recoverable failed transcription attempts may keep bounded session-only audio
  for explicit retry when transcript recovery history is enabled. This is not
  durable recording cache retention and must be cleared when the attempt
  succeeds, is deleted, history is cleared, history is turned off, or the app
  quits.
- Settings may let the user explicitly keep local recording cache files for
  Finder-based recovery or export. This cache is local-only, app-owned raw
  audio, not transcript history.
- When recording cache retention is enabled, Transcript History may offer local
  playback for accepted transcript rows whose app-owned cached recording files
  still exist. This playback must not upload audio, retranscribe audio, or log
  cached file paths.
- Recording cache retention defaults to a bounded "keep last 10 recordings"
  policy when enabled. Unlimited retention is allowed only as an explicit user
  choice and must be paired with visible cache size and clear controls.
- Transcript recovery history is session-only, local-only, enabled by default,
  and governed by `transcript-history.md`.
- Nearby text context is current-request-only. It must not be written to
  transcript history, UserDefaults, local files, debug payloads, or default
  logs.
- OpenAI text correction input and output are current-request-only unless the
  final corrected transcript is later saved by Last Transcript, HoldType
  Clipboard, or recovery history under their own specs.
- OpenAI translation input and output are current-request-only unless the final
  translated transcript is later saved by Last Transcript, Last Result,
  or recovery history under their own specs.
- Debug logging must not include raw dictated text, raw audio payloads, tokens,
  credentials, or full provider responses in the default product log stream.
- Local diagnostics may reveal or export HoldType crash reports only after an
  explicit user action. Diagnostics must not automatically upload crash reports
  or collect broad system logs.
- Local runtime diagnostics may keep bounded app-owned log lines in the user's
  Library cache hierarchy. These logs must contain only compact lifecycle events
  and operator categories, not dictated content, prompts, nearby text context,
  custom dictionary entries, API keys, authorization headers, raw audio, raw
  provider payloads, or full provider responses.
- If a user denies microphone permission, the app should remain usable enough
  to explain what is blocked and how to retry.
- On launch, if any required permission is missing, denied, or unavailable, the
  app should open the full Settings window focused on Permissions and show a
  warning banner above the Settings content explaining that required setup is
  incomplete. It must not start recording or show a system permission prompt
  automatically.
- Closing the Settings window during setup defers that visible setup surface for
  the current app run only. It must not grant permission, start recording, hide
  permission status from Settings, or bypass recording setup checks.
- Deferring required permission setup must not advance into OpenAI API key setup
  while required permissions still need attention. OpenAI setup remains deferred
  until required permission setup is complete.
- The app may show the full Settings window focused on Permissions again after
  an explicit user action that depends on required setup, such as starting
  recording. The microphone system permission prompt must still appear only
  after the user chooses the microphone request action.
- On launch, OpenAI API key setup must not read Keychain or open OpenAI Settings
  automatically. If any required permission still needs attention, the app must
  show Settings focused on Permissions and defer API key setup.
- After required permissions are complete, OpenAI setup is evaluated by the
  first explicit user action that needs a credential, such as starting
  recording. Missing or unavailable key state should then open the full Settings
  window focused on OpenAI with a warning banner explaining that transcription
  needs an API key.
- A saved OpenAI API key is considered ready for recording only after HoldType
  has loaded it into the current process without showing macOS Keychain
  authentication UI. If the runtime credential cache is empty when recording is
  requested, HoldType may lazily resolve the credential once; if that resolution
  fails or finds no key, recording must open OpenAI setup before microphone
  capture starts.
- Closing Settings during OpenAI setup defers the visible OpenAI setup surface
  for the current app run only. It must not create, remove, validate, or assume
  an API key.
- A recording start attempt must re-check required setup. If recording is
  blocked by missing microphone permission or missing Accessibility permission
  for enabled output/context behavior, the app must open Settings focused on
  Permissions and remain out of the recording state.
- A recording start attempt must check saved OpenAI API key availability only
  after permission blockers are resolved. Missing, unavailable, or
  not-yet-authorized API key setup must block recording before microphone
  capture starts and open Settings focused on OpenAI, not Permissions.
- The menu bar must not render a separate permission status or recovery block.
  If recording cannot start because required permission setup is incomplete, the
  recording action must keep recording inactive and open Settings focused on
  Permissions.
- Permissions settings should show microphone, Accessibility, and Input
  Monitoring status using product language and provide a bounded next action
  such as requesting permission or opening the relevant System Settings pane.
- Launch at login is system-managed availability setup, not a TCC privacy
  permission. It must not appear as a required permission, must not block
  recording, and must not be included in required setup warning banners.
- Permissions settings may show launch-at-login as a recommended availability
  item with the same `Start HoldType at login` control shown in Behavior. If
  HoldType already requested launch at login but macOS still needs approval,
  Permissions may also provide the approval action. Global dictation shortcuts
  work only while HoldType is running.
- Input Monitoring is an optional global-shortcut capability unless an enabled
  production hotkey path requires it. Missing Input Monitoring must not by
  itself open Settings as a required startup setup surface.
- The Accessibility next action must actively request macOS Accessibility trust
  before or alongside opening System Settings. It must not only deep-link to an
  empty Accessibility list.
- The app identity that macOS Accessibility and Input Monitoring settings show
  to the user must resolve to `HoldType`. The macOS MVP bundle identifier uses
  the HoldType-cased `app.holdtype.HoldType` identity because Accessibility settings
  can fall back to bundle identifier metadata when recreating a removed row.
- The macOS app bundle must include an `NSInputMonitoringUsageDescription`
  purpose string that explains global shortcut monitoring. Missing this key can
  make macOS return failed Input Monitoring requests without creating a System
  Settings row.
- Local debug launches used for permissions QA must keep the running app's TCC
  identity stable across rebuilds. They should use Apple Development signing
  when configured; the ad-hoc fallback must not launch a cdhash-only designated
  requirement because each rebuild would make macOS treat the same visible
  `HoldType` row as a different app and leave Settings status stale.
- Ad-hoc signing with a stable local requirement is only a fallback for local
  iteration. It is not a reliable proof that macOS will create an Input
  Monitoring row; Input Monitoring registration QA needs Apple Development or
  distribution-style signing, or else manual `+` addition remains the fallback.
- Local debug launches used for permissions QA must also use one canonical
  macOS app bundle path for the active checkout. The shared Xcode scheme and
  agent run script should both launch the default Xcode Debug product unless a
  run explicitly opts into an isolated `HOLDTYPE_DERIVED_DATA_PATH`. An isolated
  product path can create a separate System Settings Accessibility row and must
  not be used as evidence that the user-facing Permissions panel is stale.
- If System Settings contains an old `HoldType` Accessibility row for another
  debug product path or stale code requirement, the Permissions panel must keep
  displaying the non-prompting `AXIsProcessTrusted()` result for the running app.
  It must not infer `Allowed` from a visible System Settings toggle that belongs
  to a different app copy. Recovery for that OS state is to remove the stale row,
  request Accessibility access from the running HoldType app, and then enable
  the newly listed row.
- Local debug tooling may provide an explicit Accessibility reset mode for this
  stale-row recovery. It must be opt-in, reset only the `app.holdtype.HoldType`
  Accessibility service entry, launch the canonical Debug app, and have that
  running app request Accessibility trust so System Settings recreates the row
  for the current bundle path.
- The Input Monitoring action must ask macOS to register HoldType for event
  listening before opening the Input Monitoring settings pane. That request
  must use the HID listen-event permission path and a short bounded HID manager
  open probe that registers the running app in Input Monitoring. It should also
  run the CoreGraphics listen-event request, event-tap probe, and AppKit global
  key monitor probe as bounded registration probes.
- Input Monitoring status must be reported from a fresh HID listen-event status
  check after the registration probes. A successful request/probe callback,
  including CoreGraphics success, must not by itself make the Permissions panel
  show Input Monitoring as allowed.
- Permission refreshes, startup setup checks, and debug recovery hooks must
  read or request Input Monitoring before reading Accessibility trust in the
  same app process. A prior Accessibility trust check can prevent the
  HID listen-event request from creating or refreshing the Input Monitoring
  System Settings entry.
- If the user invokes the Input Monitoring action after the current process has
  already read Accessibility trust, the app may launch a fresh one-shot instance
  of the same app bundle to perform the Input Monitoring request before any
  Accessibility checks, then return the user to the Input Monitoring settings
  pane while the main Settings window continues polling.
- That one-shot Input Monitoring instance must not run normal dictation,
  hotkey, clipboard, setup-window, or transcript-cleanup startup/shutdown work;
  it exists only to make the permission request from a fresh process and then
  exit or return control to the main app.
- Before making that request, the one-shot Input Monitoring instance must
  activate as a regular foreground app and wait briefly on the main run loop.
  It must not call the HID listen-event request immediately from a menu-bar or
  background launch state, because macOS may then fail to create the current
  HoldType row in System Settings.
- Local debug tooling may provide an explicit Input Monitoring reset mode for
  stale-row recovery. It must be opt-in, reset only the `app.holdtype.HoldType`
  listen-event service entry, launch the canonical Debug app, and have that
  running app request Input Monitoring so System Settings recreates the row for
  the current bundle path.
- Manual `+` addition is only a fallback if macOS still does not show HoldType
  after the user relaunches the app and retries the Input Monitoring action.
  HoldType may request that macOS create the row for the current app bundle, but
  it must not promise or attempt to force-insert that row if TCC refuses to
  create it. Direct TCC database edits are not a supported product behavior.
- If the user invokes the Input Monitoring action twice without reaching
  `Allowed`, the Permissions panel must escalate the manual fallback copy from
  secondary help text to a visible warning. The warning must clearly say that
  the user may need to click `+` in Input Monitoring, choose the running
  `HoldType.app`, and then enable the toggle. The warning must reset after
  HoldType reads Input Monitoring as `Allowed`.
- The macOS MVP app target must not use App Sandbox while active-app insertion,
  Paste Last Result, or nearby text context depend on Accessibility-gated
  control of other apps. This is also why Mac App Store distribution is not the
  current macOS release target. Re-enabling sandbox requires a replacement
  architecture and proof that the Accessibility request still registers
  HoldType in System Settings.
- When Accessibility is not allowed, the setup surface must explain that the
  user should enable HoldType in Privacy & Security > Accessibility, and if
  HoldType is not listed, use `+` to add the running app before turning it on.
- If HoldType is listed in Accessibility but the app still reports Not Allowed
  after the user turns it on, the setup surface must explain that the visible
  row can belong to an old app copy and that the user should remove the old row,
  request Accessibility access again from the running app, and enable the newly
  listed row.
- After the user invokes the Accessibility action, the setup surface should
  refresh Accessibility status for a bounded period while System Settings is
  open, and it should explain that the user may need to quit and reopen
  HoldType if macOS still reports stale permission state.
- The full Settings Permissions section must follow the same bounded refresh
  behavior after its Accessibility action so the visible status can change from
  Not Allowed to Allowed without closing and reopening Settings.
- When the full Settings Permissions section becomes visible, when HoldType
  becomes active again, or when the Settings window becomes the focused/key
  window again, it must immediately request a fresh permission status snapshot.
  While that section remains visible, it should poll microphone, Accessibility,
  and Input Monitoring status on a lightweight interval so changes in System
  Settings are reflected in either direction.
- Settings changes that affect required setup, such as automatic insertion or
  nearby text context, must immediately recompute the visible permission
  statuses and setup warning from a fresh permission status snapshot.
- Secure storage access must not be part of continuous visible polling,
  Permissions focus refresh, or recording readiness checks. HoldType must not
  present Keychain access as a user-grantable permission.
- Resolving one permission must not dismiss the setup surface while other
  required setup items still need attention. After a system permission prompt
  closes, the visible setup surface should refresh permission status and remain
  available until setup is complete.
- The setup warning banner in Settings should focus on remaining actionable
  permission items. A permission that is already allowed must not be presented
  as though it still needs the user's action.
- Microphone permission state must be represented as one of four product
  states:
  - `allowed`: recording may start after an explicit user action.
  - `denied`: recording is blocked until the user changes system permission.
  - `not determined`: the app may request permission through the platform flow.
  - `unavailable`: recording is blocked because audio input is not available.
- Querying microphone permission must not start recording or create an audio
  file.
- The production microphone request flow should use the platform callback
  rather than polling. Automated verification should use a fake permission
  boundary instead of requiring a real system prompt.
- Accessibility permission state must be represented as one of two product
  states:
  - `trusted`: automatic insertion and Paste Last Result may control the
    active app.
  - `not trusted`: automatic insertion and Paste Last Result must not
    simulate insertion into the active app.
- Querying Accessibility permission must use the non-prompting status check by
  default. The app may provide a separate action to open the Accessibility pane
  in System Settings.
- Input Monitoring permission state must be represented as one of three product
  states:
  - `allowed`: native global hotkey listening may observe the needed key
    events outside HoldType.
  - `denied`: native global hotkey listening may be blocked until the user
    changes system permission.
  - `not determined`: the app may request permission through the platform flow.
- The MVP settings surface must not expose analytics, cloud-backup, local-model
  management, system-audio capture, or persistent raw-audio retention controls
  copied from the reference app.
- The Permissions Settings warning banner must not check, display, or link to
  OpenAI API key setup. Missing-key handling belongs to the OpenAI Settings
  surface.

## Invariants

- No microphone capture without explicit user action and permission.
- No recording start should proceed when required setup for producing usable
  transcription is incomplete.
- No hidden background recording.
- No remote provider other than OpenAI without a product-level decision and
  user-visible disclosure.
- No persistent audio outside the explicit local recording cache setting and
  bounded session-only failed-attempt recovery.
- Recording cache controls must show local disk usage and provide a way to
  clear app-owned cached recordings.
- Default logs must be short, scannable, and free of sensitive dictated content.
- Default logs must not include active-text context captured from other apps.
- Default logs must not include text correction input, output, prompts, custom
  replacement rules, or provider responses.
- Default logs must not include translation input, output, prompts, or provider
  responses.
- API keys must never be logged.
- Keychain authentication prompts must never appear from recording, key-release,
  transcription, correction, translation, launch setup, permission refresh, or
  passive Settings refresh flows. A Keychain prompt is acceptable only
  immediately after the user explicitly saves or replaces the OpenAI API key in
  Settings.
- API key status surfaces must not reveal, log, or persist the key outside
  Keychain, the process-local runtime credential cache, and the explicit Debug
  developer key-file exception. Recording readiness must use the cache or the
  explicit lazy credential-resolution point rather than passive Keychain reads.
- Diagnostic bundles must not include API keys, transcripts, prompts, custom
  dictionary contents, nearby text context, raw audio, provider payloads, or
  full provider responses.
- Diagnostic bundles may include recent app-owned runtime log lines only when
  those lines follow the default redaction rules and are included after an
  explicit user export action.

## Edge cases and failure policy

- If permission is denied or restricted by device policy, the app should show a
  recoverable blocked state instead of repeatedly prompting.
- If Accessibility permission is not trusted, the app should explain that
  automatic insertion and Paste Last Result are blocked and provide a
  way to open the relevant System Settings pane when possible.
- If Accessibility permission is not trusted, transcription itself should remain
  available when other requirements are met. The app must not fall back to the
  macOS system clipboard.
- If Accessibility permission is not trusted, nearby text context must be
  omitted and transcription should continue with the user's normal prompt and
  dictionary settings.
- If OpenAI is unavailable, the app should fail the current
  attempt with a visible error and allow a later retry.
- If debug logging is temporarily enabled for investigation, the developer
  should turn it back off after verification.
- If a crash or interruption happens during recording, the app must not retain
  audio as an undocumented recovery artifact. Any leftover app-owned recording
  files must be visible from recording cache controls or removed by normal
  cleanup.
- If Accessibility permission is denied, automatic insertion and HoldType
  Clipboard paste should show a clear status or error when a visible surface is
  available.
- If Input Monitoring permission is denied, the app should explain that global
  dictation hotkey listening may be blocked and provide a way to open the
  relevant System Settings pane when possible. Menu-driven recording must
  remain available when every required permission is complete.

## Route / state / data implications

- Permission state is part of the product state model and must be visible to
  flows that start recording.
- Accessibility trust state is part of the product state model and must be
  visible to flows that decide whether automatic insertion or HoldType
  Clipboard paste can insert text into the active app or whether nearby text
  context can be read.
- Input Monitoring state is part of the product state model for native global
  hotkey flows that need to listen for keyboard events outside the app.
- Launch-at-login state is part of Settings availability state, but not
  permission-gated recording readiness. It should be read from macOS Login
  Items rather than treated as a UserDefaults-only preference.
- Provider configuration is product behavior because it changes model,
  language, prompt, latency, and error behavior.
- Settings may be stored in UserDefaults, but the API key belongs in Keychain.
- A process-local runtime credential cache may hold the readable API key after
  launch or Settings changes. This cache must not be persisted outside
  Keychain.
- Local storage of audio is limited to the explicit recording cache setting and
  bounded session-only failed-attempt retry audio governed by
  `transcript-history.md`.
- App-owned runtime diagnostic logs are local derived diagnostics governed by
  `diagnostics-and-crash-reports.md`; they are separate from transcript history,
  recording cache audio, and macOS system crash reports.

## Verification mapping

- Add permission-state tests or manual QA for first launch, denied permission,
  permission granted after denial, and unavailable microphone when implementation
  exists.
- Add tests or review checks that default logs do not include raw dictated
  content or nearby active-text context.
- Add tests or review checks that exported runtime diagnostics omit API keys,
  transcript text, prompts, dictionary entries, nearby text context, raw audio,
  provider payloads, and full provider responses.

## Unknowns requiring confirmation

- Whether the app needs a formal onboarding screen before first recording.
- Whether temporary debug audio retention is allowed in debug builds.
- Exact wording and placement for OpenAI audio-processing disclosure.
- Exact wording and placement for nearby active-text context disclosure.
