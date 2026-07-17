# iOS Keyboard Handoff And Delivery

Status: active canonical contract for keyboard-originated dictation.

This spec governs the path that begins with the microphone in HoldType
Keyboard. It supersedes conflicting requirements in older iOS specs and plans
that say the keyboard must not open HoldType or that the user must first start
a Keyboard Dictation Session manually.

The containing app's ordinary Voice experience remains governed by the iOS
release and voice specs. A keyboard handoff lands on that same first Voice
screen and may present a temporary handoff sheet over it. The sheet is not a
new tab or navigation destination, and keyboard handoff must not add states,
copy, recovery cards, draft mutations, or routing rules to ordinary Voice.
Keyboard status and recovery presentation belong to the temporary sheet and
the keyboard's existing voice/error area.

## Product Decision

HoldType Keyboard is useful only if its microphone provides one coherent voice
flow comparable to Wispr Flow:

1. the user taps the existing keyboard microphone;
2. HoldType opens and starts app-owned recording for that explicit request;
3. the user returns to the host app;
4. the keyboard reconnects to the same request even if the extension was
   recreated;
5. the user finishes or cancels from the keyboard;
6. accepted text may cause one automatic insertion invocation only while the
   originating keyboard controller is active and visible and can still prove
   the same destination.

A recreated extension may reconnect request control, but it never inherits
automatic-delivery eligibility from the controller that originated the
request. Request ownership and destination eligibility are independent
capabilities.

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
- A valid handoff does not change the containing app's selected destination or
  mutate ordinary Voice. HoldType presents a large temporary sheet over the
  current app shell. The sheet may report
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
  capture, dismisses the sheet, and leaves the underlying app destination
  unchanged. Interactive
  sheet dismissal is unavailable while capture is active so it cannot be
  confused with the system return gesture.
- Closing, failing, expiring, interrupting, or superseding a keyboard handoff
  must not leave keyboard-originated text or local-recovery presentation on the
  ordinary Voice screen. Any keyboard-owned cleanup stays inside the handoff
  subsystem; genuine ordinary Voice recovery remains unchanged.
- If setup is incomplete, HoldType does not start capture. The temporary
  handoff sheet presents the concrete setup blocker and stays independently
  dismissible; it does not navigate, mutate, or add recovery presentation to
  ordinary Voice. A completed repair does not replay the request; the user
  returns to the host and taps the keyboard microphone again.
- A pre-start unavailable or idle-session-expired request may dismiss the
  handoff sheet and return the keyboard to its microphone action. Once a
  non-empty recording exists, failure never makes it disappear: the sheet shows
  that the recording was saved and exposes Play plus Transcribe/Retry or
  Delete. The same saved recording is visible from containing-app History even
  when the completed source could not yet commit its Pending promotion.
- A completed source that has never become Pending is `Ready to Transcribe`,
  not a failed provider attempt. It becomes `Retry` only after a canonical
  Pending/provider attempt fails; unavailable source metadata is blocked.
- Transcribe/Retry from either Saved Recording surface is one explicit user
  action: HoldType expectation-binds the exact completed source, commits it as
  failed Pending when needed, then enters the existing exactly-once provider
  retry path. A failed promotion leaves the same playable source visible. The
  handoff sheet runs this through the keyboard-owned workflow action and never
  mutates ordinary Voice presentation.
- A fresh keyboard microphone tap may supersede a pre-start, cancelled, or
  empty prior request. It must not delete or replace a prior request whose
  completed audio is Pending, Processing, or recoverably failed. That saved
  recording remains the sole recovery owner until provider success or explicit
  Delete, and the new tap reports the existing recovery instead of starting a
  second capture. Accepted text already committed to Latest or History is
  always preserved.
- Listening is not a supersession boundary. If a fresh handoff arrives while
  the prior attempt is actively Listening, HoldType keeps that exact session,
  attempt, and recording, re-presents its Listening sheet, and does not run
  setup preflight, start another capture, or retire the active audio.
- History and the handoff sheet share one process-owned Saved Recording state.
  If its local read cannot confirm either the recording or its absence, both
  surfaces show a blocked Saved Recording with Retry Refresh. The handoff does
  not continue admission or dismiss recovery until a successful read confirms
  absence.
- While that keyboard-only cleanup is finishing, the new handoff sheet remains
  visible in Starting and retries admission silently. A transient stale-session
  conflict must not dismiss the sheet or expose the unchanged Voice screen.
- A fresh microphone tap from a different host app or input follows the same
  ownership rule. It may silently supersede a pre-start or empty capture, but it
  must reveal rather than replace completed audio that is Pending, Processing,
  or recoverably failed. After that saved recording succeeds or is explicitly
  deleted, a later tap may start a request for the current document.
- HoldType does not claim it can return to the host automatically. The user may
  need to swipe back or use the normal iOS app-switching gesture.
- If the user taps keyboard Translate while its saved route is incomplete, the
  same bounded launch mechanism opens HoldType at the exact owning Translation
  input. No dictation request or provider work starts for that tap.

### Continue And Finish

- After the user returns, HoldType Keyboard reconnects to the active request.
  Reconnection does not depend on the same extension process remaining alive.
- After successful delivery, the unexpired app-owned session remains ready for
  another keyboard dictation. The next microphone tap starts recording on its
  first tap without reopening HoldType or requiring another return swipe.
- During that bounded warm session, the containing app keeps a live microphone
  input pipeline so iOS does not tear down background capture between distinct
  dictations. Session stop, cancellation, expiry, or replacement releases that
  pipeline and clears the system microphone indicator.
- The warm-session lifetime is 60 seconds only while the session is idle in
  `Ready`. Entering `Listening` cancels that idle expiry; capture then has its
  independent user-selected recording limit. That limit is frozen at Start;
  it is 1-15 minutes and defaults to five. Entering `Processing` closes microphone input
  and uses only the provider's own bounded timeout. An old warm-session timer
  must never stop capture or cancel provider work.
- The keyboard's existing voice/error area owns launch, permission, Listening,
  Processing, failure, expiry, and recovery messages. Identity or decorative
  areas do not duplicate these messages.
- Opening, Starting, Listening, Processing, failure, and recovery never disable
  or dismiss keyboard-local Quick Insert or next-request Auto selection. These
  utilities do not alter the active request or its microphone lifecycle.
- Each request freezes its automatic-mode selection when Start creates the
  attempt. Auto changes made after that boundary apply only to the next request.
- While real capture is active, the same microphone action finishes dictation.
  The keyboard workspace has no separate Cancel control beside the centered
  activity indicator. Before returning to the host, the sheet's close action
  remains the explicit cancellation path.
- Finish stops recording and starts the existing app-owned transcription and
  optional correction/translation pipeline.
- If capture reaches its selected limit first, HoldType performs the same Finish
  automatically, saves Pending audio before provider work, and shows
  `Processing — recording limit reached; audio saved`. The user does not need to keep the
  extension alive for this finalization.
- A fresh accepted result may invoke automatic insertion only while the same
  live keyboard controller that created the request is currently active and
  visible, still owns it, the request has a non-empty immutable source document
  identifier, the current proxy has the same non-empty identifier, eligibility
  has never been invalidated, and the exact delivery claim is granted.
- If safe automatic delivery is no longer possible, the result remains in
  canonical Latest. While the bounded transient result is still available, the
  keyboard's existing Latest action gives that result priority and inserts it
  only after an explicit tap into the then-current input. That is an exception
  path, not the normal workflow, and it produces no host-change warning.

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
- `Saved recording`: completed audio is locally protected and can be played,
  transcribed/retried, or explicitly deleted;
- `Failed` or `Expired`: the request cannot continue and a new microphone tap
  starts a fresh request after retiring the previous keyboard attempt.

No surface may claim `Listening` before the containing app has started real
capture. Stale state from an earlier request must never make the current
microphone appear active.

## Request And Destination Identity

- A session identifier names one bounded, app-owned warm bridge lifetime.
- That session's idle Ready lifetime is independent from the active attempt's
  Listening deadline, provider timeout, and result-delivery lifetime.
- An attempt identifier names one recorder and provider execution inside that
  session.
- Each keyboard microphone tap creates a new opaque request identifier.
- The originating live controller freezes the request's
  `UITextDocumentProxy.documentIdentifier` when iOS provides one. That source
  identifier is immutable for the attempt.
- The URL used to open HoldType carries only bounded opaque routing identity. It
  does not contain audio, transcript text, credentials, prompts, or host content.
- The containing app starts recording only when the URL matches a fresh shared
  request. An unrelated ordinary app launch does not start the microphone.
- A recreated keyboard extension reconnects control only when the session,
  attempt, and request match both shared state and the last app-consumed
  keyboard handoff. That evidence restores Listening, Processing, Finish, and
  Cancel ownership only; it never proves an insertion destination.
- Automatic delivery remains eligible only in the originating live controller
  while that controller is currently active and visible, and only while the
  current non-empty identifier exactly equals the immutable non-empty source
  identifier. A hidden controller may observe shared state but cannot claim or
  consume delivery.
- UIKit may issue a different identifier after returning to the same visible
  field. The extension cannot distinguish that case from a different field or
  host app, so a returned identifier never becomes a replacement anchor.
- A missing source identifier, a non-empty mismatch, controller recreation, or
  any previously observed destination change permanently invalidates automatic
  delivery for that request. Returning from `A -> B -> A` does not restore it.
- A temporarily missing current identifier never hides Listening or prevents
  Finish. The originating controller may repeat that local read for a short
  bounded interval while the result remains fresh, but any identifier that
  appears must still equal the frozen source. Two missing values are never a
  match.
- Loss of delivery eligibility is silent and independent from capture control.
  The accepted result remains in canonical Latest and may be inserted into the
  then-current input only by an explicit user action.

## Delivery Guarantees

- One accepted result may cause at most one automatic `insertText` invocation.
- Delivery eligibility requires the originating controller to be currently
  active and visible, its exact active request, an unexpired result, an exact
  non-empty source/current document match, no prior disqualification, and no
  prior insertion invocation.
- The keyboard writes a fresh opaque delivery-claim identifier and waits for
  the containing app to grant that exact claim before calling `insertText`.
- The controller rechecks eligibility after the grant and invokes `insertText`
  on the same proxy instance whose document identifier passed that final gate.
- A recreated extension does not inherit another process's granted claim, so
  an uncertain insertion is never replayed.
- A matching acknowledgement means only that one granted claim was consumed by
  one `insertText` invocation. It does not prove that the host accepted or
  visibly rendered the text. `insertText` return and text-change callbacks are
  diagnostic observations, not delivery receipts.
- That claim-consumption acknowledgement retires only the completed attempt and
  returns an unexpired app-owned session to Ready.
- An expiry callback owns only the snapshot that scheduled it. Before clearing
  attempt ownership it reloads the canonical bridge slot; a newer same-attempt
  Processing, Result, Failed, or Unavailable record is handled exactly once,
  even when its Darwin notification arrives late. It clears only when the
  canonical snapshot is still the expired one.
- The containing app remains the canonical owner of Latest and any History
  entry. Shared state is transient coordination, not a second transcript store.
- An uncertain insertion is never retried automatically. The user recovers from
  Latest with an explicit Insert or Copy action.
- Cancelled, failed, expired, or superseded requests never insert text. A
  provider operation already started from protected Pending audio remains
  authoritative even if the idle warm session later expires.

## Privacy And Permissions

- The keyboard extension never records audio and never links microphone or
  provider execution.
- The containing app owns microphone permission, audio capture, OpenAI access,
  and accepted-output persistence.
- Keyboard handoff may reuse lower-level recorder, permission, provider, and
  accepted-output services, but it must not extend or repurpose the ordinary
  Voice controller, scene owner, presentation model, or recovery UI.
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
- The selected containing-app destination remains unchanged and the temporary
  handoff sheet reflects Starting, Listening, Processing, and concrete
  pre-start blockers without duplicating or mutating Voice. A completed audio
  failure remains as an explicit saved-recording recovery instead of silently
  dismissing.
- Returning to the host reconnects a recreated extension to the active request.
- Quick Insert and Auto remain enabled throughout the handoff, and shared-state
  refreshes do not dismiss either already-open local surface.
- Finish from the keyboard and Cancel from the handoff sheet control the same
  app-owned recording.
- Accepted text causes at most one automatic insertion invocation, only from
  the currently active and visible originating controller with an exact
  non-empty source/current document match.
- A recreated extension may reconnect and finish the exact capture, but it
  cannot automatically insert that capture's result.
- Repeated microphone taps within the same healthy warm session start distinct
  dictation attempts without another containing-app handoff.
- Ready expires after 60 idle seconds, while Listening continues to its own
  selected automatic Finish and Processing continues to its own timeout.
- Limit-ended Finish preserves one playable Pending recording and starts
  provider work once; a later provider failure leaves Play and Retry/Delete.
- Focus/document changes, stale requests, process loss, and uncertain delivery
  preserve Latest without automatic insertion into the wrong destination.
- Permission and setup failures discovered while HoldType is foreground are
  shown in the handoff sheet. Runtime failures after return are shown in the
  keyboard's existing voice/error area. Neither path adds recovery state to
  ordinary Voice.
- Incomplete Translation setup leaves keyboard Translate actionable and routes
  to field-level Translation guidance instead of silently ignoring the tap.
- An app-only release can exclude the keyboard cleanly without weakening the
  standalone Voice experience.
