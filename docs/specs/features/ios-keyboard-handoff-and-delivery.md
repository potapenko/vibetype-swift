# iOS Keyboard Handoff And Delivery

Status: active canonical contract for keyboard-originated dictation.

This spec governs the path that begins with the microphone in HoldType
Keyboard. It supersedes conflicting requirements in older iOS specs and plans
that say the keyboard must not open HoldType, that the user must first start a
Keyboard Dictation Session manually, or that an extension restart always makes
automatic delivery ineligible.

The containing app's ordinary Voice experience remains governed by the iOS
release and voice specs. A keyboard handoff lands on that same first Voice
screen and may present a temporary handoff sheet over it. The sheet is not a
new tab, navigation destination, or second Voice implementation.

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
- HoldType opens to the existing first Voice screen. A valid handoff presents a
  large temporary sheet over that unchanged screen. The sheet may report
  `Starting` while app-owned capture is arming, but it reports `Listening` only
  after real capture begins.
- Once Listening, the sheet places the return affordance at the physical bottom
  edge, directly above the system home indicator. A compact swipe track contains
  sequential right-pointing chevrons and a short `Swipe right to return` label;
  the user must not need to read body copy to discover where the gesture starts.
  No supporting copy appears below the track or lifts it away from the bottom
  gesture region.
  It contains no second Start button.
- The sheet's explicit close action cancels the keyboard request, stops active
  capture, dismisses the sheet, and leaves ordinary Voice Ready. Interactive
  sheet dismissal is unavailable while capture is active so it cannot be
  confused with the system return gesture.
- If setup is incomplete, HoldType does not start capture or present the
  handoff sheet. It opens the exact owning Settings or permission surface. A
  completed repair does not replay the request; the user returns to the host
  and taps the keyboard microphone again.
- HoldType does not claim it can return to the host automatically. The user may
  need to swipe back or use the normal iOS app-switching gesture.
- If the user taps keyboard Translate while its saved route is incomplete, the
  same bounded launch mechanism opens HoldType at the exact owning Translation
  input. No dictation request or provider work starts for that tap.

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

- A session identifier names one bounded, app-owned warm bridge lifetime.
- An attempt identifier names one recorder and provider execution inside that
  session.
- Each keyboard microphone tap creates a new opaque request identifier.
- The request records the originating `UITextDocumentProxy.documentIdentifier`
  when iOS provides one.
- The URL used to open HoldType carries only bounded opaque routing identity. It
  does not contain audio, transcript text, credentials, prompts, or host content.
- The containing app starts recording only when the URL matches a fresh shared
  request. An unrelated ordinary app launch does not start the microphone.
- A recreated keyboard extension reconnects control only when the session,
  attempt, and request match both shared state and the last app-consumed
  keyboard handoff. Extension-process identity is never a valid ownership
  boundary.
- Originating document identity is a separate delivery gate. A matching value
  permits automatic insertion; a missing or changed value never prevents the
  user from seeing Listening or finishing the matching capture, but it makes
  automatic insertion ineligible and preserves the accepted result in Latest.

## Delivery Guarantees

- One accepted result may be inserted automatically at most once.
- Delivery eligibility requires the same request, a matching originating
  document, an unexpired result, and no prior insertion claim.
- The keyboard writes a fresh opaque delivery-claim identifier and waits for
  the containing app to grant that exact claim before calling `insertText`.
- A recreated extension does not inherit another process's granted claim, so
  an uncertain insertion is never replayed.
- A matching post-insertion acknowledgement retires only the completed attempt
  and returns an unexpired app-owned session to Ready.
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
- Existing containing-app session controls may remain temporarily as a bounded
  qualification diagnostic. They are not the production keyboard entry point
  and do not change the microphone-first contract.

## Acceptance Criteria

- Tapping the existing keyboard microphone opens HoldType and begins the same
  request without a separate preparatory session.
- The first Voice screen remains the underlying destination and the temporary
  handoff sheet reflects Starting and Listening without duplicating Voice.
- Returning to the host reconnects a recreated extension to the active request.
- Finish and Cancel from the keyboard control the app-owned recording.
- Accepted text inserts exactly once into the originating document when it is
  still eligible.
- Focus/document changes, stale requests, process loss, and uncertain delivery
  preserve Latest without automatic insertion into the wrong destination.
- Permission, offline, timeout, provider, expiry, and Full Access failures are
  shown in the existing voice/error area with a concrete recovery path.
- Incomplete Translation setup leaves keyboard Translate actionable and routes
  to field-level Translation guidance instead of silently ignoring the tap.
- An app-only release can exclude the keyboard cleanly without weakening the
  standalone Voice experience.
