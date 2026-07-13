# iOS Keyboard Settings Snapshot

Status: deferred historical typing-preference contract. V1.1 Brand Stage uses
bundled presentation and editing defaults and does not implement this snapshot.
The schema below is retained as research only and does not authorize layout,
autocorrection, prediction, automatic-insertion, or translation controls in the
extension.

## Goal

Record the former proposal for a non-secret immutable typing-preference snapshot
without exposing the containing app's canonical settings or user content
repositories.

## Ownership

- The containing app is the only writer.
- The extension is policy-level read-only even when Full Access is enabled.
- The snapshot is a separate atomically replaced App Group file, not the voice
  session record, command channel, acknowledgement channel, or event bus.
- Writing a snapshot does not wake the extension, and the app does not claim the
  extension applied a published revision.

## Schema

The first production schema contains:

- schema version
- writer-domain monotonic revision
- generation timestamp
- optional approved typing-layout identifier and locale tag
- optional auto-capitalization preference
- optional autocorrection preference
- optional predictions preference
- optional double-space-period preference
- optional key-haptics preference
- optional `automaticInsertionPreferenceEnabled`
- optional `translationActionPreferenceEnabled`
- optional `translationConfigurationReady`

Fields appear only when the corresponding production feature and default are
approved. Absence means use the bundled system-conforming fallback.

For every app-dependent action field, absence is fail-closed:
`automaticInsertionPreferenceEnabled`, `translationActionPreferenceEnabled`,
and `translationConfigurationReady` all resolve to false. A stale or prior
static snapshot may affect presentation, but it never authorizes provider work
or automatic insertion by itself.

`translationConfigurationReady` is a non-secret app-computed boolean. It is
refreshed whenever the canonical translation configuration changes and lets the
keyboard render an honest unavailable action without receiving a target,
prompt, model, or other configuration detail. It does not authorize provider
work by itself.

Static keyboard preferences do not expire by wall-clock time. Runtime voice
state, accepted results, commands, and acknowledgements remain separate
short-lived records with bounded expiry.

## Forbidden fields

The settings snapshot never contains:

- API keys, credentials, or Keychain metadata
- raw audio, file paths, or pending-recording metadata
- transcript or latest-result text
- prompts, provider models, provider responses, or provider errors
- ordinary keystrokes, touch events, surrounding text, or host-app identity
- document identifiers, session IDs, or insertion acknowledgements
- History, usage, retention, consent, or diagnostic records
- dictionary entries, custom terms, emoji commands, or replacement rules in v1
- the complete `AppSettings` value or canonical Library repository

Space cursor behavior, the required Globe path, and safety invariants are not
mutable snapshot fields.

## Optional future lexicon gate

- Personal dictionary publication remains forbidden in v1.
- A future spec update must name exact normalized fields, count/size limits,
  disclosure, deletion, refresh, and log-redaction behavior before any user
  terms enter the App Group.
- Automatically learned host-field content, prompts, usage frequency, and
  surrounding text remain forbidden.

## Reading and validation

- The extension reloads the snapshot when it appears and at relevant text-input
  context changes.
- Unsupported schema, corrupt JSON, invalid values, missing file, or failed App
  Group access must not crash or block ordinary typing.
- Any invalid snapshot falls back to bundled minimal typing behavior.
- The fallback supports ordinary Unicode entry and required keyboard switching
  without network, Full Access, or containing-app availability.
- Fallback copy must not present Phase 0 `en-US` metadata as an approved
  production layout.
- Errors log only compact categories and schema/revision metadata, never raw
  snapshot contents.

## M0B gate

- Physical iPhone and iPad evidence must prove App Group snapshot reading with
  Full Access off on supported OS versions and real provisioning profiles.
- The matrix includes Full Access on/off, reinstall/upgrade, app and extension
  eviction, missing App Group, corrupt snapshot, and schema incompatibility.
- If the read-only path is unreliable, the production keyboard keeps bundled
  fallback preferences and asks the user to open HoldType for app-dependent
  features. Full Access is not requested solely for static preferences.
- No production extension writer is added by this spec. Extension commands and
  acknowledgements require M0C and the shared-state contract update.

## Invariants

- The containing app remains the canonical settings owner.
- Snapshot publication is one-way and atomic.
- Ordinary typing never depends on network access, secrets, or a running app.
- A snapshot read failure cannot erase canonical settings.
- Static preference state is never mixed into expiring voice delivery state.

## Edge cases and failure policy

- If publication fails, Settings shows a compact refresh error while preserving
  the last durable app value and any prior valid snapshot.
- Risk-increasing changes such as enabling automatic insertion are not eligible
  in a live result until a matching settings revision has published
  successfully. Risk-reducing changes such as disabling it immediately make
  new live results ineligible and clear or replace any current app-owned result
  authorization. The accepted-result snapshot carries its own
  `automaticInsertionAuthorized` boolean derived from canonical settings, so a
  stale static `true` cannot authorize insertion.
- The app distinguishes `saved in HoldType` from `published to keyboard` and
  never tells the user an extension-facing change was applied when publication
  failed. Retry republishes the current canonical revision; it does not roll
  settings back silently.
- If two app scenes request publication, one canonical writer serializes them
  and emits one strictly increasing revision.
- If an older app version writes an unsupported snapshot, the extension uses
  fallback rather than partially applying unknown fields.
- If a layout named by the snapshot is not bundled in the extension, the
  extension uses its approved fallback and reports an unavailable-layout
  category without logging user content.

## Route / state / data implications

- Snapshot revision may appear in Diagnostics as scalar health metadata only.
- Keyboard Settings may show that preferences were published, not that the
  extension consumed them.
- Voice action readiness is owned by the expiring voice-session snapshot, even
  when translation action preference and configuration readiness are published
  here. Automatic insertion also requires the current static preference plus
  the per-result authorization plus every live eligibility rule in
  `ios-output-actions.md`.

## Verification mapping

- Test atomic round trip, revision ordering, optional-field defaults, schema
  incompatibility, corrupt data, invalid values, and missing container.
- Test automatic-insertion preference and translation visibility/readiness
  changes without publishing any underlying translation configuration.
- Test forbidden-field absence with encoded fixture inspection.
- Test bundled fallback without App Group, network, app process, or Full Access.
- Record M0B device evidence before treating read-only publication as supported.

## Superseded Unknowns

- V1.1 has no production typing-layout or locale-tag gate. Any future alphabetic
  keyboard or dictionary publication requires a new approved product spec.
