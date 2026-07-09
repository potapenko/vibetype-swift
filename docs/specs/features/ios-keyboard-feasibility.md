# iOS Keyboard Feasibility

## Goal

Establish the supported product boundary for an iOS HoldType keyboard before
building a full replacement keyboard.

This direct user request activates the iOS feasibility lane. The first delivery
is a device-validation spike, not a production keyboard and not a promise of a
seamless Wispr-style round trip.

The phased implementation plan lives in `docs/ios-keyboard-development-plan.md`.

## Platform Decision

HoldType may ship a custom keyboard extension, but it cannot add a button to or
reuse Apple's keyboard. A production keyboard must implement its own typing
experience and use `UITextDocumentProxy` for host-field interaction.

The supported architecture is:

- the containing iOS app owns onboarding, microphone permission, audio capture,
  OpenAI requests, recovery, settings, and secrets;
- the keyboard extension owns ordinary character input, keyboard switching,
  compact voice-session presentation, and accepted-text insertion;
- a minimal versioned App Group record carries non-secret session state and an
  accepted transcript between the two processes;
- the keyboard extension does not record audio, store the API key, or call
  OpenAI.

Apple provides no public API that reliably opens the containing app, identifies
the previous host app, and returns the user to the same text field. The product
must validate the app-switch and background-session alternatives on physical
devices before implementing a full QWERTY engine.

The selected product hypothesis for that validation is an explicit, five-minute
Quick Session started in the containing app. The user returns manually to the
host app and may need to reselect HoldType with Globe. While the session is
active, a future Full-Access bridge may carry start, stop, and insertion-
acknowledgement commands. HoldType does not use a private app-launch or automatic
return API.

The M0C hypothesis keeps the containing app's microphone/audio engine visibly
active for those five minutes so iOS can continue the background session. In
the armed `ready` state, incoming samples are immediately discarded in memory;
they are not written or uploaded. Only audio after an explicit keyboard mic tap
is retained for the current utterance. If this behavior is rejected in review,
uses unacceptable battery, or cannot be made unambiguous, the Quick Session
gate fails and HoldType falls back to manual one-shot recording.

## Product Direction

The target is system-conforming and familiar, not a pixel-identical Apple
clone.

- Ordinary typing remains usable without network access and without Full
  Access.
- Voice input uses a dedicated control in a compact action bar after the voice
  handoff is proven.
- Long press on Space remains reserved for cursor movement.
- Literal transcription with punctuation is the default; semantic rewriting
  is an explicit option.
- Finished audio is recoverable until transcription and insertion have
  succeeded.
- The initial product milestone is iPhone. iPad is a separate product milestone
  because floating layouts, Stage Manager, and hardware keyboards change the
  interaction model.

Detailed keyboard behavior is defined in `ios-keyboard-experience.md`.

## Phase 0 Spike Contract

The first buildable spike must include:

- an embedded `com.apple.keyboard-service` extension;
- one ordinary character key that calls `insertText`;
- a required next-keyboard control using the system input-mode API;
- read-only loading of a harmless accepted-transcript sample from an App Group;
- insertion of that sample through `UITextDocumentProxy`;
- a containing-app probe that publishes the sample;
- no microphone, background audio, Speech framework, provider network request,
  Keychain sharing, or containing-app launch from the extension.

`hasDictationKey` remains false in this phase so the spike does not suppress a
system dictation control. `RequestsOpenAccess` remains false until a later
device test demonstrates a justified write requirement.

The spike is internal validation code. It is not expected to satisfy the final
App Store requirement for a complete ordinary typing experience.

## App Group Boundary

The shared record contract is defined in `ios-keyboard-shared-state.md`.

The containing app is the only writer in Phase 0. The extension reads only a
schema version, revision, session metadata, short status, and accepted
transcript. Raw audio, API keys, prompts, keystrokes, host-app identity, and
provider payloads never enter the shared record.

The App Group is state transport, not a wake-up mechanism. File replacement is
atomic, records expire, and stale or incompatible records are treated as
unavailable.

## System Limits

- Third-party keyboards are unavailable in secure text fields and selected
  phone-pad contexts.
- A host app may reject all third-party keyboards.
- Full Access does not grant a documented microphone entitlement to a custom
  keyboard.
- A keyboard must expose the next-keyboard control whenever the system requires
  it.
- A production keyboard must still enter ordinary Unicode characters without
  Full Access and without network access.
- Apple emoji artwork is not embedded in the custom keyboard; the Globe route
  provides system emoji access in the initial product.

These are platform limitations, not failed HoldType sessions.

## Go / No-Go Gate

Do not begin the full typing engine until physical-device evidence shows that:

- the extension can read and insert accepted text reliably in representative
  host apps;
- no completed recording is lost during the proposed containing-app or bounded
  background-session flow;
- the user is never silently returned to or inserted into the wrong field;
- microphone activation and shutdown remain visible and bounded;
- after tapping Start in HoldType, returning to a HoldType-ready host field takes
  at most two clear actions: return to the host and, when needed, reselect the
  keyboard with Globe;
- secure fields, phone fields, host rejection, process eviction, and expired
  state fail safely.

If the gate fails, retain Apple Dictation as the keyboard fallback and consider
an app/Shortcut voice workflow instead of a default-keyboard replacement.

Apple Dictation fallback is conditional: iOS may expose a system dictation
control while HoldType is active, but otherwise the user switches with Globe to
Apple's keyboard and starts Dictation there.

## Verification

Automated checks cover the versioned shared record and pure state transitions.
Simulator builds prove target composition and extension embedding, but they do
not prove Full Access, keyboard switching, microphone lifecycle, app return,
secure-field fallback, iPad floating layout, or process eviction.

Those behaviors require bounded physical-device QA recorded in `docs/qa/runs/`.

## Evidence

- Apple Custom Keyboard guide, reviewed 2026-07-09:
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html`
- Apple Creating a Custom Keyboard, reviewed 2026-07-09:
  `https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard`
- Apple Configuring Open Access, reviewed 2026-07-09:
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`
- Apple App Review Guidelines 4.4.1, reviewed 2026-07-09:
  `https://developer.apple.com/app-store/review/guidelines/`
- Apple DTS on the absence of a public keyboard-to-host round trip, reviewed
  2026-07-09:
  `https://developer.apple.com/forums/thread/826851`

## Invariants

- No direct audio recording or OpenAI call from the keyboard extension.
- No API key or raw audio in the App Group.
- No hidden, indefinite, or ambiguous microphone session.
- No reliance on private app-return APIs.
- No voice gesture that replaces the Space cursor gesture or another standard
  keyboard action.
- No full QWERTY investment before the device feasibility gate passes.
