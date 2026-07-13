# iOS Keyboard Experience

Status: active V1.1 UX contract; Brand Stage Adaptive selected 2026-07-13.
`ios-v1-release.md` wins any conflict.

## Goal

Provide a polished HoldType voice-command keyboard that complements the user's
system keyboards. It starts only the physically verified voice flow, exposes
accepted results for explicit insertion, and keeps the small editing controls
needed to finish a sentence without building a multilingual QWERTY engine.

## Product Role

- HoldType is selected with Globe when the user wants voice input or a recent
  HoldType result.
- The system keyboard remains the normal alphabetic, numeric, emoji, and
  language-layout keyboard.
- HoldType inserts accepted Unicode text in any transcription language supported
  by the containing app. It has no keyboard-locale promise.
- The extension never records audio, contacts OpenAI, reads Keychain, or owns
  app settings, Library data, Pending audio, or canonical History.
- Voice is the only primary action. `History` and `Latest` are compact secondary
  actions, not competing call-to-action buttons.

## Brand Stage Adaptive Composition

The keyboard keeps one stable composition in Light and Dark Mode:

1. Top rail: `History` at leading, the HoldType mark and current state centered,
   and `Latest` at trailing.
2. Voice stage: one medium circular microphone control with a restrained
   waveform or progress treatment.
3. Correction row: `.`, `,`, `?`, and `!`.
4. Editing row: Globe, wide Space, Delete, and adaptive Return.

The HoldType mark is decorative identity plus status context. It is never an
unlabelled action. The microphone is visually primary but does not fill the
keyboard width. The interface contains no `A` probe key, manual `Refresh`,
alphabet layout, number deck, Shift, Caps Lock, `123`, prediction row, settings
gear, or opaque mode icon.

Light Mode uses system-light surfaces, neutral keycaps, and restrained shadows.
Dark Mode uses deep navy system-dark surfaces and lighter translucent keycaps.
Geometry, order, labels, and touch targets do not change between appearances.
HoldType blue `#5165E8` and purple `#844DF2` are reserved for the microphone,
focus, and small active-state accents; the whole background is never a gradient.

## Editing Controls

- `.`, `,`, `?`, and `!` insert their literal Unicode scalar locally.
- A short Space tap inserts one space.
- Long-press then horizontal drag on Space moves the insertion cursor through
  `UITextDocumentProxy`; beginning a cursor gesture does not insert a space.
- Delete removes one unit on tap and repeats with bounded acceleration while
  held. Releasing, cancelling, or losing view ownership stops repeat immediately.
- Return inserts the host-appropriate return action and uses a label or symbol
  derived from current text-input traits when that information is available.
- Globe uses the system input-mode API and remains reachable whenever iOS
  requires it.
- Punctuation, Space, Delete, Return, and Globe work without network, provider
  setup, Full Access, or a running containing app.

## Voice States

The centered brand/status and voice stage show only these user-visible states:

- `needsSetup`: required app-owned setup is incomplete; the keyboard explains
  the next app step without requesting credentials or microphone permission;
- `ready`: the verified voice action can begin now;
- `handoffRequested`: a supported public handoff was requested, but the keyboard
  does not claim recording has started;
- `recording`: shown only after the containing app confirms that it owns an
  active recording; waveform, Cancel, and Finish are unambiguous;
- `processing`: capture has stopped and an accepted result is not ready yet;
- `resultReady`: a valid Latest snapshot can be inserted;
- `inserted`: brief non-blocking confirmation after one explicit insertion;
- `recoverableFailure`: compact Retry or recovery guidance for a known failure;
- `stale`: shared state is expired, incompatible, or no longer eligible.

The UI never uses `Ready`, `Recording`, or `Listening` as optimism. Each label
must correspond to app-confirmed state. Cancel and Finish are visually separate
and cannot be mistaken for History, Latest, or editing keys. Reduce Motion turns
waveform animation into a static level/status treatment.

## Voice Activation Contract

- The microphone performs only the public, App-Review-compatible action proven
  by the signed K1 device gate.
- The keyboard does not open the containing app through private APIs and does
  not promise automatic return to the previous host field.
- The user manually returns to the host app and may need to reselect HoldType
  with Globe.
- An instruction-only microphone, fabricated recording state, or private URL
  workaround does not pass K1.
- If no supported handoff exists, the keyboard-plus-voice release is a no-go and
  requires an explicit product rescope; implementation does not grow a QWERTY
  engine to compensate.

## Latest And Keyboard History

- The containing app is the only writer of the bounded App Group keyboard
  snapshot. The extension is read-only.
- `Latest` is enabled only for a valid unexpired accepted item. One tap performs
  one `insertText` call. It never inserts on appearance, refresh, app return, or
  host-field change.
- `History` opens an in-keyboard recent-results view, newest first, containing at
  most five app-published accepted texts from the previous 24 hours. Expired
  items are never rendered. Selecting an item is an explicit one-tap insertion.
- The recent-results view replaces the voice stage temporarily; the editing row
  stays available and an explicit close action restores the voice stage.
- Full 20-entry History, detail, Share, Delete, Clear All, and Save History
  controls remain in the containing app.
- The projection contains result id, text, creation date, and expiry only. It
  contains no audio, Pending metadata, prompt, provider payload, settings,
  dictionary, deletion command, or canonical History file.
- Save History off produces a truthful disabled History state. A missing,
  corrupt, unsupported, or inaccessible projection produces a compact retry or
  setup state; it is never labelled as an empty successful History and never
  says merely `Unavailable in this build`.
- A new Latest item or recent-results projection is observed at normal extension
  lifecycle boundaries. There is no manual Refresh button and App Group
  publication is not treated as a wake-up mechanism.

## Failure And Fallback

- Secure fields, selected phone pads, and host-app rejection fall back to system
  behavior; HoldType does not claim to bypass iOS policy.
- Offline, provider failure, or missing Full Access disables only app-dependent
  voice/result actions. Local editing and Globe remain usable.
- Expired or invalid Latest never inserts. Repeated lifecycle refreshes never
  replay a previous result.
- The keyboard never requests an API key, microphone permission, long-form
  consent, or destructive History action inline.
- System emoji and ordinary typing remain available by switching with Globe.

## Accessibility And Appearance

- Every interactive target is at least 44 by 44 points.
- VoiceOver names the action and current state, including `Insert latest`,
  `Open recent results`, `Start voice input`, `Next keyboard`, `Space`, `Delete`,
  and the adaptive Return action.
- Recording, processing, success, and failure do not rely on color alone.
- Increase Contrast strengthens boundaries without changing hierarchy. Reduce
  Transparency replaces material effects with opaque system colors.
- Dynamic Type may enlarge labels without moving or shrinking the editing row;
  truncation never hides whether an action is History, Latest, Cancel, or Finish.
- Theme follows system appearance automatically. There is no keyboard-local
  Light/Dark toggle.

## iPhone And iPad

The first qualified surface is iPhone portrait and landscape. iPad containing-
app compatibility does not imply keyboard qualification. Docked/floating iPad,
Stage Manager, multiple windows, and hardware-keyboard workflows remain a later
milestone with their own layout and signed-device evidence.

## Release Acceptance

Automated and simulator coverage must prove composition, Light/Dark adaptation,
editing semantics, honest state reduction, bounded snapshot decoding, and one
explicit insertion per tap.

Signed-device evidence must additionally prove Globe, Full Access off/on,
cursor movement, Delete repeat, host field traits, secure/phone-field fallback,
public microphone handoff, manual return, Latest, recent-result insertion, and
process eviction. App Review 4.4.1 remains a release risk to validate; the
punctuation/editing surface is real keyboard input, but approval is not assumed.

After K1, the production controller may set `hasDictationKey = true` only if
physical QA confirms that HoldType's dedicated voice control should suppress a
duplicate system Dictation key. Until then it remains false.
