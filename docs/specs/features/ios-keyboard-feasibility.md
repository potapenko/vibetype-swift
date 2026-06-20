# iOS Keyboard Feasibility

## Goal

Decide whether an iOS VibeType keyboard is feasible before adding an iOS
target or keyboard extension.

## Scope

This spec covers:

- iOS custom keyboard constraints that affect dictation
- the containing-app versus keyboard-extension product split
- Open Access, network, microphone, secure-field, and next-keyboard behavior
- what shared SwiftUI surfaces may be reused from the macOS app

## Non-goals

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

An iOS VibeType keyboard is feasible as a text insertion surface, not as the
component that records microphone audio or talks directly to OpenAI.

The MVP iOS split is:

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

## Initial Containing App Target

The first iOS containing app target may launch as a minimal setup/status
surface before keyboard or dictation behavior exists.

Until future iOS implementation tasks add real features, this target must:

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
- Future iOS target work should use XcodeBuildMCP or the Build iOS Apps flow
  for simulator build, test, screenshot, or UI snapshot evidence.
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
- No iOS target should be added before a task or direct user request explicitly
  selects that work.
- The iOS containing app target must remain a safe setup/status surface until a
  future spec adds real iOS dictation or keyboard behavior.
