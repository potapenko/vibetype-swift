# iOS Keyboard Experience

Status: active V1.1 MVP UX contract; revised 2026-07-15 for automatic
keyboard-to-app handoff. `ios-keyboard-handoff-and-delivery.md` wins any
conflict about microphone behavior, launch routing, reconnection, or delivery.

## Goal

Provide a compact HoldType command keyboard whose primary action is voice
dictation. The user taps the keyboard microphone, completes any targeted setup
in HoldType when necessary, speaks, finishes, and receives eligible accepted
text in the active host field.

The extension itself never records audio. The containing app owns microphone
capture, OpenAI processing, text rules, Latest, and History. The keyboard owns
only the controls, one bounded command handoff, transient status, and insertion
through `UITextDocumentProxy`.

## Platform Boundary

- A custom keyboard extension has no microphone access. HoldType does not try
  to bypass that restriction.
- The containing app owns a bounded warm handoff session and processes keyboard
  commands while that session remains available.
- When no healthy session exists, the same keyboard microphone writes a bounded
  intent and opens HoldType. The keyboard contains no manual navigation copy.
- System setup and product settings remain in the containing app. A blocker
  routes to its exact owner; a valid cold request starts capture automatically
  and presents the swipe-back sheet.
- HoldType declares that it supplies dictation before the keyboard view is
  presented, so iOS does not add a duplicate system Dictation button beside the
  HoldType voice control.
- Physical-device evidence must prove that the app-owned background session can
  receive commands reliably and with acceptable privacy, energy, and App Review
  behavior. Simulator success cannot settle this boundary.
- If the device spike requires private APIs, fabricated state, indefinite
  silent audio, or recording user audio outside an explicit listening action,
  keyboard-controlled dictation is a no-go and implementation stops.

## Product Role

- HoldType is selected with Globe when the user wants voice dictation, Latest
  insertion, or compact sentence-editing controls.
- The system keyboard remains the normal alphabetic, numeric, emoji, and
  language-layout keyboard.
- HoldType inserts accepted Unicode text in any transcription language
  supported by the containing app. It has no keyboard-locale promise.
- Canonical History and every History action remain in the containing app. The
  keyboard never renders History rows, transcript previews, or detail.
- The API key, provider client, prompts, Library, Pending audio, canonical
  Latest, and canonical History never enter the extension.

## Brand Stage Adaptive Composition

The keyboard keeps one stable composition in Light and Dark Mode:

1. Top rail: Quick Insert and `Auto` form the leading group. A separate
   44-point History action sits immediately before `Latest` in the trailing
   group. The center remains an unoccupied flexible gap with no logo, label, or
   control. Every neutral key in the rail uses the same surface treatment as
   the editing keys below.
2. Workspace: either the Voice stage or Quick Insert. One toggle tap replaces
   Voice directly with Quick Insert; there is no intermediate launcher, task
   picker, menu, or containing-app transition. The close icon restores the
   exact Voice presentation underneath.
3. Editing row: Globe, wide Space, Delete, and adaptive Return.

The top center stays empty during Ready, Starting, Listening, Processing, and
Quick Insert. No state label appears under or beside it. Ready, unavailable,
listening, starting, processing, and failure information belongs exclusively to
the central voice stage so the interface never repeats the same state in two
places.

The approved Brand Stage reference remains the geometry source of truth. On
iPhone the surface uses approximately 18-point side insets, 8-point editing-key
gaps, an approximately 128-point Voice activity control in regular-height
portrait and an approximately 88-point control in compact-height landscape,
plus one bounded 21-bar waveform on each side of that activity. The waveforms
stay centered with the activity, mirror the approved Brand Stage silhouette,
and adapt their spacing and height without stretching the central artwork. The
editing-key relationship remains close to
`Globe : Space : Delete : Return` of `1 : 4.35 : 1.15 : 1.25` when Return uses
its symbol or a short title. Return has a 56-point default width, expands to
keep the current contextual title on one line, and never wraps. Space yields
width first, down to its 44-point minimum. Only after Space reaches that
minimum may Return use bounded single-line font scaling for a title that still
cannot fit. Every action is at least 44 by 44 points.

Compact-height landscape may use the existing two-column reflow. Wider iPad
layouts keep a centered maximum content width. V1.1 release qualification is
iPhone-first; iPad remains compatibility UI.

The surface has rounded top corners and stays visually distinct from the host
application. The central recording and recognition activity is the keyboard's
only HoldType mark; the top rail contains no duplicate logo. The interface
contains no transcript card, alphabet layout, number deck, Shift, Caps Lock,
`123`, prediction row, or manual Refresh.

## Setup And Recovery Actions

- The keyboard has no permanent Settings action.
- Full product settings and system-setup assistance remain available from the
  containing app.
- The central indicator remains present for Ready and compact operational
  failures. The keyboard never replaces it with written navigation steps.
- A microphone tap opens the exact containing-app setup owner for Full Access,
  microphone, provider, consent, Translation, or another preflight blocker.
- After setup is fixed, the user returns to the host and taps the same
  microphone again. A healthy cold request opens the swipe-back sheet and
  starts app-owned capture automatically.

## Quick Insert And Editing Controls

- The left utility group remains one stable visual unit. Its first control
  shows a smile icon while Voice is visible and a close icon while Quick Insert
  is visible.
- Quick Insert opens and closes in one tap. It never shows a mode chooser or a
  second confirmation step.
- Quick Insert has no visible title or explanatory label; the available keys
  fill the workspace.
- The punctuation row contains `.`, `,`, `?`, `!`, `:`, `;`, `—`, and `…`.
- Two emoji rows contain the bundled set `🙂`, `😂`, `❤️`, `👍`, `🙏`, `🔥`,
  `✅`, `✨`, `😊`, `😍`, `🤔`, `👏`, `💯`, `🎉`, `🚀`, and `👀`. These are fixed
  keyboard-local Unicode values, not copied Apple artwork or user Library data.
- Each selection performs exactly one local `insertText` call and closes Quick
  Insert immediately, restoring the underlying Voice or recovery workspace.
- Rows may scroll horizontally on narrow layouts, but every item keeps at least
  a 44-by-44-point target.
- Compact-height landscape may combine both emoji sets into one horizontally
  scrolling row so punctuation and every emoji remain reachable without making
  the keyboard taller.
- Quick Insert remains available without provider setup, network, microphone
  permission, or Full Access. Opening it may temporarily cover recovery copy;
  closing it restores that copy unchanged.
- Quick Insert remains enabled in Ready, Opening, Starting, Listening,
  Processing, failure, and recovery. Opening it may temporarily cover the
  active Voice workspace, but it never starts, finishes, pauses, or cancels
  dictation.
- An incoming voice-state refresh does not close Quick Insert. Closing it or
  selecting an item reveals the latest underlying Voice presentation.
- A short Space tap inserts one space.
- Long-press then horizontal drag on Space moves the cursor without inserting a
  space.
- Delete removes once on tap and repeats with bounded acceleration while held.
- Return follows the current text-input traits when public information is
  available. Changing traits recomputes its width in both directions so a long
  action such as `Search` or `Continue` expands the key and a later short action
  restores the default geometry.
- Globe uses the system input-mode API and remains reachable whenever iOS
  requires it.
- Quick Insert, Space, Delete, Return, Globe, and an already-available
  restricted-mode Latest remain useful without provider setup, network, or Full
  Access.
- `Latest` inserts the first entry in accepted History and remains enabled for
  as long as that entry exists. It has no independent age or expiry policy.
- Keyboard `Latest` is not the app-private Latest Result recovery record and
  neither exposes nor clears that record.
- History opens the containing app at its canonical History destination. The
  keyboard never receives History rows, text previews, or History actions.
  The launch remains subject to the same platform and App Review gate as other
  keyboard-to-containing-app routes.

## Automatic Voice Modes

- One compact labeled `Auto` button replaces the separate Translate and Improve
  icons beside Quick Insert. It opens a compact popover matching the containing
  app's Voice control, with independent native switches labeled `Translate
  Result` and `Correct Result`. The closed button keeps the keyboard's existing
  key treatment, uses a downward chevron matching the popover direction, and
  shows how many of the two modes are selected.
- The closed button has a minimum width and expands to fit its current title,
  chevron, content insets, and supported Dynamic Type size without clipping or
  shrinking its contents. The popover contains no Clear Draft or Append action.
  Keyboard results always preserve existing host text and insert once at the
  current insertion point through `UITextDocumentProxy`.
- Selecting a mode never starts dictation. The centered microphone remains the
  only Start action and uses the currently selected modes for the next request.
  Changing a valid mode keeps the popover open so the user can change both modes
  in one visit. Opening the popover closes Quick Insert if necessary and returns
  to the Voice workspace. The popover closes on a second `Auto` tap, an outside
  tap, or opening Quick Insert. Voice-state changes do not close it.
- Auto Translate uses the saved Translation route. If that route is incomplete,
  selecting Auto Translate leaves it off and opens the containing app at the
  exact owning Translation input with inline guidance.
- Auto Correct forces the saved Writing & Correction model and prompt without
  changing the durable correction preference. Correction retains its existing
  safe fallback to the accepted transcript when the correction stage cannot
  produce a safe result.
- The two modes may be selected together. Combined requests run correction
  before translation, matching containing-app Voice behavior.
- Both modes start off when a keyboard extension lifetime begins, remain selected
  for subsequent requests in that lifetime until the user changes them, and do
  not rewrite durable Settings or share selection with containing-app Voice.
- Auto remains enabled in Ready, Opening, Starting, Listening, Processing,
  failure, and recovery. Missing Full Access, provider setup, or a warm session
  does not prevent choosing modes for the next request.
- The mode combination chosen at Start is frozen for that request. Auto changes
  made while a request is opening, starting, listening, or processing apply
  only to the next request and do not change active work.

## Keyboard Handoff Session

### Setup

- The user configures the provider, accepts provider processing, grants
  microphone permission, enables HoldType Keyboard, and enables Allow Full
  Access for keyboard-controlled dictation.
- The production keyboard does not require a manually prepared session. A
  valid cold microphone request creates the bounded app-owned session.
- V1.1 may use one fixed bounded session lifetime. Configurable session lengths,
  permanent background mode, and Live Activity controls are deferred.
- Creating the session and starting its first capture are one admitted handoff;
  provider work still begins only after capture finishes.

### Interaction

- With a valid session, the first microphone tap requests Start for one new
  request identifier.
- Ready uses the same full-color cyan HoldType recording artwork as the
  containing app, scaled to the keyboard workspace and presented statically as
  the primary Start action. A static low-energy cyan waveform appears on each
  side. The activity contains no microphone glyph, duplicate logo, or visible
  Ready label.
- The app acknowledges actual capture before the keyboard presents
  `Listening…`; an optimistic or fabricated listening state is forbidden.
- Listening keeps the recording artwork in the same location and adds the same
  restrained orbit rotation and pulse as the containing app. Both cyan
  waveforms animate through deterministic, slightly phase-shifted height and
  opacity cycles. They are phase-driven decorative motion, not a microphone
  power meter. Tapping the activity requests Finish. No separate Cancel control
  appears beside it or shifts the activity away from the workspace center;
  cancellation before the return gesture remains available from the handoff
  sheet's close action.
- A second tap requests Finish.
- Opening and Starting keep the central Voice indicator in its bounded starting
  state until real capture is acknowledged. Their cyan waveforms may use a slow
  opacity sweep but do not change height like Listening or imply microphone
  power.
- After actual capture stops, the keyboard replaces the recording artwork with
  the containing app's purple recognition artwork and slower orbit animation
  while the existing app-owned OpenAI and text-rule pipeline runs. Both purple
  waveforms use a slower edge-to-center processing cycle. The activity stays
  centered and unavailable as a primary action while processing.
- If the same live keyboard request still owns the active host context, one
  accepted result performs exactly one `insertText` call.
- If the extension is dismissed, restarted, changes host context, loses the
  request, or cannot prove current ownership, it does not auto-insert. The app
  still commits the accepted result to Latest and optional History, and the user
  may later select `Latest` explicitly.
- Only one keyboard or foreground Voice recording/provider chain may own the
  microphone at a time. A conflicting start is rejected with a compact state;
  it never creates a second recording.

### State Vocabulary

The centered status is short and contains no transcript text or manual route:

- `Ready` — the microphone can start a warm attempt or a cold handoff;
- `Full Access required` — voice commands cannot use the shared command boundary;
- `Allow Microphone` — the app lacks microphone authorization;
- `Starting…` — Start was written and is awaiting real app acknowledgement;
- `Listening…` — the app acknowledged real capture for this request;
- `Processing…` — capture stopped and app-owned processing is active;
- `No Network` — the current request cannot reach the provider;
- `Dictation failed` — a bounded failure ended the request.

Inserted text is its own success confirmation. The keyboard returns to `Ready`
without showing `Inserted` or rendering a result preview.

## Shared Boundary

- Keyboard-controlled dictation requires `RequestsOpenAccess = true`, but the
  extension itself does not contact OpenAI or transmit host keystrokes.
- The extension writes one bounded current command, including the selected
  one-shot voice action for Start; the app writes one bounded current
  state/result. Each record has exactly one writer, one current request
  identifier, an expiry, and no history or append-only log.
- Signalling may wake an already-running app-owned session, but App Group files
  are not treated as a general background-launch mechanism.
- Commands and state use atomic replacement. One opaque delivery claim and its
  acknowledgement share those same two projections; they add no outbox,
  transcript queue, lease, or second persistence system.
- App Group state may include only a boolean Translation-route-valid capability.
  It contains no language codes, translation route, model, API key, prompt,
  dictionary, canonical History, raw audio, provider body, or durable host
  context.
- Existing Latest remains a separate app-written projection of the first
  accepted History entry. It stays available for explicit insertion when
  automatic insertion is unsafe and changes only when History changes.

## Privacy And Recording

- Microphone permission is requested by the containing app only.
- The app records, buffers, and uploads audio only after a user Start action and
  until Finish, Cancel, timeout, interruption, or failure.
- An idle Keyboard Dictation Session must not retain or upload spoken content.
- The system recording indicator and HoldType keyboard state must agree with
  actual microphone ownership. App Review notes explain that audio capture and
  provider processing are app-owned.
- Provider consent is checked before every remote request. API keys remain in
  app-owned Keychain storage.
- Accepted text follows existing Latest, History, and optional Recording Cache
  policy. The command boundary does not introduce another transcript history.

## Failure And Fallback

- Session expiry, app termination, Full Access removal, microphone denial,
  interruption, timeout, offline state, or provider failure ends the current
  keyboard request without fabricating progress.
- No failure automatically retries a provider call or inserts an older result.
- A stale request or result expires and cannot be replayed into a later field.
- Secure fields, phone pads, and hosts that reject custom keyboards fall back to
  system behavior.
- Local editing and Globe remain usable whenever iOS presents HoldType.

## Accessibility And Appearance

- VoiceOver names Quick Insert, Auto and its selected modes, History, the
  microphone state/action, Latest, Globe, Space, Delete, and
  adaptive Return.
- Listening, processing, success, and failure never rely on color alone.
- Increase Contrast strengthens boundaries; Reduce Transparency replaces
  material effects with opaque system colors.
- Reduce Motion keeps both side waveforms visible as complete static silhouettes
  for the current cyan or purple phase.
- Theme follows system appearance. Light and Dark use identical geometry.
- Top-rail, Quick Insert, punctuation, and editing keys share one neutral key
  surface color in each appearance. Active, pressed, and disabled treatments
  may change emphasis without introducing another base key color.
- Re-rendering an unchanged voice phase does not rebuild the central activity
  artwork, restart its orbit or pulse, move accessibility focus, or flash the
  utility controls. A real phase, size, lifecycle, or Reduce Motion change may
  update the presentation once.

## Release Acceptance

KBD-MVP-2 uses a deliberately split feasibility qualification: a signed
physical iPhone and DEBUG containing-app controls prove the real recorder,
Finish, Cancel, expiry, and idle-audio release without presenting the keyboard
through iPhone Mirroring. The microphone indicator is recorded when the chosen
wired capture surface exposes it and is otherwise reported as unavailable;
Simulator UI and focused tests prove the extension, bounded command/state
reduction, insertion, and restricted editing half. This spike split does not
replace the signed-device keyboard/host-app release matrix below.

Automated and Simulator coverage must prove composition, both appearances,
absence of retired manual-session copy, local editing, state reduction, stale-request
rejection, bounded record decoding, one insertion per accepted live request,
explicit Latest fallback, always-available Quick Insert and Auto, and stable
same-phase activity rendering.

Signed physical-iPhone evidence must additionally prove:

- real app/extension signing and App Group access with Full Access on and off;
- absence of an extension-owned Settings or containing-app launch;
- app-owned session start, expiry, and stop;
- keyboard Start, Finish, Cancel, listening acknowledgement, provider timeout,
  and accepted insertion in real host apps;
- foreground/background transitions, interruption, Low Power Mode, process
  eviction, and microphone privacy indication;
- no automatic insertion after host-context or extension ownership changes;
- one explicitly authorized live microphone-to-OpenAI-to-host-field smoke.

The first TestFlight candidate is not ready until that device evidence passes.
App Store approval is never inferred from Simulator behavior or competitor
behavior.
