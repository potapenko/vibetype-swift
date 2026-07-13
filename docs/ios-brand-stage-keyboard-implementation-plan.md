# iOS Brand Stage Keyboard Implementation Record

Status: active completion record, updated 2026-07-14.

Product behavior is governed by `docs/specs/features/ios-v1-release.md` and
`docs/specs/features/ios-keyboard-experience.md`. This file records what is
implemented, what remains to be qualified, and why keyboard voice is still a
release no-go. It is not a backlog.

## Product Decision

The selected keyboard is Brand Stage Adaptive:

- no QWERTY, alphabet, number, prediction, or autocorrection engine;
- no transcript, History row, preview, or detail inside the keyboard;
- `History` is a navigation control for the containing app;
- `Latest` is the only text-bearing shared projection;
- the centered label is `Ready` or the brief failure `Open failed`;
- Light and Dark Mode keep identical geometry;
- the microphone remains non-interactive until a public, App-Review-compatible
  HoldType handoff exists.

The former plan for five recent results and an in-keyboard History panel is
retired. Schema 3 contains at most one Latest item.

## Platform Gate

The public production voice handoff is not qualified:

- custom keyboard extensions cannot access the microphone;
- Apple documents `NSExtensionContext.open` support on iOS for Today and
  iMessage extension points, not custom keyboards;
- App Review Guideline 4.4.1 says keyboard extensions must not launch apps
  other than Settings;
- there is no public host-identity or automatic-return contract.

A one-way custom URL may work on a particular OS build. That proves only
observed runtime behavior, not a supported API or App Review compliance. The
same rule applies to the requested History launch. Production uses no private
selector, responder-chain trampoline, host discovery, or fabricated recording
state.

## Implemented Surface

The Phase-0 probe has been replaced with:

1. Top rail: equal-width `History` and `Latest` controls around the centered
   transparent HoldType mark and compact status.
2. Voice stage: approximately 80-point branded microphone treatment and static
   waveform, disabled while the platform gate is unresolved.
3. Correction row: `.`, `,`, `?`, and `!`.
4. Editing row: conditional Globe, wide Space, Delete, and adaptive Return.

The surface includes:

- stable Light/Dark semantic colors and rounded keyboard top corners;
- minimum 44-point targets and VoiceOver labels;
- Dynamic Type-safe labels, Increase Contrast, and Reduce Transparency support;
- bounded iPad content width;
- no `A`, Refresh, giant Latest button, settings gear, or opaque mode icon.

## Editing Semantics

- Punctuation inserts one literal character per tap.
- Space tap inserts one space.
- Long-press and horizontal drag on Space adjusts the cursor and does not also
  insert a space.
- Delete fires on touch-down and repeats with bounded acceleration until every
  end or cancellation path stops it.
- Return derives its visible meaning from the host's public `UIReturnKeyType`.
- Globe uses the system input-mode API and is synchronized before first
  presentation as well as after host text changes.
- No host text or keystroke content is logged or persisted.

## Latest-Only Shared Boundary

The containing app is the only writer. The extension is read-only.

```text
schemaVersion = 3
revision
publishedAt
latest?
  resultID
  text
  createdAt
  expiresAt = createdAt + 10 minutes
```

Rules:

- publication is enabled in production and occurs from canonical Latest state;
- an already-expired result is omitted, republishing never extends expiry, and
  the open keyboard disables Latest when its published item expires;
- an unsafe current canonical Latest atomically clears older shared text rather
  than leaving it presented as current; a canonical-load failure preserves the
  bounded last-known cache until normal expiry;
- exact accepted text is preserved subject to bounded size and safe-control
  validation;
- schema 1/2 payloads are atomically replaced with an empty schema 3 cache;
- no History, recent-result array, prompt, credential, provider payload, audio,
  settings, host context, outbox, receipt, tombstone, or consumed-ID log enters
  the snapshot;
- `Latest` performs one `insertText` call for each explicit valid tap and never
  inserts on refresh, appearance, host change, or app return.

Apple permits read-only access to the containing app's shared containers in the
restricted keyboard sandbox. The extension therefore declares
`RequestsOpenAccess = false`, does not gate reading on `hasFullAccess`, performs
no network access, and never writes to App Group.

## History Boundary

The keyboard always renders the separate History control, but no History data
enters the extension. The containing app owns the strict `holdtype://history`
route and real History destination.

The keyboard currently uses only public `NSExtensionContext.open` for the
requested one-way launch and shows `Open failed` when the completion reports
failure. This implementation remains a technical probe and release gate because
Apple does not document it for keyboard extensions and Guideline 4.4.1 forbids
launching the containing app. No technical success may be recorded as public or
review-safe qualification.

## Verification

Automated evidence must cover:

- exact schema, size, expiry, legacy cutover, and increasing revision behavior;
- app publication and extension read-only insertion semantics;
- restricted `RequestsOpenAccess = false` metadata;
- cursor thresholds, Delete repeat bounds, Return presentation, and insertion
  event gating;
- strict containing-app History route parsing;
- iOS Debug/Release builds, macOS regression build, and diff hygiene.

Simulator evidence must cover:

- iPhone Light/Dark portrait and compact landscape;
- iPad Light/Dark bounded layout;
- punctuation, Space/cursor drag, Delete tap/hold, Return, Globe, and Latest;
- no automatic insertion, no transcript rendering, and concise status;
- accessibility labels and relevant appearance settings where exposed.

A signed physical iPhone remains required for matching App Group signing,
restricted-mode Latest reading, secure/phone-field fallback, host rejection,
process eviction, system Dictation behavior, Data Protection, and real-host
editing. A device may also record the History URL result, but it cannot override
the public-API and App Review no-go.

## Completion Dashboard

| Slice | Result |
| --- | --- |
| Contract and K1 evidence | Complete; production handoff is a documented no-go |
| Schema 3 Latest-only snapshot | Complete |
| Production publisher and app wiring | Complete in code; signed-device proof pending |
| Brand Stage UI and editing | Complete in code; iPhone Light/Dark and large-text runtime captured, remaining matrix pending |
| History app route | App-side complete; keyboard launch not release-qualified |
| Public HoldType microphone handoff | Not achievable under current Apple contract |
| Signed-device release evidence | Pending |

Engineering work may close the remaining runtime coverage, but the full
keyboard-plus-voice release cannot be called complete until the product is
explicitly rescoped, Apple changes the supported contract, or the review risk is
explicitly accepted.
