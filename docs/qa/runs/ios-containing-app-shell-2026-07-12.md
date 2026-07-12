# iOS Containing-App Shell QA

Date: 2026-07-12
Milestone: P3.2 native iPhone and iPad shell

## Scope

- Replace the probe-only containing-app root with four stable destinations:
  Voice, Library, History, and Settings.
- Use independent tab navigation on iPhone and a native sidebar/detail split on
  iPad, with scene-local top-level restoration and safe compact re-entry.
- Install the exact process-owned Settings and Library owners at the SwiftUI
  root without fallback repositories or whole-composition environment access.
- Keep passive launch and destination appearance free of microphone requests,
  Keychain reads, provider work, and App Group writes.
- Present only behavior that exists in this checkpoint: setup guidance,
  practice text, one explicit fixed-sample bridge test, truthful saved Settings
  and Library summaries, and honest unavailable Voice/History states.

## Automated Evidence

- Focused shell and composition suites
  - Result: 10 passed in 2 suites; result bundle
    `/tmp/holdtype-p32-shell-focused2.xcresult`.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS -destination
  'platform=iOS Simulator,name=iPhone 16,OS=18.6' test`
  - Result: 1,318 passed in 137 suites, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p32-final3-ios.xcresult`.
- `xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination
  'platform=macOS' test`
  - Result: 441 passed, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p32-final-mac.xcresult`.
- Release Xcode builds for `HoldType-iOS` on the generic iOS Simulator and
  `HoldType` on macOS
  - Result: passed. The first concurrent macOS attempt encountered only the
    shared DerivedData build-database lock; the required sequential rerun
    passed.
- `otool -L`, `nm -gU`, and `strings` on the release simulator keyboard
  executable
  - Result: only system frameworks are linked. No Domain, Persistence, IOSCore,
    OpenAI, Settings, Library, containing-app, Keychain, or state-owner symbol
    or string entered the extension.
- `git diff --check`
  - Result: passed.

No verification command contacted OpenAI, loaded a live API key, requested
microphone permission, or used a live credential provider.

## Navigation And Ownership Evidence

- iPhone 16 on iOS 18.6 presents Voice, Library, History, and Settings in fixed
  order. Every tab owns its own `NavigationStack`; Voice is the invalid-value
  fallback.
- iPad Pro 11-inch presents the same destinations in a system
  `NavigationSplitView`. Expanded selection, system-collapsed sidebar behavior,
  Back-to-sidebar, and same-row re-entry preserve the last valid stored
  destination without forcing a nonoptional transient selection.
- `@SceneStorage` persists only the raw top-level destination. It never stores
  a draft, row payload, credential state, or unstable detail path.
- The root presents the normal shell only when both concrete process owners
  exist, then injects those exact nonoptional identities. A canonical storage
  root failure replaces the shell with one blocking local-storage-unavailable
  surface and does not synthesize defaults.
- Settings and Library load only when their destination appears. An unreadable
  record stays a local load failure with Retry through the same owner; a failed
  save shows the last durable value.

## Runtime And Visual Evidence

- XcodeBuildMCP built, installed, and launched the current shell on iPhone and
  iPad. All four destinations were opened. Settings and Library completed their
  lazy loads, History made no claim that an unread canonical store was empty,
  and Voice remained provider- and microphone-passive.
- The Voice practice field accepted and cleared text. The explicit
  `Publish Keyboard Test Sample` action published only its fixed local string,
  displayed the ten-minute expiry status, and announced the result for
  VoiceOver. Passive appearance did not publish anything.
- iPad `accessibility-large` Dynamic Type stacked labeled values, preserved
  sidebar labels, and kept every section reachable by scrolling. iPhone dark
  appearance and an accessibility text size used native colors and retained
  readable, scrollable content. Both simulators were returned to normal text
  size; iPhone was returned to light appearance.
- Final app and OS logs for both simulator runs contained no error, fault,
  crash, assertion, or fatal entry.
- Product Design exploration produced three independent directions. The
  selected `Guided Utility` reference was compared side by side with the real
  iPhone Voice screen at the same aspect ratio. The implementation preserves
  its native grouped hierarchy, setup order, practice field, and four-tab
  structure while deliberately omitting the reference's fake completion,
  inert chevrons, custom OpenAI logo, and Start action that belongs to P4.

## Truthful State And Privacy Evidence

- Provider-coordinator availability crosses the root only as one payload-free
  available/unavailable value. Unavailability is not presented as a missing
  key; availability still does not claim that a key is present or accepted.
- Settings labels current values as saved configuration or preferences. Custom
  transcription language distinguishes automatic fallback, invalid setup, and
  a normalized valid code. Translation says `Configured` or `Needs setup`, not
  that an unavailable Voice action is ready.
- Library labels saved counts and selected emoji preference without implying
  that future editors or voice capture are active.
- The practice publisher contains no credential, prompt, user Library content,
  or user transcript. Settings and Library remain app-private and are not
  copied into the extension or App Group.
- Independent architecture, UX/accessibility, and security reviews found no
  remaining P1/P2 issue after transient split selection, truthful provider and
  History copy, Dynamic Type retry feedback, and VoiceOver publication status
  were corrected.

## Assessment

P3.2 passed. The app now has a native, truthful, adaptive shell grounded in the
approved design direction and exact composition ownership. The next P3
checkpoint can add the P4-owned Settings and Library editors without changing
navigation ownership or weakening keyboard isolation.
