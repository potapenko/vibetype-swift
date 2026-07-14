# iOS Flat History QA

Date: 2026-07-14

Scope: containing-app History list, clipboard copy, swipe deletion, optional
Recording Cache playback, and playback-to-Voice handoff.

## Result

History is now one flat list of complete transcript text. It has no result
detail route, date, time, Share action, explanatory footer, or second tap before
Copy. When the independently configured Recording Cache contains the exact
accepted recording, Play appears immediately before Copy.

Management actions remain available in the trailing ellipsis menu, while row
deletion uses the standard trailing swipe action.

## Visual Evidence

The previous screen exposed policy, dates, disclosure chevrons, a second result
screen, Clear All, and explanatory copy directly in the primary flow:

![Previous History](assets/ios-brand-stage-keyboard-2026-07-13/history-route.png)

The current real SwiftUI History screen was rendered on iPhone 16, iOS 18.6,
with the same populated state in both appearances:

| Light | Dark |
| --- | --- |
| [Screenshot](assets/ios-history-flat-2026-07-14/iphone-light.png) | [Screenshot](assets/ios-history-flat-2026-07-14/iphone-dark.png) |

The captures confirm full text in each row, Play before Copy on the eligible
row, Copy on every row, and no visible metadata or disclosure chevrons.

## Interaction Evidence

An XCUITest launched the sanitized History qualification state and verified:

- the exact full text is visible without opening another screen;
- one Copy tap followed by Simulator pasteboard inspection returns the exact
  selected string;
- tapping transcript text leaves the `History` navigation title and row actions
  in place;
- no Share action exists;
- a trailing swipe exposes Delete and removes only the selected row;
- the eligible row exposes Play while rows without cached audio do not.

The interaction test passed on iPhone 16, iOS 18.6 Simulator. No Keychain
prompt, microphone capture, or provider request was used.

## Automated Evidence

- Full `HoldType-iOS` Simulator run: 1,044 passed, 0 failed, 0 skipped.
- Full `HoldTypePersistence` package run: 198 passed, 0 failed.
- Focused History UI/composition/qualification run: passed.
- Ad hoc real-screen clipboard/navigation/swipe XCUITest: passed.
- Generic iOS Simulator Release build: passed.
- macOS app build: passed.
- `git diff --check`: passed.

Persistence tests cover cache-off, bounded and unlimited retention, exact
`resultID` lookup, idempotent recovery, managed-only pruning, and isolation of
optional cache failures from accepted dictation cleanup. iOS tests cover the
conditional Play boundary and the process-owned playback-to-recording handoff.
