# iOS Library Foundation And Dictionary QA

Date: 2026-07-12
Milestone: P3.5A app-private Library transaction foundation and Dictionary

## Scope

- Freeze the iOS Library editor contract for Dictionary, Voice Emoji Commands,
  and Replacement Rules before exposing content mutations.
- Add typed Library mutations that run against the process owner's latest
  durable value and distinguish committed, unchanged, duplicate, missing,
  conflict, and invalid outcomes without unnecessary repository writes.
- Add the first native Library content route: a searchable Dictionary list with
  batch Add, case-insensitive deduplication, exact semantic deletion, explicit
  destructive confirmation, and scene-local dirty-navigation protection.
- Keep every Library value in the containing app's protected private storage.
  Do not publish content, routes, drafts, catalogs, or mutation state to the App
  Group or keyboard extension.
- Close the save/load structural-limit asymmetry so every successfully encoded
  Library value is also accepted by the bounded structural decode gate.

## Automated Evidence

- Focused Library mutation, owner, privacy, route, and shell run
  - Result: 16 passed, 0 failed, 0 skipped on iPhone 16 / iOS 18.1; result
    bundle `/tmp/holdtype-p35a-focused-final.xcresult`.
- Full signed simulator regression for `HoldType-iOS`
  - Result: 1,372 passed, 0 failed, 0 skipped on iPhone 16 / iOS 18.1; result
    bundle `/tmp/holdtype-p35a-full-ios-signed.xcresult`.
- Full macOS regression for `HoldType`
  - Result: 441 passed, 0 failed, 0 skipped; result bundle
    `/tmp/holdtype-p35a-full-mac.xcresult`.
- Focused package tests
  - The 65,536-member Library save/load structural boundary passes and the
    65,537-member value fails before replacement.
  - Spoken-phrase normalization uses the exact punctuation, case, and diacritic
    tokenization used by runtime emoji replacement.
- Sequential Release builds for `HoldType-iOS` and `HoldType`
  - Both succeeded. iOS reported zero warnings and zero errors. macOS reported
    its existing 44 warnings and zero errors. Result bundles are
    `/tmp/holdtype-p35a-ios-release.xcresult` and
    `/tmp/holdtype-p35a-mac-release.xcresult`.
- Release keyboard executable inspection with `otool -L`, `nm -gU` plus Swift
  demangling, `strings`, and bundle inventory
  - The extension links only its existing system/runtime boundary. No Domain,
    Persistence, IOSCore, OpenAI, Library repository, mutation, Dictionary,
    custom emoji, replacement-rule, repository-path, or runtime canary symbol,
    string, framework, JSON, fixture, or resource entered the extension.
- `git diff --check`
  - Result: passed.

The first unsigned full simulator run intentionally could not satisfy the
existing hosted-app access-group assertion because code signing was disabled.
The canonical signed run above passed that assertion and every other test.
No verification contacted OpenAI, used a real API key, requested microphone
access, read or wrote Keychain items, or touched the clipboard.

## Durable Ownership And Concurrency

- `IOSLibraryStateOwner.apply` serializes one typed operation against its latest
  durable Library value. It commits only a `committed` outcome and publishes the
  repository's exact canonical response before the next FIFO operation starts.
- Non-commit outcomes perform no repository replacement. A failed commit
  restores observable state to the exact last durable Library while the
  originating view keeps its memory-only draft for retry.
- Dictionary rows retain the existing ordered-string schema. Add and remove use
  trim-plus-lowercase semantic identity; deletion also requires the exact
  expected displayed spelling. Filtered indexes and newly invented UUIDs are
  never used.
- Concurrent scene adds merge against current truth. A stale missing or changed
  delete fails closed and cannot remove a different row.
- The same foundation already freezes UUID/full-row CAS for future custom emoji
  and replacement editors, Boolean CAS for row toggles, and complete-sequence
  CAS for future replacement reorder.
- New custom/custom spoken-phrase collisions are invalid. Readable legacy
  collisions remain visible and are not silently removed or made unreadable.

## Runtime Evidence

- XcodeBuildMCP built, installed, launched, and exercised the app with
  `HOLDTYPE_AUTOMATION=1` on iPhone and iPad. The existing automation credential
  boundary remained active, so runtime QA did not access live Keychain state.
- iPad split flow:
  - Library opened Dictionary through a value-based shell-owned navigation path.
  - `Alpha, Beta, alpha, Gamma` committed three rows and reported one duplicate.
  - Force stop and relaunch preserved the exact three-row durable result.
  - Searching `Beta`, invoking the row context action, and confirming deletion
    removed only `Beta`; clearing search still showed `Alpha` and `Gamma`.
  - A dirty sidebar destination request kept the Dictionary draft behind the
    global confirmation; confirmed discard cleared only the Library path and
    entered the requested destination.
- iPhone tab flow:
  - A dirty History-tab request exposed both Keep Editing and confirmed discard.
  - Keep Editing retained the exact draft and route.
  - Local Cancel, confirmed local discard, and a subsequent History selection
    navigated immediately without a second top-level prompt.
- Native grouped-list geometry, compact tab navigation, regular split
  navigation, wrapping text, list spacing, destructive confirmations, and the
  selected visual reference were inspected together. No cropped controls,
  broken margins, or non-native replacement chrome remained.

## Storage, Privacy, And Accessibility

- A real Dictionary mutation was bracketed by App Group inventory and SHA-256
  checks. Before and after, the only file was the same container metadata plist
  with hash
  `2c258323910d44b1569b9cf91b9e5bdf4eb1fbeca214e65638200050311c2071`;
  no shared Library file or content appeared.
- The canonical `ios-library.json` was present only beneath the containing
  app's private `Library/Application Support/HoldType` directory.
- The runtime canary `LIBRARY-GROUP-BOUNDARY-CANARY`, earlier Dictionary rows,
  and the discarded iPhone draft did not appear in captured app or OS logs.
- Draft, search, semantic reference, action, receipt, completion, and notice
  reflection surfaces are redacted. Navigation values and accessibility
  identifiers contain only app-owned enum values or UUIDs, never user text.
- Visible fields and rows remain normally available to VoiceOver. Notices and
  announcements expose only content-free action and count summaries.
- Dictionary CRUD performs no provider, microphone, Keychain, clipboard, or
  keyboard operation.

## Review Assessment

Architecture, privacy, and UX reviews were repeated after compilation and
runtime fixes. The navigation destination modifier now lives outside the
Library load/save state branch, so a `ready` to `saveFailed` publication cannot
recreate the active editor and erase its retained draft. The spec also records
that spoken-phrase collision prevention is a typed editor-mutation invariant,
not an unsafe unversioned migration of readable legacy rows.

## Assessment

P3.5A passes. HoldType now has one durable, typed, multi-scene Library mutation
boundary and a complete native Dictionary editor on iPhone and iPad. Voice
Emoji Commands and Replacement Rules remain intentionally summarized rather
than exposed as inert routes; they are the next two P3 checkpoints.
