# Text Fixes

Status: active product contract.

## Goal

Let a person transform text already being edited by choosing a reusable
HoldType Fix. The action applies to the non-empty selection when one exists
and otherwise to the complete compatible field or HoldType Voice Draft.

The same catalog concept is available in the macOS app, iOS Voice, and
HoldType Keyboard while each platform keeps an honest compatibility boundary.

## Scope

- built-in Translate and Fix actions
- user-authored prompt actions
- local catalog editing and persistence
- macOS `Option-J` palette behavior
- selection and complete-field target rules
- iOS Voice and keyboard presentation
- remote processing, privacy, failure, and stale-target behavior

## Non-goals

- automatic rewriting while the user types
- chained or batch actions
- cloud or cross-platform catalog sync
- clipboard fallback for an inaccessible target
- replacing text in secure fields
- importing another product's catalog
- per-action credentials or provider selection
- adding immediate Fixes to dictation History or Usage

## Catalog

- **Fixes** is the feature and catalog name. One catalog item is a **Fix**.
- The first two actions are always:
  1. `Translate`, using the saved HoldType Translation route and model;
  2. `Fix`, forcing the saved Writing & Correction model and prompt for this
     request without changing the durable automatic-correction preference.
- Translate and Fix are typed actions. They cannot be deleted or converted into
  arbitrary prompts.
- New catalogs also include editable prompt actions for Improve Writing, Make
  Shorter, Summarize, Bullet Points, Change to Casual, and Markdown.
- A custom Fix has one stable identifier, title, supported icon, prompt,
  enabled state, and user-defined position after the two built-ins.
- A title is required and limited to 80 user-perceived characters.
- A custom prompt is required and limited to 8 KiB of UTF-8.
- The icon comes from a finite HoldType-supported SF Symbols set so every
  surface can render the same semantic icon safely.
- Users can add, edit, reorder, enable, disable, and delete custom Fixes.
- Restore Defaults recreates missing default custom actions without deleting
  or changing other custom actions.
- Catalogs are local and separate on macOS and iOS in the first release.
- Corrupt or unsupported catalog data is preserved and reported. HoldType does
  not overwrite it with defaults while reporting a successful load.

## Target Selection

- The target is captured before a palette, menu, or app transition can move
  focus.
- A non-empty selection is the source and replacement range.
- With no selection:
  - macOS uses the complete value of the same compatible Accessibility text
    element;
  - iOS Voice uses the complete confirmed Draft;
  - HoldType Keyboard uses the complete host field only after public API
    evidence proves both complete traversal and exact replacement.
- A visually blank source is unavailable and starts no provider request.
- The source is limited to 32 KiB of UTF-8 for one Fix request. A larger target
  remains unchanged and shows a concise size-limit failure.
- macOS support means compatible non-secure text controls exposed through
  public Accessibility APIs. Custom-rendered, protected, or incomplete
  controls may be unavailable.
- Keyboard selection support uses the host-provided selected text. The
  no-selection path is a signed-device release gate. A partial or uncertain
  context is never presented or processed as the complete input.

## Processing And Replacement

- Only one immediate Fix may be active on a surface. Further taps are ignored;
  actions are not queued.
- The request freezes the action, exact source, target identity, and target
  revision or fingerprint.
- Custom Fixes use the saved Writing & Correction model with their own prompt.
  They do not inherit transcript-correction length-ratio safety rules.
- Every remote request uses the current app-owned OpenAI credential, current
  provider consent, `store: false`, explicit cancellation, and a 20-second
  maximum wait.
- Custom Fix output is used exactly as returned. HoldType does not trim,
  normalize typography, strip Markdown, or rewrite meaningful whitespace.
  Empty or whitespace-only output is invalid.
- Translate and Fix retain their existing typed output normalization and
  failure semantics.
- Immediately before replacement, HoldType revalidates the same target,
  document, source range, and source text.
- A changed, missing, unsupported, or stale target rejects the result and
  leaves current text unchanged.
- A successful action replaces only the captured range and creates one logical
  Undo mutation where the host supports it.
- Cancellation, timeout, provider failure, invalid output, persistence failure,
  and stale results leave source text unchanged.
- Successful immediate Fixes do not mutate Latest, Pending, History, Recording
  Cache, or Usage.

## macOS

- `Option-J` is the default global Fixes shortcut.
- The shortcut captures the current external text target before opening UI.
- A compact searchable palette opens near the caret or selected-text bounds,
  clamped to the visible screen.
- Arrow keys move selection; Return runs the selected Fix; Escape and
  click-outside dismiss without changing text.
- The palette shows icon, short title, progress, unavailable, failure, and
  stale-target states without showing provider payloads.
- Successful replacement dismisses the palette. A failed request may be
  retried only while the original target snapshot still validates.
- If `Option-J` cannot be registered, HoldType keeps dictation and menu
  controls available and reports the Fixes shortcut as unavailable.
- The menu bar exposes `Fixes…` and `Edit Fixes…`. Opening a HoldType-owned
  editor never changes the captured external target.
- The Fixes editor is a normal native window with search, Add, title, prompt,
  icon, enabled state, reorder, Delete, and Restore Defaults.

## iOS Voice

- The former separate one-shot Translate and Correction controls become one
  `Fixes` launcher in the Draft action area.
- The Fixes surface shows Translate and Fix first, followed by enabled custom
  actions.
- A non-empty Draft selection is transformed; otherwise the complete confirmed
  Draft is transformed.
- Editing is committed before the snapshot is reserved. Recording, starting,
  finalizing, processing, or another Fix makes immediate Fixes unavailable.
- A result is spliced into the exact reserved range after Draft revision and
  source validation.
- A successful replacement creates one app-level Undo mutation and clears Redo.
- Auto Translate and Auto Correction remain next-dictation modes in the
  separate Auto menu and do not select or run an immediate Fix.
- The iOS containing app exposes a native Fixes editor from Library. Full
  prompts remain app-private.

## iOS Keyboard

- The center of the top rail contains a 44-point Fixes control.
- Activating it replaces the Voice workspace with a scrollable Fixes workspace
  using icon-and-title tiles. A close action restores the current Voice state.
- Quick Insert and Fixes are mutually exclusive. Voice state refreshes update
  underneath without dismissing the open Fixes workspace.
- Fixes remains visible but unavailable while a keyboard dictation request is
  Starting, Listening, or Processing.
- The extension receives only bounded action metadata: identifier, kind,
  title, icon, order, and enabled state. Custom prompts and credentials remain
  app-private.
- The extension sends one bounded, expiring immediate-Fix request containing
  request identity, action identity, source text, source kind, document
  identity, and source fingerprint. It never sends surrounding text that is
  outside the chosen source.
- The containing app resolves the action and prompt, checks consent and
  credential, performs the provider request, and publishes one bounded result.
- Source and result bridge records expire after 60 seconds and are replaced
  atomically. They are transient coordination, not History or a replay queue.
- Before replacement, the active visible controller must still own the exact
  request, document, source selection or complete-field traversal, and source
  fingerprint.
- A result causes at most one replacement invocation. Uncertain replacement is
  never retried automatically.
- Full Access is required for the app-mediated Fixes bridge. With Full Access
  off, local editing and Quick Insert remain available and Fixes explains the
  requirement without fabricating processing.
- Secure fields, phone pads, host opt-out, partial context, oversized targets,
  and unprovable complete fields fail closed.

## Privacy And Data

- Settings disclose that running a Fix sends the selected text or complete
  compatible field plus the chosen instruction to OpenAI.
- The keyboard consent copy explains that a user-invoked Fix sends only its
  chosen source through transient App Group coordination to the containing app.
- API keys never enter the catalog, App Group, keyboard extension, logs, or
  diagnostics.
- Full custom prompts remain in app-private or macOS-local catalog storage.
- Source text and results are current-request-only. They are removed on
  acknowledgement, cancellation, terminal failure, or expiry.
- Default product logs contain action identifiers and closed outcome
  categories only. They contain no source, result, prompt, field context, API
  key, or provider body.
- No action performs a remote request until current provider consent and a
  credential are available.

## Invariants

- Immediate Fixes never overwrite text outside the captured target.
- A stale or uncertain target is never replaced.
- A partial keyboard context is never treated as the complete field.
- A Fix request never starts recording or changes an active dictation request.
- The keyboard extension never reads Keychain or contacts OpenAI.
- External operations have explicit bounded timeouts and real cancellation.
- Normal automated tests use fakes and never contact live OpenAI.

## Failure Policy

- Missing permission, consent, credential, Full Access, or Translation route
  produces a concise actionable blocked state and no provider request.
- Provider, timeout, cancellation, invalid-output, and local-save failures
  preserve the source.
- If a catalog cannot be loaded, existing text surfaces remain usable and
  Fixes shows a local unavailable state.
- If an iOS bridge write or read fails, canonical app-private catalog data
  remains unchanged.
- Process or extension restart never replays or applies an old Fix result.

## Route / State / Data Implications

- macOS persists one versioned local Fixes catalog and shortcut registration
  status.
- iOS persists one versioned app-private Fixes catalog.
- iOS publishes one replaceable metadata snapshot plus one replaceable
  immediate-request/result record family to the existing App Group boundary.
- The keyboard bridge has one extension writer for requests and one containing
  app writer for results, with opaque IDs, revision, expiry, and no append-only
  log.
- The iOS app processes keyboard Fixes through the existing bounded app-owned
  handoff runtime; it does not share its Keychain item or provider client.

## Verification Mapping

- Domain and persistence tests cover defaults, CRUD, ordering, validation,
  corruption, migration, Restore Defaults, byte bounds, and redaction.
- Provider tests cover exact prompt/source projection, typed action routing,
  exact custom output, timeout, cancellation, empty output, late response, and
  no live calls.
- macOS tests and runtime QA cover shortcut registration, AX selection and
  complete-field capture, stale targets, palette interaction, replacement,
  Undo, multiple monitors, secure fields, and representative host apps.
- iOS Voice tests cover Unicode selections, complete Draft, stale edits,
  single-action ownership, exact range splice, and Undo.
- Keyboard tests cover metadata projection, selected text, complete-field
  traversal gate, document changes, Full Access, expiry, exactly-once
  replacement, extension recreation, secure/restricted hosts, and no leakage.
- Simulator proves presentation and extension integration. A signed physical
  iPhone is required for host-field traversal, focus continuity, Full Access,
  background app processing, and real replacement qualification.

## Release Gate

Keyboard Fixes may ship for selected text after the signed-device path proves
target continuity and app-mediated processing. No-selection keyboard Fixes may
ship only after the same device matrix proves complete traversal and exact
replacement in supported hosts. Failure of the second gate narrows keyboard
Fixes to selection-only; it does not block macOS or iOS Voice.
