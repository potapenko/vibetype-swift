# iOS Keyboard Feasibility

Status: active feasibility evidence; K1 voice activation is not qualified for
production as of 2026-07-14. The current product scope and implementation order
are `ios-v1-release.md` and `docs/ios-v1-development-plan.md`. The former full-
replacement QWERTY and Quick Session hypotheses are superseded by Brand Stage
Adaptive.

## Goal

Establish whether HoldType can ship a public-API, App-Review-compatible voice-
command keyboard with honest app handoff and explicit result insertion. This is
not a promise to reproduce Apple's keyboard or build multilingual typing layouts.

## Platform Decision

HoldType may ship a custom keyboard extension, but it cannot add a button to or
reuse Apple's keyboard. Its supported architecture is:

- the containing app owns onboarding, microphone permission, audio capture,
  OpenAI requests, recovery, settings, secrets, Library, Latest, and canonical
  History;
- the extension owns punctuation, Space, Delete, Return, keyboard switching,
  voice-state presentation, and explicit accepted-text insertion through
  `UITextDocumentProxy`;
- the app is the only writer of a small versioned App Group snapshot containing
  only one optional 10-minute Latest item;
- the extension is read-only and never records audio, reads Keychain, calls
  OpenAI, renders History, or mutates canonical History.

Apple documents `NSExtensionContext.open` on iOS for Today and iMessage
extension points, not custom keyboards. App Review Guideline 4.4.1 also says a
keyboard extension must not launch apps other than Settings. Apple provides no
public host-identity or automatic-return contract. A one-way custom URL may work
on some iOS versions, but that alone does not make it a documented or review-safe
production action. HoldType does not use a private launch or return workaround.

## Selected Product Direction

The production target is the Brand Stage Adaptive command surface defined in
`ios-keyboard-experience.md`:

- one non-interactive branded voice state while HoldType handoff is unavailable;
- Apple's own Dictation key when iOS supplies it, one compact `History`
  app-navigation action, and one compact Latest insertion action;
- `.`, `,`, `?`, `!`, Globe, wide Space, Delete, and adaptive Return;
- long-press and drag on Space for cursor movement;
- system-driven Light and Dark appearances with stable composition;
- no alphabetic, numeric, symbol-deck, Shift/Caps, prediction, autocorrection,
  or keyboard-locale engine.

The surface provides real local character/editing input without network or Full
Access. Ordinary alphabetic typing, other language layouts, and system emoji
remain available through Globe. Accepted result text may contain arbitrary
Unicode and is independent of the keyboard metadata locale.

The selected composition requires `History` visually and semantically, but the
keyboard-originated launch is not production-qualified by registering a custom
URL alone. The containing app may implement and test its public History route;
the extension must not use a private responder-chain or automatic-return
workaround if the public extension request is rejected.

## Current Implementation Evidence

The current production-shaped extension includes:

- an embedded `com.apple.keyboard-service` extension;
- Brand Stage Adaptive with `History`, `Latest`, punctuation, Space, Delete,
  adaptive Return, and a conditional system input-mode switcher;
- read-only loading of one bounded, expiring Latest item from App Group;
- explicit Latest insertion through `UITextDocumentProxy`;
- `Ready` as the normal status and only a brief `Open failed` problem state;
- no microphone, background audio, Speech framework, provider request, shared
  Keychain access, private app-launch path, or qualified app-launch dependency.
  The separate public History request remains an explicit no-go gate.

Simulator runtime evidence proves target composition, Light/Dark adaptation,
large-text layout, and local interaction only. The former probe `A`, manual
`Refresh`, large `Insert latest` button, and Full Access instruction are removed.

`hasDictationKey` remains false so iOS may supply its own system Dictation key.
That key is Apple-owned speech entry, not a HoldType/OpenAI action.
`RequestsOpenAccess`,
`PrimaryLanguage`, and `IsASCIICapable` are release metadata to verify in K1;
the current `en-US` value is not a product language promise.

## App Group Boundary

- The containing app is the only writer and replaces the bounded snapshot
  atomically.
- The extension reads only schema/revision metadata and one optional Latest
  result identifier, exact accepted text, creation date, and 10-minute expiry.
- Expired source results are omitted, and app startup replaces obsolete schema
  1/2 cache payloads with an empty current-schema snapshot. Production Latest
  publication is enabled.
- If the current canonical Latest cannot be projected safely, an empty
  current-schema snapshot replaces older shared text. If canonical state cannot
  be loaded, the bounded last-known snapshot is preserved until normal expiry.
- Raw audio, API keys, prompts, keystrokes, host identity, provider payloads,
  canonical settings, recent results, and the History repository never enter
  App Group.
- Publication is not a wake-up mechanism. Missing, stale, corrupt, oversized,
  or incompatible state is unavailable and never causes insertion.
- `RequestsOpenAccess` is false. Apple documents read-only access to the
  containing app's shared containers without Full Access; matching effective
  App Group entitlements still require signed-device evidence.

## System And Review Limits

- Custom keyboards are unavailable in secure text fields and selected phone-pad
  contexts, and a host app may reject all third-party keyboards.
- Full Access does not grant a documented microphone entitlement to a custom
  keyboard.
- With `hasDictationKey == false`, iOS may show an Apple-owned Dictation key.
  The extension neither receives its audio nor controls whether it appears.
- A keyboard must expose the next-keyboard control whenever iOS requires it.
- App Review 4.4.1 requires keyboard input functionality, a next-keyboard path,
  and useful behavior without network access; punctuation and editing controls
  satisfy the intended product behavior but do not guarantee review approval.
- A negative App Review or platform result does not authorize private APIs or a
  surprise QWERTY project. It triggers an explicit product rescope.

## K1 Go / No-Go Result

K1 is not qualified for the specified production keyboard-started voice action
under current public documentation and App Review rules. Do not add a custom
URL, hidden host lookup, responder-chain launch, or instruction-only microphone
and call it complete.

Signed physical iPhone qualification is still required for the non-blocked
keyboard behavior:

- one explicit Latest insertion without wrong-field replay;
- Globe, punctuation, Space cursor movement, Delete repeat, and adaptive Return
  in representative first- and third-party hosts;
- restricted-mode App Group reading with no Full Access request, real effective
  entitlements, app and extension eviction, and missing/corrupt snapshot
  behavior;
- secure fields, phone fields, host rejection, interruption, and provider timeout
  fail safely;
- `PrimaryLanguage`, `IsASCIICapable`, `RequestsOpenAccess`, and
  `hasDictationKey` produce truthful system and review behavior, including the
  system Dictation key's device- and host-dependent presence.

The existing fallback is the containing-app Voice flow plus Copy and the user's
system keyboard. Brand Stage editing and result insertion may be completed, but
shipping it as keyboard-plus-voice V1.1 requires an explicit product rescope,
new Apple guidance, or an explicit acceptance of the remaining review risk. An
instruction-only microphone is not successful completion.

## Verification

Automated checks cover snapshot schema/limits, pure state transitions, the real
keyboard view hierarchy, editing geometry, appearance, accessibility labels,
and insertion idempotency per tap. Simulator builds prove embedding and
rendering only. Restricted App Group access, keyboard switching, secure-field
fallback, process eviction, effective Data Protection, and review-facing
metadata require bounded physical-device QA recorded in `docs/qa/runs/`.

## Evidence

- Apple Custom Keyboard guide, reviewed 2026-07-09:
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html`
- Apple Creating a Custom Keyboard, reviewed 2026-07-09:
  `https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard`
- Apple Configuring Open Access, reviewed 2026-07-09:
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`
- Apple App Review Guidelines 4.4.1, reviewed 2026-07-13:
  `https://developer.apple.com/app-store/review/guidelines/`
- Apple `NSExtensionContext.open` support discussion, reviewed 2026-07-13:
  `https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:)`
- Apple `UIInputViewController.hasDictationKey`, reviewed 2026-07-13:
  `https://developer.apple.com/documentation/uikit/uiinputviewcontroller/hasdictationkey`
- Apple Dictation user guide, reviewed 2026-07-13:
  `https://support.apple.com/guide/iphone/iph2c0651d2/ios`
- Apple App Extension Programming Guide, reviewed 2026-07-13:
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html`
- Apple DTS on the absence of a public keyboard-to-host round trip, reviewed
  2026-07-09: `https://developer.apple.com/forums/thread/826851`

## Invariants

- No direct audio recording or OpenAI call from the extension.
- No API key, raw audio, canonical History, or settings repository in App Group.
- No hidden, indefinite, or ambiguous microphone session.
- No reliance on private app-return APIs.
- No voice gesture that replaces Space cursor movement or another editing key.
- No QWERTY, locale-layout, prediction, or autocorrection expansion in V1.1.
