# iOS Keyboard Handoff And Delivery

Status: active canonical contract for keyboard-originated dictation.

This spec governs the path that begins with the microphone in HoldType
Keyboard. It supersedes conflicting requirements in older iOS specs and plans
that say the keyboard must not open HoldType, that the user must first start a
Keyboard Dictation Session manually, or that an extension restart always makes
automatic delivery ineligible.

The containing app's ordinary Voice experience remains governed by the iOS
release and voice specs. A keyboard handoff lands on that same first Voice
screen; it does not create a separate handoff screen.

## Product Decision

HoldType Keyboard is useful only if its microphone provides one coherent voice
flow comparable to Wispr Flow:

1. the user taps the existing keyboard microphone;
2. HoldType opens and starts app-owned recording for that explicit request;
3. the user returns to the host app;
4. the keyboard reconnects to the same request even if the extension was
   recreated;
5. the user finishes or cancels from the keyboard;
6. accepted text is delivered back to the originating document exactly once
   when that destination is still eligible.

The product does not ship a keyboard whose normal voice workflow requires the
user to open HoldType first and manually prepare a session. If this complete
flow cannot be approved or made reliable, HoldType may release as an app-only
product without the keyboard extension. App Review uncertainty must not be
resolved by silently degrading the keyboard into that manual-session design.

## User-Visible Flow

### Start

- The existing microphone button is the only primary voice action. There is no
  separate black button, Open HoldType button, or handoff button.
- Tapping the microphone creates a fresh dictation request and opens the
  containing app.
- The tap is an explicit user request to begin voice capture. HoldType starts
  real app-owned recording as soon as the request and current permissions allow.
- On first use, iOS may present microphone permission before recording begins.
  A denial produces a recoverable permission message; it never reports
  Listening.
- HoldType opens to the existing first Voice screen. That screen shows the
  current request and a short instruction to return to the host app. It is not
  replaced by a keyboard-specific screen.
- HoldType does not claim it can return to the host automatically. The user may
  need to swipe back or use the normal iOS app-switching gesture.

### Continue And Finish

- After the user returns, HoldType Keyboard reconnects to the active request.
  Reconnection does not depend on the same extension process remaining alive.
- The keyboard's existing voice/error area owns launch, permission, Listening,
  Processing, failure, expiry, and recovery messages. Identity or decorative
  areas do not duplicate these messages.
- While real capture is active, the same microphone action finishes dictation.
  Cancel remains a separate explicit action.
- Finish stops recording and starts the existing app-owned transcription and
  optional correction/translation pipeline.
- A fresh accepted result inserts automatically only when the current document
  still matches the request's originating document and delivery has not already
  been claimed.
- If safe automatic delivery is no longer possible, the result remains in
  Latest and the keyboard offers an explicit Insert recovery action. That is an
  exception path, not the normal workflow.

## State Contract

The keyboard may present these product states:

- `Ready`: tapping the microphone begins a new handoff;
- `Opening HoldType`: the handoff was requested but recording is not yet
  acknowledged;
- `Allow Microphone`: iOS permission is required or was denied;
- `Listening`: the containing app has acknowledged real capture;
- `Processing`: recording ended and accepted text is not ready yet;
- `Result ready`: safe automatic insertion is pending or explicit recovery is
  available;
- `Failed` or `Expired`: the request cannot continue and a new microphone tap
  starts a fresh request.

No surface may claim `Listening` before the containing app has started real
capture. Stale state from an earlier request must never make the current
microphone appear active.

## Request And Destination Identity

- Each microphone start creates a new opaque request identifier in the keyboard.
- The request records the originating `UITextDocumentProxy.documentIdentifier`
  when iOS provides one.
- The URL used to open HoldType carries only bounded opaque routing identity. It
  does not contain audio, transcript text, credentials, prompts, or host content.
- The containing app starts recording only when the URL matches a fresh shared
  request. An unrelated ordinary app launch does not start the microphone.
- A recreated keyboard extension may reconnect through the active request and
  originating document identity. Extension-process identity alone is not a
  valid ownership boundary.
- Missing or changed document identity makes automatic insertion ineligible; it
  does not discard the accepted result.

## Delivery Guarantees

- One accepted result may be inserted automatically at most once.
- Delivery eligibility requires the same request, a matching originating
  document, an unexpired result, and no prior insertion claim.
- The keyboard claims delivery before calling `insertText` so an extension
  recreation cannot replay the same accepted result.
- The containing app remains the canonical owner of Latest and any History
  entry. Shared state is transient coordination, not a second transcript store.
- An uncertain insertion is never retried automatically. The user recovers from
  Latest with an explicit Insert or Copy action.
- Cancelled, failed, expired, or superseded requests never insert text.

## Privacy And Permissions

- The keyboard extension never records audio and never links microphone or
  provider execution.
- The containing app owns microphone permission, audio capture, OpenAI access,
  and accepted-output persistence.
- Full Access may be required for shared coordination. Editing controls that do
  not need shared state remain useful when Full Access is off.
- Shared storage stays bounded and expiring. It contains request/state/result
  coordination only, never raw audio, API keys, provider payloads, prompts, or
  durable History.
- External transcription calls use the existing explicit timeout and failure
  rules. No error automatically resubmits user audio.

## Release Policy

- The complete keyboard flow must be proven on a signed physical iPhone. The
  Simulator cannot establish microphone ownership, app switching, extension
  recreation, or App Review acceptance.
- TestFlight and App Review are product gates, not reasons to pre-emptively
  remove the handoff.
- If Apple rejects the keyboard behavior and no compliant equivalent preserves
  this flow, the release fallback is an app-only build without the embedded
  keyboard extension, keyboard onboarding, or dead keyboard controls.
- HoldType does not ship a manual-session keyboard as the fallback.

## Acceptance Criteria

- Tapping the existing keyboard microphone opens HoldType and begins the same
  request without a separate preparatory session.
- The first Voice screen reflects the keyboard-originated recording without a
  new handoff destination.
- Returning to the host reconnects a recreated extension to the active request.
- Finish and Cancel from the keyboard control the app-owned recording.
- Accepted text inserts exactly once into the originating document when it is
  still eligible.
- Focus/document changes, stale requests, process loss, and uncertain delivery
  preserve Latest without automatic insertion into the wrong destination.
- Permission, offline, timeout, provider, expiry, and Full Access failures are
  shown in the existing voice/error area with a concrete recovery path.
- An app-only release can exclude the keyboard cleanly without weakening the
  standalone Voice experience.
