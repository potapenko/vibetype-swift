# HoldType Text Fixes Implementation Plan

Status: approved for implementation; Phase 0 in progress

Date: 2026-07-23

Implementation authorization: granted 2026-07-23

Current execution follows the active contract in
`docs/specs/features/text-fixes.md`.

## 1. Goal

Add a unified HoldType **Fixes** feature that applies a chosen text
transformation to the text currently being edited:

- use the non-empty selection when one exists;
- otherwise use the complete editable field or complete HoldType Voice Draft;
- replace only the captured target with the transformation result;
- expose the same action concept in:
  - the macOS app through a global `Option-J` shortcut and a popup near the
    active text field;
  - the iOS containing app's Voice panel;
  - the HoldType iOS keyboard extension.

The first two actions in the catalog are typed HoldType actions:

1. **Translate** — reuse the saved HoldType translation route and model.
2. **Fix** — reuse the saved HoldType writing-and-correction configuration.

Users can also create, edit, order, enable, hide, and remove custom prompt
actions. Additional default custom actions can provide a useful initial
catalog.

This file is an implementation plan, not an active product specification. It
must not be used to bypass the spec-first workflow.

## 2. Research Basis

### 2.1 Authoritative HoldType specs reviewed

The planning pass used these active specs as the current product contract:

- `docs/specs/README.md`
- `docs/specs/index.md`
- `docs/specs/features/global-hotkey.md`
- `docs/specs/features/text-output-workflow.md`
- `docs/specs/features/post-transcription-actions.md`
- `docs/specs/features/text-correction.md`
- `docs/specs/features/ios-v1-release.md`
- `docs/specs/features/ios-voice-draft.md`
- `docs/specs/features/ios-keyboard-experience.md`
- `docs/specs/features/ios-keyboard-handoff-and-delivery.md`

The current specs settle existing dictation, translation, correction, text
insertion, Quick Insert, keyboard privacy, and hotkey behavior. They do not
authorize:

- an arbitrary prompt-action catalog;
- reading and transforming selected host-app text;
- falling back from no selection to a complete external input;
- a global fixes palette;
- network-backed transformation from the keyboard extension;
- an action editor;
- replacement of only a selected Voice Draft range.

Several current non-goals explicitly exclude action editing and general
rewriting presets. The keyboard spec also intentionally leaves the center of
the Brand Stage unoccupied and excludes host text, prompts, and API
credentials from its current App Group contract.

### 2.2 FixKey reference inspected

The installed reference was FixKey 2.9.3 (build 91). The live app, status menu,
Prompt Editor, and the two supplied screenshots were inspected.

Observed Prompt Editor behavior:

- a searchable action list;
- an add action button;
- per-action title, prompt/description, and icon;
- save and delete operations;
- concise icon-and-title rows with a shortened prompt preview.

Observed actions included:

- Translate to English
- Fix Grammar
- Improve Writing
- Convert to Bullet Points
- Summarize
- Make Shorter
- Translate to Russian
- Translate to Serbian
- Change to Markdown
- Change to Casual
- Decline this Mail
- Write Alternatives
- Write TLDR
- Find Synonyms

The installed build currently advertises:

- `Option-J` for **Open prompt picker**;
- `Option-S` for **Fix current line**.

This matches the corrected HoldType shortcut requirement. HoldType should use
`Option-J` by default.

The installed FixKey commands were disabled in the observed runtime state, so
this research does not claim provider-result or replacement behavior that
could not be exercised. The editor, catalog, status-menu commands, and visible
interaction model were verified.

### 2.3 Current HoldType implementation seams inspected

Relevant current ownership includes:

- macOS focused-text inspection in `ActiveTextContextService`;
- macOS insertion in `TextInsertionService`;
- global hotkeys in `GlobalHotkeyService`,
  `CGEventGlobalHotkeyService`, and `SpecialClipboardHotkeyService`;
- macOS floating panel lifecycle in `FloatingIndicatorPanelController`;
- iOS Voice Draft presentation and ownership in
  `IOSVoiceDraftPresentation` and `IOSVoiceDraftTextActionOwner`;
- one-shot iOS actions in `IOSForegroundVoiceProcessor`;
- keyboard workspaces in `BrandStageKeyboardView`;
- keyboard command routing in `KeyboardCommandSurface`;
- Quick Insert catalog behavior in `KeyboardQuickInsertCatalog`;
- OpenAI translation and correction services in the package layer.

Important findings:

- The existing macOS focused-text service can read the focused AX element,
  value, and selected range, but its public result is designed for dictation
  context and does not retain enough target identity for a safe later
  replacement.
- The existing macOS insertion service inserts at the current focus. A fixes
  flow must capture and revalidate the original element and exact UTF-16 range
  before replacing anything.
- The existing correction service has transcript-specific output checks and is
  not a safe generic executor for actions such as Make Shorter or Summarize.
- The iOS Voice action owner already has useful single-action, stale-result,
  compare-and-swap, and Undo concepts, but it currently reserves and replaces
  the complete Draft.
- `UITextDocumentProxy.selectedText` makes selected-text transformation
  possible in compatible keyboard hosts.
- Public keyboard context before and after the cursor can be partial, absent,
  or host-dependent. It does not by itself prove that HoldType has the complete
  external input.

## 3. Required Spec Work

Before the first implementation edit:

1. Add one active umbrella spec for the Fixes catalog and shared transformation
   contract.
2. Update `global-hotkey.md` for `Option-J`, collision behavior, enablement,
   and palette lifecycle.
3. Update `post-transcription-actions.md` and `text-correction.md` to move
   one-shot Translate and Fix into the catalog without changing their typed
   semantics.
4. Update `ios-voice-draft.md` for selection-aware Draft transformations and
   Undo.
5. Update `ios-keyboard-experience.md` for the center Fixes control and the
   Fixes workspace.
6. Update `ios-keyboard-handoff-and-delivery.md` only after the keyboard
   provider and privacy architecture passes its feasibility gate.
7. Update privacy and consent language for any external host text sent to a
   remote provider.

The specs must settle the open product choices in Section 15. If a feasibility
spike disproves a desired behavior, update the contract before continuing.

## 4. Product Vocabulary

- **Fixes**: the feature and the catalog as a whole.
- **Fix**: one immediate action that transforms a captured text target.
- **Built-in Fix**: a typed HoldType action with stable behavior and routing.
- **Custom Fix**: a user-authored title, icon, and prompt.
- **Auto Translate / Auto Correct**: existing next-dictation modes. They remain
  separate from the immediate Fixes catalog.
- **Source snapshot**: exact source text, target identity, selection/range,
  revision or fingerprint, and capture time used to reject stale results.

## 5. Target Resolution Contract

The target must be resolved before opening UI that can steal focus.

| Surface | Non-empty selection | No selection | Unsupported or stale |
| --- | --- | --- | --- |
| macOS external field | Exact selected UTF-16 range | Complete value of the same AX text element | Fail closed without a provider request |
| iOS Voice Draft | Exact selected Draft range | Complete Draft | Leave Draft unchanged |
| iOS keyboard extension | `selectedText` when the host provides it | Complete field only when completeness and exact replacement can be proved | Do not transform partial context as if it were complete |

Common invariants:

- Empty source text does not start a request.
- Secure fields never expose or transform their content.
- The source snapshot is revalidated immediately before replacement.
- A changed element, document, source range, or Draft revision makes the result
  stale.
- A stale, cancelled, failed, empty, or invalid result leaves the source
  unchanged.
- At most one transformation is active on a surface at a time; requests are not
  queued.
- A successful replacement is one logical Undo operation where the host
  supports it.
- Immediate Fixes do not create dictation History or Usage entries.
- Source text, prompts, and provider output are excluded from normal logs.

### 5.1 macOS compatibility boundary

“Every input” means every compatible, non-secure text control exposed through
public macOS Accessibility APIs. Some custom-rendered editors, protected
fields, and controls with incomplete AX support cannot be guaranteed.

The UI must explain an unavailable action briefly; it must not silently target
the clipboard, the current line, or another application as a fallback.

### 5.2 Keyboard whole-input gate

No-selection keyboard behavior is a hard feasibility gate, not an
implementation detail.

The signed-device spike must prove all of the following in representative
hosts:

- the complete field can be distinguished from a truncated context window;
- the complete range can be replaced without damaging adjacent content;
- the document can be identified or fingerprinted well enough to reject stale
  results;
- focus and selection survive the provider round trip;
- secure and restricted hosts fail closed.

If public iOS APIs cannot prove this contract, production keyboard work stops
at the gate. The product contract must then explicitly choose selection-only
keyboard Fixes or another narrower behavior. Partial context must never be
presented as “the whole input.”

## 6. Catalog Contract

Use a stable, versioned domain model rather than storing view-specific rows.
A proposed action record contains:

- stable action ID;
- kind: typed Translate, typed Fix, or custom prompt;
- localized display title;
- icon token from a finite supported icon set;
- custom prompt where applicable;
- sort position;
- enabled/hidden state;
- schema version and migration metadata.

Recommended first-run order:

1. Translate
2. Fix
3. Improve Writing
4. Make Shorter
5. Summarize
6. Bullet Points
7. Change to Casual
8. Markdown

Translate and Fix should remain typed actions:

- Translate uses the saved translation language route and translation model.
- Fix uses the saved writing-and-correction model and prompt, even when
  automatic correction for dictation is off.
- Neither action is implemented as a duplicate free-form default prompt.

Typed actions can be reordered or hidden, but their semantic payload is edited
through the existing settings that own it. Custom actions can be created,
edited, reordered, hidden, and deleted.

**Restore Defaults** should restore missing default actions without deleting
custom actions. Catalog corruption or an unsupported schema must recover
safely without erasing recoverable user-authored prompts.

The first release should not promise cross-device or macOS-to-iOS catalog
sync. macOS and iOS may use the same schema and defaults while persisting
locally in their respective containers. Sync can be specified separately.

## 7. Surface UX

### 7.1 macOS global palette

Default invocation: `Option-J`.

The palette should:

- capture the external target before taking focus;
- appear near the AX caret or selected-text bounds and remain on-screen;
- show a searchable, keyboard-navigable list of icon-and-title rows;
- support arrow keys, Return, Escape, mouse selection, and click-outside
  dismissal;
- show compact progress, failure, unavailable, and stale-target states;
- dismiss after successful replacement;
- retain the original text and offer retry after a provider failure only while
  the snapshot is still valid.

The existing floating dictation indicator is a useful panel-lifecycle
reference but cannot be reused as-is: it is non-key, ignores the mouse, and is
anchored to a fixed screen location.

The menu-bar app should expose:

- **Fixes…** to open the palette for the last valid non-HoldType text target;
- **Edit Fixes…** to open the editor;
- shortcut status and conflict guidance.

Opening the menu or editor must not accidentally make a HoldType-owned field
the transformation target.

### 7.2 macOS Fix Editor

Use a normal app window, visually grounded in HoldType rather than cloning
FixKey:

- searchable action sidebar;
- add button;
- title field;
- multiline prompt editor;
- supported icon picker;
- enabled state;
- reorder;
- Save, Delete, and Restore Defaults;
- explicit validation for blank titles, blank prompts, duplicates, and size
  limits.

The editor is not part of the transient global palette.

### 7.3 iOS Voice panel

Replace the current top-level one-shot Translate and Correction affordances
with one **Fixes** launcher. The opened surface shows Translate and Fix first,
then the remaining catalog.

The existing Auto Translate and Auto Correct controls remain separate because
they configure the next dictation rather than transform the current Draft.

Behavior:

- use the non-empty `UITextView` selection, otherwise the complete Draft;
- keep the current single-active-action and stale-result protections;
- splice a result into the captured range instead of replacing unrelated Draft
  text;
- preserve one-step Undo;
- keep editing and recording lifecycle rules explicit;
- use Dynamic Type and VoiceOver labels for action title, progress, and error.

### 7.4 iOS keyboard workspace

Use the existing Brand Stage workspace pattern:

- place a Fixes button in the currently open center area of the top rail;
- make the touch target at least 44 points;
- swap the Voice workspace for a Fixes workspace, like Quick Insert;
- show compact tiles with a real icon and short title;
- use a scrollable one- or two-row layout for an unbounded catalog;
- make Quick Insert and Fixes mutually exclusive;
- include compact progress, failure, stale, and unavailable states;
- never show source text or provider output in logs or long-lived UI.

The spec must define whether Fixes is disabled or deferred while keyboard
dictation is active. The first implementation should favor an explicit
disabled state over interrupting or mixing two workflows.

## 8. Provider And Output Contract

Add a generic text-transformation operation instead of weakening the
transcript-specific correction safeguards.

The executor should accept:

- action identity and typed/custom action kind;
- exact source text;
- custom prompt or typed action route;
- cancellation;
- a bounded timeout;
- a request correlation token that contains no source content.

Common provider requirements:

- continue using `store: false`;
- keep an explicit external timeout;
- support cancellation and ignore late results;
- reject empty or structurally invalid output;
- keep verbose provider payloads behind opt-in debug logging;
- never log source text, custom prompts, or output by default;
- avoid recreating completed remote work when a safely reusable result exists.

The spec must explicitly settle whitespace handling. Generic trimming is risky:
leading indentation, trailing newlines, and whitespace around a selected range
may be meaningful. Model-result cleanup must be narrow, deterministic, and
covered by tests.

## 9. Persistence And Privacy Boundaries

### 9.1 macOS and iOS app

Persist catalog records through the repository's persistence layer with
versioned decoding and migrations. Persist prompts only in the app's private
container unless a later sync spec says otherwise.

### 9.2 Keyboard projection

The keyboard may receive the minimum catalog metadata it needs through the App
Group:

- action ID;
- display title;
- icon token;
- order;
- enabled state;
- action kind.

Do not copy the full custom prompt or API credential into the current shared
snapshot contract merely for convenience.

### 9.3 Keyboard provider architecture gate

Evaluate two bounded prototypes before choosing an architecture:

**A. Extension-local provider request**

- preserves host focus and selection;
- requires Full Access for networking;
- requires a deliberately shared credential mechanism, appropriate
  entitlements, package linkage, and revised consent/privacy behavior;
- must prove that credentials and prompts are not exposed through App Group
  files or logs.

**B. Containing-app processor with an ephemeral request/result bridge**

- preserves the existing app-owned credential boundary;
- needs request IDs, TTL, size limits, single-use claim, result
  acknowledgement, and exactly-once replacement;
- must prove the containing app can process while the external field remains
  the valid target;
- must fail closed when cold start, suspension, or app handoff destroys focus
  or selection.

The implementation must not select either architecture by assumption. Use a
signed physical-device spike and choose only an approach that satisfies target
continuity, credential safety, bounded latency, and the product's consent
contract.

## 10. Proposed Component Boundaries

Names are provisional; ownership matters more than exact filenames.

### 10.1 Shared package layer

- `TextFixAction` and catalog defaults in the domain package.
- `TextFixCatalogStore` protocol and versioned persistence implementation.
- `TextTransformationRequest`, result, and error types.
- `TextTransformationService` protocol.
- OpenAI generic transformation implementation with timeout and cancellation.
- Typed adapters that route Translate and Fix through existing settings.

Keep UI frameworks and AX/keyboard host types out of the shared domain model.

### 10.2 macOS

- `FocusedTextSnapshotService`
  - captures app PID/bundle ID, AX element identity, full text, selected UTF-16
    range, target scope, and anchor bounds;
  - rejects secure or unsupported controls.
- `FocusedTextReplacementService`
  - revalidates the target and captured source;
  - restores the exact range and performs one replacement;
  - reports unsupported Undo or host behavior instead of hiding it.
- `FixesHotkeyService`
  - owns `Option-J`, registration conflicts, enablement, and teardown.
- `FixesPalettePanelController`
  - owns palette window, positioning, keyboard/mouse interaction, and states.
- `FixesRuntime`
  - coordinates capture, action selection, request, revalidation, replacement,
    cancellation, and lifecycle.
- `FixesEditor`
  - owns catalog CRUD and validation in the normal app UI.

An early spike should compare AX value replacement with selection restoration
plus synthetic insertion in representative hosts. Choose the safest method
per proven compatibility and Undo behavior; do not assume one method works
universally.

### 10.3 iOS Voice

- expose the Draft editor selection as a UTF-16 range;
- extend the action owner to reserve `{revision, range, source fingerprint}`;
- commit by exact range splice after revalidation;
- generalize action presentation from two fixed buttons to the catalog;
- preserve the existing action cancellation and Undo ownership.

### 10.4 iOS keyboard

- project safe action metadata to the extension;
- add a Fixes command and workspace state to the command surface;
- add a document-target snapshot and stale-result guard;
- add the selected-text replacement path;
- add a whole-input path only after its gate passes;
- add the provider boundary selected by the physical-device spike;
- keep bridge state ephemeral, bounded, single-use, and observable without
  logging text.

## 11. Implementation Phases And Checkpoints

Each phase ends with updated specs or code, matching tests, scoped staging, and
a checkpoint commit on `master`. A failed gate stops later dependent phases.

### Phase 0 — Product contract

1. Write the umbrella Fixes spec.
2. Update the affected active specs listed in Section 3.
3. Resolve the open product choices in Section 15.
4. Define compatibility and privacy wording without promising unsupported
   platform behavior.

Exit: specs are active, indexed, internally consistent, and reviewed before
source edits.

### Phase 1 — Feasibility spikes

macOS spike:

- capture selected and complete values from representative AX controls;
- anchor a temporary panel to caret/selection bounds;
- register and suppress `Option-J` without breaking typing;
- replace exact ranges, test stale targets, and inspect Undo;
- document incompatible hosts.

iOS Voice spike:

- expose and preserve the Draft selection;
- validate Unicode-safe exact range splicing and stale edits.

iOS keyboard signed-device spike:

- exercise `selectedText`;
- test complete-context detection and exact whole-input replacement;
- test document changes, secure fields, extension recreation, and host
  variability;
- prototype both provider boundaries;
- determine Full Access, credential, consent, focus, and cold-start behavior.

Exit:

- macOS and Voice have a documented viable path;
- keyboard selected-text behavior is proven;
- keyboard whole-input and provider architecture receive explicit go/no-go
  decisions;
- specs are corrected if a desired contract is not feasible.

### Phase 2 — Shared foundation

1. Add the versioned action model and default catalog.
2. Add persistence and migrations.
3. Add typed Translate/Fix adapters.
4. Add the generic transformation service.
5. Add timeout, cancellation, validation, privacy, and corruption tests.

Exit: package tests prove catalog and provider behavior without any host UI.

### Phase 3 — macOS vertical slice

1. Implement `Option-J`.
2. Capture and retain the focused target.
3. Show a minimal native palette near the target.
4. Run one built-in and one custom action.
5. Revalidate and replace only the source range.
6. Handle unavailable, stale, cancelled, and failed states.

Exit: the complete path works in the agreed macOS compatibility matrix and
preserves unrelated text.

### Phase 4 — macOS catalog editor

1. Add the full editor and menu commands.
2. Add search, CRUD, order, icons, enabled state, and Restore Defaults.
3. Add validation, accessibility, and shortcut conflict guidance.

Exit: catalog changes persist and immediately drive the palette.

### Phase 5 — iOS Voice

1. Add range-aware action ownership.
2. Replace the two fixed one-shot controls with the Fixes launcher.
3. Preserve Auto Translate and Auto Correct as separate modes.
4. Add catalog presentation, progress, errors, and Undo.
5. Add selection, Unicode, stale-result, and accessibility coverage.

Exit: selected text or the complete Draft is transformed without overwriting
concurrent edits.

### Phase 6 — Keyboard service path

Proceed only with the architecture approved by Phase 1:

1. Project safe catalog metadata.
2. Add ephemeral source request/result transport if required.
3. Enforce TTL, size, consent, Full Access, cancellation, and exactly-once
   replacement.
4. Add stale-document and extension-recreation handling.
5. Keep all unsupported no-selection cases fail-closed.

Exit: selected-text transformation works end to end on a signed physical
iPhone without credential or text leakage.

### Phase 7 — Keyboard UX and qualified fallback

1. Add the center Fixes button and workspace.
2. Add dynamic tile layout, scrolling, progress, error, and disabled states.
3. Add the no-selection whole-input path only if Phase 1 proved it.
4. Qualify host behavior and publish the supported boundary in the spec.

Exit: the keyboard experience is usable, accessible, and honest about host
limitations.

### Phase 8 — Integrated qualification

1. Run package, macOS, iOS app, and keyboard regression suites.
2. Run the host compatibility matrices.
3. Audit normal and debug logs for text/prompt leakage.
4. Verify provider timeouts, cancellation, and late-result rejection.
5. Verify permissions, consent, accessibility, and migration behavior.
6. Update operator and release documentation.

Exit: all acceptance criteria pass with recorded evidence.

## 12. Verification Matrix

### 12.1 Domain, persistence, and provider

- first-run defaults and stable order;
- typed-action routing;
- custom CRUD, reorder, hide, delete, and Restore Defaults;
- schema migration, corrupt data, and unsupported version;
- prompt/title/icon validation and configured size limits;
- timeout, cancellation, offline, provider rejection, empty result, and late
  result;
- meaningful whitespace, Unicode, emoji, RTL, and multiline content;
- absence of source, prompt, and output in normal logs.

### 12.2 macOS

Hosts:

- TextEdit
- Notes
- Safari text field and textarea
- Chrome text field and textarea
- Xcode source editor
- at least one custom-rendered or unsupported control
- secure text field

Cases:

- selection at start, middle, and end;
- no selection with complete-field replacement;
- empty input;
- multiline and large bounded input;
- target edited while the provider is running;
- focus moved to another app;
- target window closed;
- shortcut conflict and keyboard layout variation;
- multiple monitors and screen-edge anchoring;
- Escape/click-outside cancellation;
- one-step Undo where supported.

### 12.3 iOS Voice

- selected range and complete Draft;
- selection containing composed Unicode;
- edit/revision change during request;
- action cancellation and one active action;
- one-step Undo;
- Translate/Fix typed routing;
- Auto mode independence;
- Dynamic Type and VoiceOver.

### 12.4 iOS keyboard

Use real host apps and a signed physical iPhone for the contract:

- selection in single-line and multiline hosts;
- no-selection complete-input proof or explicit refusal;
- partial or nil context;
- secure, phone, and restricted fields;
- document identifier/fingerprint change;
- cursor or text change during request;
- host app background/foreground changes;
- extension eviction and recreation;
- Full Access off and on;
- network timeout and cancellation;
- TTL expiry and exactly-once result claim;
- cold containing-app state if using a bridge;
- Voice/Fixes/Quick Insert workspace transitions;
- VoiceOver, compact width, and long catalog titles.

Simulator evidence may cover presentation and simulated extension interaction.
iPhone Mirroring may operate and observe only the containing app. A signed
physical iPhone is required for real keyboard-host, proxy, networking,
credential, focus, and handoff evidence.

### 12.5 Baseline commands

Select the exact schemes and destinations after each phase, but retain these
repository baselines:

```sh
swift test --package-path Packages/HoldTypeDomain
swift test --package-path Packages/HoldTypeOpenAI
swift test --package-path Packages/HoldTypePersistence
swift test --package-path Packages/HoldTypeIOSCore
xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination 'platform=macOS' build
xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination 'platform=macOS' test
git diff --check
```

Add the matching iOS app, keyboard extension, unit, and UI test invocations
after confirming their live schemes and destinations.

Before any UI automation:

- start a scoped `caffeinate` guard;
- use the sanitized Keychain launch route;
- do not use live provider credentials unless the user explicitly asks for a
  live debug session;
- stop the guard after the UI session.

## 13. Acceptance Criteria

The feature is complete only when:

- `Option-J` opens a responsive native palette for a compatible macOS text
  target;
- a selection is transformed without changing surrounding text;
- no-selection macOS behavior transforms only the complete compatible field;
- stale or unsupported macOS targets are left unchanged;
- users can manage and persist custom Fixes;
- Translate and Fix are first-class typed defaults using existing settings;
- the iOS Voice panel transforms a selection or complete Draft with Undo;
- the keyboard transforms selected text on a signed physical iPhone;
- keyboard no-selection behavior either passes the complete-input contract or
  is explicitly narrowed by the active spec;
- source text, prompts, output, and credentials do not leak into normal logs or
  an unintended shared container;
- external requests time out and late results cannot overwrite newer text;
- all changed behavior is represented in active specs and verification
  artifacts.

## 14. First-Release Non-Goals

- chaining multiple Fixes in one request;
- background batch rewriting;
- automatic Fixes on every input change;
- clipboard-only fallback for unsupported controls;
- silently treating the current line as the complete input;
- cloud or macOS-to-iOS catalog sync;
- importing FixKey data;
- arbitrary per-action provider credentials or models;
- using immediate Fixes as dictation History or Usage events;
- promising compatibility with secure or inaccessible custom controls;
- storing external host text for later processing.

## 15. Phase 0 Product Decisions

1. If complete no-selection input cannot be proved in the iOS keyboard,
   keyboard Fixes ships selection-only; macOS and iOS Voice remain unaffected.
2. Built-in Translate and Fix stay pinned first and cannot be deleted.
3. The initial eight-action catalog is the recommendation in Section 6; the six
   custom defaults are editable.
4. Custom Fixes initially use the saved Writing & Correction model.
5. macOS and iOS catalogs remain intentionally separate in version one.
6. Titles are limited to 80 user-perceived characters, prompts to 8 KiB UTF-8,
   and one source to 32 KiB UTF-8.
7. Keyboard Fixes use the containing app's provider through a 60-second
   bounded App Group request/result bridge. Credentials and custom prompts stay
   app-private.
8. Custom output is inserted exactly as returned. Empty or whitespace-only
   output is invalid; HoldType performs no generic trimming or normalization.

## 16. Working-Tree Coordination

At the time of research, unrelated edits were already present in:

- `HoldTypeIOSTests/KeyboardCommandSurfaceIOSTests.swift`
- `HoldTypeKeyboard/KeyboardCommandSurface.swift`
- `HoldTypeKeyboard/KeyboardQuickInsertCatalog.swift`
- `docs/specs/features/ios-keyboard-experience.md`
- `docs/specs/features/ios-keyboard-handoff-and-delivery.md`

Those edits belong to other work and must remain untouched. Before phases that
need the same paths, inspect the current diff, work from the live contents, and
stage only phase-owned changes. Dirty Git state is not a blocker.
