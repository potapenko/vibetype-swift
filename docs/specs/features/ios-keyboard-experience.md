# iOS Keyboard Experience

Status: active V1.1 UX contract; Brand Stage Adaptive selected and restricted
keyboard access confirmed 2026-07-14.
`ios-v1-release.md` wins any conflict.

Current K1 result: Apple does not document containing-app launch for custom
keyboard extensions, and App Review 4.4.1 forbids keyboard extensions from
launching apps other than Settings. The selected design nevertheless keeps the
user-required `History` handoff as a distinct top-rail action. The containing
app route and the button are implemented with public APIs only, but the action
is not release-qualified until its keyboard-originated launch is proven and the
remaining review risk is explicitly accepted or Apple clarifies the rule. The
same unresolved gate keeps the microphone stage visibly unavailable and
non-interactive; it is not an instruction-only fake action.

## Goal

Provide a polished HoldType command keyboard that complements the user's system
keyboards. It preserves Apple's system Dictation path when iOS offers it,
provides a direct `History` handoff plus `Latest` insertion, and keeps the small
editing controls needed to finish a sentence without building a multilingual
QWERTY engine.

## Product Role

- HoldType is selected with Globe when the user wants system Dictation, the
  latest HoldType result, or the compact editing controls.
- The system keyboard remains the normal alphabetic, numeric, emoji, and
  language-layout keyboard.
- HoldType inserts accepted Unicode text in any transcription language supported
  by the containing app. It has no keyboard-locale promise.
- The extension never records audio, contacts OpenAI, reads Keychain, or owns
  app settings, Library data, Pending audio, or canonical History.
- Apple's system Dictation is the only actionable microphone path currently
  qualified. `Latest` is a compact secondary action.
- Canonical History and every History row remain in the containing app. The
  keyboard never renders transcript text, History lists, previews, or detail.
- `History` is navigation, not a data surface: it requests the containing app's
  History destination and never copies History records into the extension.

## Brand Stage Adaptive Composition

The keyboard keeps one stable composition in Light and Dark Mode:

1. Top rail: `History` on the left, the HoldType mark and current state centered,
   and `Latest` on the right.
2. Voice stage: one medium circular microphone control with a restrained
   waveform or progress treatment.
3. Correction row: `.`, `,`, `?`, and `!`.
4. Editing row: Globe, wide Space, Delete, and adaptive Return.

The approved Option 2 reference is the geometry source of truth. On iPhone the
surface uses approximately 18-point side insets, 8-point key gaps, an
approximately 80-point voice circle, four equal punctuation keys, and the
editing-key width relationship `Globe : Space : Delete : Return` of roughly
`1 : 4.35 : 1.15 : 1.25`. If iOS already supplies the input-mode control
outside the extension, Space, Delete, and Return retain their relative
`3.8 : 1 : 1.07` balance rather than allowing Return or Space to absorb the
row. Wider iPad layouts keep a centered maximum content width instead of
stretching fixed controls across the whole screen.

On compact-height iPhone landscape, the full top rail remains visible and the
lower surface reflows into two columns rather than hiding the voice identity.
The left column keeps the non-interactive 80-point microphone and waveform;
the right column stacks the four punctuation keys above the editing row. The
surface remains approximately 176 points tall plus the system safe-area inset,
with every action at least 44 by 44 points. Portrait and iPad keep the vertical
Option 2 composition.

The keyboard is one visually distinct surface with rounded top-left and
top-right corners. It must not merge into the containing app background.
`History` and `Latest` normally use equal 88-point top-rail widths. At
accessibility content sizes, both expand equally so the brand/status column
stays exactly centered. The HoldType mark is a full-color transparent image
with no embedded square background and is identical in Light and Dark Mode.

The HoldType mark is decorative identity plus status context. It is never an
unlabelled action. The branded microphone treatment is non-interactive while
HoldType handoff is unavailable and does not compete with the separate system
Dictation key when iOS displays one. The interface contains no `A` probe key,
manual `Refresh`,
alphabet layout, number deck, Shift, Caps Lock, `123`, prediction row, settings
gear, or opaque mode icon.

The top-rail status is deliberately terse: `Ready` when the local command
surface is usable, or `Open failed` after an unsuccessful History request.
Latest availability is communicated by the `Latest` button itself and
is never repeated in the centered status. `Ready` describes the keyboard
surface only; it never claims that HoldType recording has started or that the
unqualified microphone handoff is available. Successful taps and in-progress
actions do not replace this label with messages such as `Inserted`, `Latest
ready`, or `Opening History`.

Light Mode uses a clearly separated cool-light surface, neutral keycaps,
restrained borders, and native-looking shadows.
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

## Status Contract

The centered label has only two values:

- `Ready` while the local keyboard controls are usable;
- `Open failed` briefly after the public History request reports failure.

Button enablement communicates Latest availability. Successful insertion has
no text confirmation inside the keyboard because the inserted text is already
visible in the host field. Longer setup, permission, recording, processing, or
recovery explanations belong in the containing app. A future qualified voice
handoff must revise this spec before adding any new keyboard status vocabulary.

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
- Under the current unresolved K1 result, the microphone adds no app-launch
  action and shows no voice-ready, `handoffRequested`, `recording`, or
  `processing` state. The branded voice stage is disabled and ignored as an
  action by assistive technology. This does not remove the separate History
  navigation control or the surface-level `Ready` label.
- `hasDictationKey` remains `false`. Apple may then provide its own Dictation
  key outside the extension. That Apple-owned path may insert speech into the
  host field, but it does not run HoldType/OpenAI, expose audio to the extension,
  or provide a HoldType completion callback.

## Latest

- The containing app is the only writer of the bounded App Group keyboard
  snapshot. The extension is read-only.
- The extension declares `RequestsOpenAccess = false`. Apple permits read-only
  access to the containing app's shared containers without Full Access, so
  Latest reading and insertion never depend on `hasFullAccess`.
- `Latest` is enabled only for a valid unexpired accepted item. One tap performs
  one `insertText` call. It never inserts on appearance, refresh, app return, or
  host-field change.
- The snapshot contains only schema/revision metadata and one optional Latest
  item: result id, exact accepted text, creation date, and 10-minute expiry.
- An already-expired app result is omitted rather than copied into the shared
  snapshot. An item that expires after publication becomes ineligible for
  insertion immediately; the open keyboard disables `Latest` at that expiry
  even if no lifecycle event or new publication occurs.
- If the current canonical Latest cannot be shared safely, the app atomically
  publishes an empty current-schema snapshot instead of leaving an older result
  presented as Latest. The cache publication reports failure without invalidating
  the canonical accepted result.
- A failed cache publication is a nonblocking containing-app warning. It remains
  pending until a later publication actually succeeds; a load, a failed Clear,
  or another path that does not publish the cache must not clear it.
- Canonical Latest and Clear notices take display priority without discarding a
  pending cache warning. When the canonical notice is gone, the cache warning is
  shown again until publication succeeds.
- If publishing an empty snapshot after Clear fails, the containing app keeps a
  visible Latest section warning even though canonical Latest is absent, because
  an older unexpired keyboard item may still remain in the shared container.
- Cache-warning-only fail or recovery updates do not invalidate an already
  visible canonical Latest action or dismiss its pending Clear confirmation.
- If canonical state cannot be loaded at all, the publisher does not overwrite
  the last-known cache with an invented empty state. The normal 10-minute expiry
  still prevents indefinite insertion.
- App startup atomically replaces legacy schema 1/2 cache payloads with an
  empty schema 3 snapshot. Legacy History or recent-result fields are never
  retained for later keyboard use.
- Latest text is never rendered or previewed by the keyboard. It enters the host
  field only after an explicit `Latest` tap.
- Full History, previews, detail, Share, Delete, Clear All, and retention
  controls remain in the containing app and never enter the keyboard snapshot.
- A new Latest item is observed at normal extension lifecycle boundaries. There
  is no manual Refresh button and App Group publication is not a wake-up
  mechanism.

## History Handoff

- `History` is always visible in the left top-rail position and is independent
  of Latest availability, provider setup, network, and Full Access.
- A tap requests the stable containing-app route `holdtype://history`. The
  containing app resolves that route to its real History destination in both
  tab and split layouts.
- The handoff never inserts text, never previews a transcript, and never reads
  or publishes History through App Group storage.
- If the containing app already has an unsaved Library or Settings edit, its
  existing confirmation policy still protects that work before navigation.
- Only public extension APIs may request the launch. A private responder-chain
  trampoline, hidden `UIApplication` access, or fabricated success is not an
  acceptable implementation.
- A Simulator `openurl` check qualifies the containing-app route only. The
  keyboard-originated launch and review posture remain a signed-device/release
  gate; failure must leave the keyboard usable and show a compact honest status.

## Failure And Fallback

- Secure fields, selected phone pads, and host-app rejection fall back to system
  behavior; HoldType does not claim to bypass iOS policy.
- Offline or provider failure does not affect local editing, Globe, or an
  already-published valid Latest item. A missing or invalid shared snapshot
  disables only `Latest`.
- Expired or invalid Latest never inserts. Repeated lifecycle refreshes never
  replay a previous result.
- The keyboard never requests an API key, microphone permission, long-form
  consent, or History management inline.
- System emoji and ordinary typing remain available by switching with Globe.

## Accessibility And Appearance

- Every interactive target is at least 44 by 44 points.
- VoiceOver names the action and current state, including `Open History in
  HoldType`, `Insert latest`, `Next keyboard`, `Space`, `Delete`, and the
  adaptive Return action. The unavailable branded microphone treatment is not
  exposed as a button.
- Recording, processing, success, and failure do not rely on color alone.
- Increase Contrast strengthens boundaries without changing hierarchy. Reduce
  Transparency replaces material effects with opaque system colors.
- Dynamic Type may enlarge labels without moving or shrinking the editing row;
  truncation never hides whether an action is Latest, Cancel, or Finish.
- Theme follows system appearance automatically. There is no keyboard-local
  Light/Dark toggle.

## iPhone And iPad

The first qualified surface is iPhone portrait and landscape. iPad containing-
app compatibility does not imply keyboard qualification. Docked/floating iPad,
Stage Manager, multiple windows, and hardware-keyboard workflows remain a later
milestone with their own layout and signed-device evidence.

## Release Acceptance

Automated and simulator coverage must prove composition, Light/Dark adaptation,
the containing-app History route, editing semantics, honest state reduction,
bounded snapshot decoding, and one explicit insertion per tap.

Signed-device evidence must additionally prove Globe, restricted-mode read-only
App Group access with no Full Access request, cursor movement, Delete repeat,
host field traits, secure/phone-field fallback, Latest insertion, system
Dictation presence/absence, and process eviction.
Current documentation does not qualify HoldType microphone handoff; the system
Dictation and punctuation/editing paths are real keyboard input, but approval is
not assumed.

`hasDictationKey` remains `false` so HoldType does not suppress Apple's own
Dictation key. It may become `true` only after a separate, physically qualified
HoldType microphone action exists and product explicitly chooses to replace the
system path.
