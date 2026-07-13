# iOS Keyboard Feasibility

Status: physical-device feasibility evidence. The current product scope and
implementation order are `ios-v1-release.md` and
`docs/ios-v1-development-plan.md`. The former full-replacement QWERTY and Quick
Session hypotheses are superseded by Brand Stage Adaptive.

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
  a 10-minute Latest item and at most five accepted texts with a 24-hour expiry;
- the extension is read-only and never records audio, reads Keychain, calls
  OpenAI, or mutates canonical History.

Apple provides no public API that reliably opens the containing app, identifies
the previous host app, and returns the user to the same text field. The exact
voice action therefore remains a signed-device K1 gate. HoldType does not use a
private app-launch or automatic-return workaround.

## Selected Product Direction

The production target is the Brand Stage Adaptive command surface defined in
`ios-keyboard-experience.md`:

- one dedicated microphone action with app-confirmed state;
- compact History and Latest actions;
- `.`, `,`, `?`, `!`, Globe, wide Space, Delete, and adaptive Return;
- long-press and drag on Space for cursor movement;
- system-driven Light and Dark appearances with stable composition;
- no alphabetic, numeric, symbol-deck, Shift/Caps, prediction, autocorrection,
  or keyboard-locale engine.

The surface provides real local character/editing input without network or Full
Access. Ordinary alphabetic typing, other language layouts, and system emoji
remain available through Globe. Accepted result text may contain arbitrary
Unicode and is independent of the keyboard metadata locale.

## Phase 0 Evidence

The existing internal spike includes:

- an embedded `com.apple.keyboard-service` extension;
- one `insertText` probe key;
- a required next-keyboard control using the system input-mode API;
- read-only loading of a harmless accepted-transcript sample from an App Group;
- explicit sample insertion through `UITextDocumentProxy`;
- no microphone, background audio, Speech framework, provider request, shared
  Keychain access, or containing-app launch from the extension.

This proves target composition and simulator interaction only. The probe `A`,
manual `Refresh`, and large `Insert latest` button are not product UI and are
removed by K2.

`hasDictationKey` remains false in the spike. `RequestsOpenAccess`,
`PrimaryLanguage`, and `IsASCIICapable` are release metadata to verify in K1;
the current `en-US` value is not a product language promise.

## App Group Boundary

- The containing app is the only writer and replaces the bounded snapshot
  atomically.
- The extension reads only schema/revision metadata, accepted result identifiers,
  accepted text, creation dates, Latest expiry, and compact voice status proven
  necessary by K1.
- Raw audio, API keys, prompts, keystrokes, host identity, provider payloads,
  canonical settings, and the 20-entry History repository never enter App Group.
- Publication is not a wake-up mechanism. Missing, stale, corrupt, oversized,
  or incompatible state is unavailable and never causes insertion.
- Full Access requirements and actual shared-container behavior are established
  by signed provisioning evidence, not simulator assumptions.

## System And Review Limits

- Custom keyboards are unavailable in secure text fields and selected phone-pad
  contexts, and a host app may reject all third-party keyboards.
- Full Access does not grant a documented microphone entitlement to a custom
  keyboard.
- A keyboard must expose the next-keyboard control whenever iOS requires it.
- App Review 4.4.1 requires keyboard input functionality, a next-keyboard path,
  and useful behavior without network access; punctuation and editing controls
  satisfy the intended product behavior but do not guarantee review approval.
- A negative App Review or platform result does not authorize private APIs or a
  surprise QWERTY project. It triggers an explicit product rescope.

## K1 Go / No-Go Gate

Do not claim keyboard voice readiness until a signed physical iPhone proves:

- the public microphone action and every state shown before, during, and after
  containing-app handoff;
- manual return and one explicit Latest insertion without wrong-field replay;
- the bounded recent-results projection and explicit insertion of one selected
  item;
- Globe, punctuation, Space cursor movement, Delete repeat, and adaptive Return
  in representative first- and third-party hosts;
- Full Access off/on, real App Group entitlements, app and extension eviction,
  and missing/corrupt snapshot behavior;
- secure fields, phone fields, host rejection, interruption, and provider timeout
  fail safely;
- `PrimaryLanguage`, `IsASCIICapable`, `RequestsOpenAccess`, and
  `hasDictationKey` produce truthful system and review behavior.

If supported handoff fails, the keyboard-plus-voice V1.1 is a no-go. The fallback
is the containing-app Voice flow plus Copy and the user's system keyboard; an
instruction-only microphone is not successful completion.

## Verification

Automated checks cover snapshot schema/limits, pure state transitions, editing
semantics, appearance, accessibility labels, and insertion idempotency per tap.
Simulator builds prove embedding and rendering only. Full Access, keyboard
switching, microphone lifecycle, app return, secure-field fallback, process
eviction, effective Data Protection, and review-facing metadata require bounded
physical-device QA recorded in `docs/qa/runs/`.

## Evidence

- Apple Custom Keyboard guide, reviewed 2026-07-09:
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html`
- Apple Creating a Custom Keyboard, reviewed 2026-07-09:
  `https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard`
- Apple Configuring Open Access, reviewed 2026-07-09:
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`
- Apple App Review Guidelines 4.4.1, reviewed 2026-07-13:
  `https://developer.apple.com/app-store/review/guidelines/`
- Apple DTS on the absence of a public keyboard-to-host round trip, reviewed
  2026-07-09: `https://developer.apple.com/forums/thread/826851`

## Invariants

- No direct audio recording or OpenAI call from the extension.
- No API key, raw audio, canonical History, or settings repository in App Group.
- No hidden, indefinite, or ambiguous microphone session.
- No reliance on private app-return APIs.
- No voice gesture that replaces Space cursor movement or another editing key.
- No QWERTY, locale-layout, prediction, or autocorrection expansion in V1.1.
