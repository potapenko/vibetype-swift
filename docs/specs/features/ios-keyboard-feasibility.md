# iOS Keyboard Feasibility

## Goal

Preserve the future v2 iOS keyboard feasibility decision without making iOS
implementation part of the current macOS MVP.

The active product phase is the native macOS menu bar app. iOS companion,
simulator, and keyboard-extension work must remain deferred unless a direct user
request or explicitly v2-labeled task opts into deferred iOS lanes.

## Scope

This spec covers:

- iOS custom keyboard constraints that affect dictation
- the containing-app versus keyboard-extension product split
- Open Access, network, microphone, secure-field, and next-keyboard behavior
- what shared SwiftUI surfaces may be reused from the macOS app
- the constraint that normal macOS MVP implementation should not select iOS
  work

## Non-goals

- implementing any iOS work before the macOS MVP is usable
- implementing a keyboard extension
- implementing iOS recording, transcription, or storage
- replacing the native iOS system dictation experience

## Evidence

- Apple App Extension Programming Guide: Custom Keyboard, reviewed 2026-06-20:
  `https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html`
- Apple Platform Security: Supporting extensions, reviewed 2026-06-20:
  `https://support.apple.com/guide/security/supporting-extensions-secabd3504cd/web`
- Apple Developer: Configuring open access for a custom keyboard, reviewed
  2026-06-20:
  `https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard`

## Feasibility Decision

For a future v2, an iOS VibeType keyboard is feasible as a text insertion
surface, not as the component that records microphone audio or talks directly
to OpenAI.

The future v2 iOS split is:

- Containing app:
  - onboarding and privacy disclosure
  - OpenAI API key setup and storage
  - settings
  - microphone permission, recording, and transcription
  - accepted transcript state and optional local history
  - any network request to OpenAI
- Keyboard extension:
  - compact keyboard UI
  - required next-keyboard control
  - insertion of an accepted transcript into the current text input object
  - limited setup or unavailable states

The keyboard extension must not capture microphone audio, stream live dictation,
or send audio, transcript text, API keys, keystrokes, or prompts to OpenAI in
the MVP.

## User-Visible Behavior

- The keyboard must always provide a way to switch to the next keyboard.
- If there is no accepted transcript available, the keyboard should show a
  compact empty or setup-needed state without blocking keyboard switching.
- The keyboard is not available in secure text fields, passcode entry, and
  some phone-pad contexts. The system may temporarily replace it with the
  system keyboard.
- Host apps may reject third-party keyboards. VibeType must treat this as a
  platform limitation, not as a failed dictation session.
- The containing app must explain when Open Access is needed before directing
  the user to enable the keyboard.
- The keyboard must not prompt for long setup, credentials, or permissions
  inline. Complex setup belongs in the containing app.

## Keyboard Voice Session Contract

The keyboard-visible session states are:

- setup needed, when containing-app setup, Open Access, an accepted transcript,
  or the host text-input context is unavailable;
- idle, with an optional accepted transcript ready for insertion;
- launching session, while the keyboard asks the containing app to start the
  voice flow;
- listening, while the containing app owns microphone capture;
- transcribing, while the containing app owns provider work;
- confirming, when returned text is ready for the user to accept or cancel;
- accepted transcript, when accepted text can be inserted into the host field;
- error, without clearing the previous accepted transcript;
- compact settings, for inline keyboard options and a deep link back to the
  containing app.

Starting from an unavailable state must not launch recording or provider work.
It should leave the keyboard in setup-needed state and offer the shortest path
back to containing-app setup.

Canceling a launch, listening, transcribing, confirming, error, or compact
settings state returns to idle without deleting the last accepted transcript.
Accepting text stores only the normalized accepted transcript needed for
insertion. Empty or whitespace-only returned text becomes an error state and is
not inserted.

Inline keyboard settings are intentionally compact. Deep setup, credentials,
microphone consent, Open Access explanation, transcription settings, and history
management remain containing-app responsibilities.

## Existing Exploratory Containing App Target

The repository already contains an exploratory minimal iOS containing app
target. It is not the current product target and must not steer normal
implementer work away from the macOS menu bar MVP.

Until future v2 iOS implementation tasks add real features, this target must:

- identify itself as VibeType;
- state that keyboard setup, recording, transcription, and text insertion are
  not enabled yet;
- use only shared, platform-neutral SwiftUI setup/status components when code is
  intentionally shared with macOS;
- avoid microphone capture, network calls, Open Access setup, shared
  containers, keyboard extension code, and transcript persistence;
- stay independent from macOS menu bar, AppKit Settings-window, global-hotkey,
  floating-indicator, and Accessibility paste code.

## Open Access And Shared State

By default, an iOS custom keyboard runs in a restrictive sandbox. A useful
VibeType dictation keyboard likely needs Open Access so it can read accepted
transcript state or shared settings produced by the containing app.

Open Access does not change the MVP privacy boundary:

- OpenAI network requests stay in the containing app.
- The API key stays in the containing app's secret-storage boundary.
- The keyboard extension reads only the minimum accepted transcript state
  needed for insertion.
- The keyboard must not log raw dictated text by default.
- If Open Access is disabled, the keyboard should fall back to a limited state
  instead of pretending dictation insertion is available.

## Microphone And Network Constraints

The iOS keyboard extension must not be designed around direct microphone
capture. If the product needs recording on iOS, the containing app owns the
recording flow and user consent.

The keyboard extension must not call OpenAI for MVP transcription. Keeping
provider calls in the containing app preserves the existing Keychain, timeout,
error mapping, and no-live-provider-test contracts.

## Shared SwiftUI Reuse

Shared SwiftUI is allowed only where the product behavior is common and the UI
fits both platforms.

Reusable candidates:

- settings rows for model, language, prompt, and history preferences
- privacy disclosure copy
- transcript history list rows
- small status components that do not depend on AppKit or macOS menu-bar APIs

Not reusable for the iOS keyboard:

- macOS `MenuBarExtra` structure
- AppKit Settings-window plumbing
- global hotkey UI
- macOS floating indicator
- macOS Accessibility paste handoff
- full-size macOS settings layouts inside the keyboard extension

Future shared code should be introduced only after an iOS target exists and a
task verifies the shared surface on both macOS and iOS.

The initial reusable setup/status surface may be shared between the iOS
containing app and the macOS Settings window when it remains platform-neutral.
Shared setup UI must describe current product availability honestly and must
not expose controls for unavailable recording, transcription, keyboard
extension, Open Access, or paste behavior.

## Verification Mapping

- This spec-only task requires `git diff --check`.
- Future v2 iOS target work should use XcodeBuildMCP or the Build iOS Apps flow
  for simulator build, test, screenshot, or UI snapshot evidence only when a
  direct user request or v2-specific selector run includes deferred iOS lanes.
- Keyboard session state model work should use pure Swift tests for start,
  cancel, accept, error, settings, and unavailable paths.
- Future keyboard tests should cover next-keyboard availability, no-transcript
  state, Open Access disabled state, and transcript insertion through a fake or
  controlled text-input boundary.
- Future containing-app tests should keep recording, transcription, Keychain,
  and network behavior fake-backed and bounded.

## Invariants

- No hidden or background recording.
- No direct OpenAI call from the keyboard extension in the MVP.
- No API key storage inside the keyboard extension.
- No reliance on keyboard availability in secure or host-rejected fields.
- No new iOS target, keyboard extension, or iOS product behavior should be
  added before a task or direct user request explicitly selects v2 work.
- The iOS containing app target must remain a safe setup/status surface until a
  future v2 spec adds real iOS dictation or keyboard behavior.
