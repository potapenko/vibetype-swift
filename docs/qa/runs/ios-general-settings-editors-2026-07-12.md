# iOS General Settings Editors QA

Date: 2026-07-12
Milestone: P3.4 native containing-app general Settings editors

## Scope

- Add native `Form` routes for Transcription, Writing & Correction,
  Translation, and Voice & Recording.
- Expose only the existing app-private Settings v1 fields needed by the P4
  app-only flow. Keep keyboard, Quick Session, History, recording-cache,
  automatic-insertion, Nearby Text, and macOS-only controls absent.
- Use explicit scene-local drafts and Save actions while committing only one
  semantic Settings group through the exact process-owned state owner.
- Preserve failed and concurrently superseded drafts as visibly unsaved,
  without logging or announcing prompt or model content.
- Guard dirty-editor Back, Cancel, iPhone-tab, and iPad-sidebar replacement.
  Provide dedicated searchable language selection and content-free
  accessibility feedback.

## Automated Evidence

- Focused editor, state-owner, and shell run
  - Result: 30 passed, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p34-editor-support6.xcresult`.
- Full signed simulator regression for `HoldType-iOS`
  - Result: 1,359 passed, 0 failed, 0 skipped on iPhone 16 / iOS 18.6; result
    bundle `/tmp/holdtype-p34-postfix-ios.xcresult`.
- Full macOS regression for `HoldType`
  - Result: 441 passed, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p34-postfix-mac.xcresult`.
- Sequential Release builds for `HoldType-iOS` on iOS Simulator and `HoldType`
  on macOS
  - Result: passed. Existing project warnings remain recorded by the build;
    this iOS-only slice introduced no build error. iOS reported zero build
    issues; macOS reported its existing 44 warnings and no error. Result
    bundles are `/tmp/holdtype-p34-postfix-ios-release.xcresult` and
    `/tmp/holdtype-p34-postfix-mac-release.xcresult`; the macOS product is
    `/tmp/holdtype-p34-postfix-mac-dd/Build/Products/Release/HoldType.app`.
- Release keyboard executable inspection with `otool -L`, `nm -gU`, and
  `strings`
  - Result: only the keyboard's existing system/runtime boundary is linked.
    No Domain, Persistence, IOSCore, OpenAI, Keychain, containing-app owner,
    Settings editor, route, prompt, model, or language-selection dependency,
    symbol, or string entered the extension.
- `git diff --check`
  - Result: passed.

No verification command contacted OpenAI, used a real API key, requested the
microphone, or performed a Keychain item operation.

## Draft, Ownership, And Concurrency

- Every editor initializes one memory-only draft from its current durable
  semantic group. The draft is neither a repository nor durable navigation
  state, and it performs no work until explicit Save.
- Saves use the exact composition-owned `IOSAppSettingsStateOwner`. Each
  mutation applies only the edited semantic group to the owner's latest
  durable value, preserving unrelated settings and the deferred Keep Latest
  preference.
- A clean editor adopts newer durable truth. A dirty editor retains its draft
  and shows `Changed Elsewhere`. Failed persistence retains the draft as `Not
  Saved` while shared state remains the last durable value.
- An older successful caller cannot overwrite a newer same-group publication
  that reached the owner before the caller resumed. Tests cover both scenes
  sharing the exact owner, FIFO publication, unrelated-group preservation,
  initial reconciliation, failure/retry, and same-group supersession.

## Navigation And Runtime Evidence

- XcodeBuildMCP built, installed, and exercised the containing app with
  `HOLDTYPE_AUTOMATION=1`, so live Keychain access was disabled before
  composition construction.
- iPhone light, dark, and accessibility-extra-extra-extra-large layouts and
  iPad split layouts were inspected. Summaries wrap, forms remain scrollable,
  and the persistent bottom failure/change status stays available while lower
  content is edited.
- A real iPad sidebar probe caught and drove a navigation fix: a system
  selection transaction could previously pop the nested editor before the
  discard decision. The final shell owns the Settings value path and routes
  sidebar activation through explicit rows.
- Final iPad runtime checks verified that a dirty destination attempt leaves
  the exact editor and draft visible; Escape/Keep Editing retains both;
  confirmed discard clears the Settings path and enters the requested
  destination; tapping the already-selected Settings row does not pop; and a
  clean destination switch remains immediate.
- A Debug-only automation layout override then exercised the same split shell
  at iPhone compact width. Back exposed only the sidebar; tapping the already
  selected Voice row returned to its exact detail through the shell-owned
  preferred compact column, so the collapsed split cannot trap navigation.
- Local Cancel → Discard was followed immediately by a top-level Voice
  selection. It navigated without a second prompt, confirming that editor
  discard clears the shell dirty flag synchronously before dismissal.
- The language route presents a searchable native list. Searching `Custom`
  reduced the list to the explicit Custom row without changing durable state.
  The simulator was left with the documented default transcription settings.

## Validation, Accessibility, And Privacy

- Blank model fields visibly use their documented default without exposing the
  resolved identifier in summaries or status text. Model identifiers appear
  only in their explicit editor fields.
- Empty Custom language visibly falls back to Auto. Invalid non-empty codes
  disable Save and show an associated hint. VoiceOver announces only recovery
  from invalid to valid, without reading the code or interrupting ordinary
  keyboard echo after the first character.
- Correction and Translation prompts remain editable while their remote stage
  is off. Reset restores the exact standard prompt in the draft and announces
  that it remains unsaved without reading prompt content.
- Save failure and concurrent-change phases appear both in the form and in a
  persistent bottom status, with content-free VoiceOver announcements. Warning
  text keeps semantic primary/secondary contrast while color is reserved for
  the icon accent.
- Reflection, descriptions, notices, announcements, and runtime-log canaries
  contain no prompt or model content. The deliberately non-secret runtime
  model canary did not appear in the app or OS log.
- Keep Latest Result remains deliberately absent until accepted-output,
  bridge-revocation, and History cleanup can change with it atomically.

## Review Assessment

Architecture, privacy, and UX/accessibility reviews were repeated after fixes
for same-group save ordering, initial durable reconciliation, model-summary
redaction, persistent warnings, language validation and Reset announcements,
searchable language selection, and iPad dirty-navigation lifetime. No
unresolved P1/P2 finding is accepted into the next P3 checkpoint.

## Assessment

P3.4 passes. The containing app now exposes the complete non-secret general
Settings subset needed by P4 with native iPhone/iPad editing, explicit durable
commits, multi-scene truth, conservative failure handling, content-free
accessibility status, and unchanged keyboard-extension isolation. The next P3
checkpoint is the app-private Library editor foundation and its Dictionary,
Voice Emoji Commands, and Replacement Rules routes.
