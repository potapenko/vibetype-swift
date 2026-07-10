# iOS Settings And Secret Storage

## Goal

Provide a complete native iPhone and iPad configuration surface while keeping
the containing app as the canonical owner of settings, user-managed content,
and the OpenAI API key.

## Scope

- in-app Settings and Library ownership
- defaults, validation, persistence, and migrations
- app-only OpenAI Keychain item and runtime credential state
- publication of a minimal keyboard settings snapshot
- truthful setup/readiness presentation
- iPhone and iPad settings navigation

## Non-goals

- `Settings.bundle` for product configuration
- accounts, subscriptions, analytics, telemetry, cloud sync, or team policy
- provider marketplaces, local model downloads, or self-hosted endpoints
- profiles or Modes not present in the current product
- macOS Accessibility, Input Monitoring, launch-at-login, Finder, floating
  indicator, Sparkle, or update preferences
- controls for features that are not implemented in the owning milestone

## Settings surfaces

- HoldType settings live inside the containing SwiftUI app.
- iPhone uses the Settings destination inside its normal navigation stack.
- iPad exposes the same settings destinations through its sidebar/detail
  experience rather than stretching an iPhone form.
- System Settings is used only for system-owned microphone, keyboard, default
  keyboard, and Full Access controls.
- HoldType uses public, version-gated Settings URLs plus written fallback
  instructions. It never uses private `prefs:` URLs.
- Dictionary, emoji commands, and replacement rules are editable Library
  content with lists and detail editors, not static system preferences.
- A setting appears only when its owning behavior works. Future keyboard,
  Quick Session, or typing controls must not be saved inertly in an earlier
  milestone.

## Default configuration

- transcription model: `gpt-4o-transcribe`
- dictation language: Auto
- custom language code and transcription prompt: empty
- custom dictionary: empty
- emoji commands: on; English set active
- Nearby Text Context: unavailable on iOS
- OpenAI correction: off
- correction model: `gpt-5.5`
- correction prompt: standard conservative correction prompt
- local plain-typography cleanup: on
- literal replacement rules: empty
- translation action preference: on
- translation source: Same as Transcription
- translation source override and target: unconfigured
- translation model: `gpt-5.4-mini`
- translation prompt: standard translation prompt
- insert automatically when current target matches: on
- keep latest result: on
- voice start/stop cues: on
- recording tail: Off
- per-utterance maximum: five minutes
- Quick Session: fixed five minutes once its gate passes; no duration editor
- durable local history: on under `ios-history-and-storage.md`
- recording cache: off; when enabled keep last 10 by default, with unlimited
  available only as an explicit choice

The Phase 0 `en-US` keyboard metadata is not a production typing-layout
default. Typing layouts and dictionaries appear only after their entry gate.

## OpenAI API key

- The API key is stored as one generic-password item with the fixed service
  `app.holdtype.HoldType.ios` and account `openai-api-key`. These values are
  stable storage identifiers, not values derived dynamically from the current
  bundle identifier.
- The item is not synchronizable, is not in an App Group or custom shared
  Keychain group, and uses `WhenUnlockedThisDeviceOnly` accessibility.
- Every add, update, read, and remove is scoped to the containing app's built-in
  signed `application-identifier` access group. The value is expanded from
  `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` at build time; HoldType
  never performs a wildcard search and never uses
  `group.app.holdtype.HoldType.shared` for the key. A missing, unsigned,
  unresolved, shared, or wrong-bundle value fails locally before any Keychain
  call. Public iOS APIs do not prove that an otherwise well-shaped prefix is
  entitled; Security rejects an unauthorized group and HoldType reports a
  redacted local Keychain failure.
- Save/replace updates that exact item before attempting an add. If another
  operation creates the item between update and add, HoldType retries the
  update; it never deletes the previous item before replacement.
- A locked-device Keychain response and an invalid Keychain result are distinct
  typed local failures. Removing an already-missing item succeeds. Public error
  text, debug output, and reflection contain neither key material nor raw
  Keychain status details.
- The extension never reads Keychain and never receives key metadata.
- HoldType does not read the key on launch, passive Settings appearance,
  permission refresh, keyboard status refresh, or diagnostics export.
- Saving or replacing a manually entered key occurs when the user commits the
  field with Done/Return or leaves the field with a non-empty valid candidate;
  it does not write a partial key on every character.
- An explicit Paste action with non-empty text commits immediately. HoldType
  does not inspect the clipboard passively.
- No separate Save button is required.
- Save/replace updates the same stable item and the process credential cache.
- The containing app serializes save, replace, remove, explicit Settings
  refresh, and voice-preflight resolution as whole operations. Awaiting a
  Keychain adapter must not allow a second credential operation to interleave
  its marker, Keychain, or runtime-cache steps. Cancellation before an
  operation receives its lease performs no work; ordinary cancellation after a
  mutation marker is durable does not abandon reconciliation or restoration.
- The app composition root owns exactly one credential coordinator for the
  process lifetime and shares it across every scene, Settings surface, and voice
  flow. Production callers never construct scene-local coordinators or invoke
  the underlying Keychain or marker adapters directly; otherwise a per-instance
  transaction gate and credential generation could diverge.
- A separate app-private non-secret
  `credentialPresenceLastKnown` marker records only `present`, `absent`,
  `unknown`, or `mutationInProgress` plus its schema/update date and mutation
  kind. It contains no key material and is never published to the keyboard. A
  fresh process may read this marker to render status without touching Keychain;
  only an explicit OpenAI Settings action or a requested voice preflight
  resolves the actual item.
- A failed replacement leaves the previous saved item and runtime credential
  intact and shows a visible error.
- Remove requires explicit user action. A failed delete must not present the key
  as removed.
- Provider rejection never deletes, replaces, or rewrites the saved key.
- Provider rejection is process-only status tied to the exact current runtime
  credential generation. A late rejection for a replaced credential is
  ignored, and voice preflight never silently reuses a current credential that
  is already marked rejected.
- Provider services receive an already resolved credential and never read
  Keychain themselves.
- The resolved runtime credential trims only surrounding whitespace and rejects
  an empty normalized key. It is a transient non-Codable value: neither the key
  nor its compatibility source marker is persisted, logged, described, or
  published to the App Group or keyboard. Its standard Swift string, debug, and
  reflection representations are redacted. The source marker exists only for
  compatibility and does not prove readiness, trust, current Keychain
  availability, or storage location.
- A normal voice start resolves the credential in foreground before microphone
  capture. If the device is locked or the item is unavailable, recording stays
  blocked or an already completed journaled attempt waits for foreground and
  unlock.
- iOS does not inherit the macOS debug key-file exception.
- The only public resolution purposes are an explicit OpenAI Settings refresh
  and a requested voice preflight. Voice preflight reuses a current runtime
  credential or known absence; Settings refresh always checks Keychain. There
  is no general or passive credential-load API.

## API-key status

The OpenAI surface distinguishes:

- `not configured`
- `not checked in this process`
- `saved, last known`
- `available in this process`
- `unavailable while locked`
- `provider rejected`

A mask indicates last known successful storage, not proof that the key is
currently readable or accepted by OpenAI. The full key is never revealed.

The surface always shows one primary state from the list above. It may add a
`status needs refresh` warning only while the marker is `unknown` or
`mutationInProgress`; `saved, status needs refresh` and `removed, status needs
refresh` are not additional primary states and are never reconstructed from an
old `present`/`absent` marker after relaunch.

`not configured` requires an explicit successful removal or a permitted
credential resolution that found no item. Missing, corrupt, or stale marker
state is `not checked in this process`, never a passive Keychain read.

Keychain and marker writes are reconciled conservatively because they cannot be
one atomic transaction. Before every add, replace, or remove, HoldType first
atomically changes the marker to `mutationInProgress`; if that write fails, it
does not mutate Keychain. It then performs the explicit Keychain operation and
only after success commits `present` or `absent`. If the final marker write or
the process fails, a fresh process sees `not checked in this process` with the
refresh warning, never the previous false `present`/`absent` state. If the
Keychain operation fails, HoldType attempts to restore the prior marker; a
failed exact restore falls back to conservative unknown semantics.
Reconciliation reads Keychain only on a later explicit OpenAI or voice action.
A marker write never rolls back or deletes a successfully saved item, and no
stale marker is treated as proof after an interrupted mutation.

A successful Keychain mutation is also a successful user mutation even if the
final non-secret marker replacement fails. HoldType updates the process cache
to the Keychain truth, keeps the durable `mutationInProgress` marker, reports a
visible `status needs refresh` partial-success outcome, and never rolls the
Keychain item back. If a Keychain mutation fails, the exact prior marker is
restored, including removal of the marker file when it was previously missing.
If exact restoration fails, HoldType attempts to persist `unknown`; if marker
storage remains unavailable, the durable `mutationInProgress` state is treated
with the same not-checked/refresh-required semantics.

An unreadable, corrupt, or unsupported marker is preserved byte-for-byte.
Passive status performs no Keychain read, while save and remove stop before any
Keychain mutation. An explicit Settings refresh or voice preflight may still
resolve and cache the actual Keychain item, but it does not overwrite the
unreadable marker and reports a separate redacted local marker issue.

Successful explicit reconciliation avoids a marker write when the durable
marker already matches Keychain truth. For `unknown` or
`mutationInProgress`, it writes the final actual state. For a missing or
contradictory `present`/`absent` marker, it first attempts `unknown` and then
the final actual state so a failed final replacement cannot leave the opposite
last-known state. Failure to prepare `unknown` does not prevent the final
actual-state attempt; a remaining failure is surfaced as a local marker issue
without discarding a successfully resolved runtime credential or absence.

## Persistence ownership

- Small non-secret preferences use an app-owned versioned settings repository.
- The credential-presence marker is a separate status record excluded from
  device backup so a restored `ThisDeviceOnly` key is never inferred from a
  migrated marker.
- Dictionary, emoji commands, and replacement rules use an app-private
  versioned structured repository with atomic writes and Data Protection.
- History, pending recordings, cache audio, usage, and diagnostics follow their
  dedicated specs and are not serialized into the general settings record.
- The App Group receives only the exact keyboard snapshot and short-lived voice
  records defined by their specs. It never receives the complete settings or
  Library repository.
- Settings and Library data do not use CloudKit, iCloud Drive, or any other
  cross-device synchronization service.
- User-authored preferences, dictionary entries, emoji commands, and
  replacement rules are eligible for system-managed device backup so they can
  be restored with the app. Their backup protection follows the user's system
  backup configuration; HoldType does not claim or require that the backup is
  encrypted. Transient bridge files, latest/pending delivery records,
  recoverable audio, recording cache, runtime logs, and the API key follow
  their own explicit backup policies and are not inferred from this rule.

### Protected atomic metadata files

- The general settings record, Library record, and credential-presence marker
  share one app-private metadata-file boundary. It accepts only regular files
  and rejects symbolic links, directories, and special files without following
  them.
- Reads are bounded before allocation and while bytes are loaded. The marker is
  limited to 16 KiB and the settings and Library records to 1 MiB each; the
  exact limit is valid, while one byte more is rejected without changing the
  source.
- A read uses one pinned regular-file identity and accepts bytes only when its
  size and modification/change timestamps remain stable through the complete
  read. A save stops before publish if the durable destination changes, even
  when a raced write keeps the same inode and byte count.
- A settings or Library load that exceeds its limit is reported separately from
  a value whose canonical encoding is too large to save. The marker uses one
  storage-limit failure for either direction. These failures do not expose
  file locations, source content, system error numbers, or attacker-controlled
  fields or values.
- An oversized save fails before a temporary file is created and leaves the
  durable destination unchanged. A valid save uses an exclusive, owner-only
  temporary regular file in the destination directory, applies Complete
  protection before its first content write, applies the record's backup
  policy, writes and synchronizes all bytes, validates the temporary identity
  and size, and only then atomically publishes it.
- A failed publish preserves the previous destination and removes only the
  temporary file created by that operation. Removing an already-missing marker
  remains successful. Identity checks prevent a raced symbolic link or
  replacement object observed before cleanup from being treated as the
  operation-owned file; that observed object is not written, published, or
  deleted by the operation.
- These identity guarantees assume the app-private sandbox namespace and the
  repositories' serialized production ownership, without a hostile same-UID
  process interposing between the final path check and `rename` or `unlink`.
  HoldType does not claim kernel-level conditional-unlink hardening against
  that out-of-scope interposer.
- No failing step follows a successful atomic rename or removal. A committed
  mutation is reported as successful even if the best-effort directory sync
  cannot be completed, so callers never receive a failure after the durable
  destination has already changed.

### General app settings v1

- The app-private general settings record lives at the stable relative path
  `HoldType/ios-app-settings.json` inside the containing app's Application
  Support directory. It is never stored in `UserDefaults`, an App Group,
  CloudKit, or iCloud Drive.
- Version 1 contains only transcription configuration, correction
  configuration, the local plain-typography cleanup preference, translation
  configuration, Keep Latest Result, and voice audio-cue/recording-tail
  preferences. The API key and presence marker, Library content, History,
  usage, diagnostics, pending/recovery state, audio, retention, automatic
  insertion, typing preferences, Nearby Text, macOS-only preferences, consent,
  and Full Access evidence are not part of this record.
- The runtime settings value is an `Equatable` and `Sendable` value, not a wire
  DTO and not `Codable`. Persistence uses a private versioned representation.
- `schemaVersion` is required and must be exactly integer `1`. A canonical save
  writes every v1 group and field, even when it equals the default. A load may
  default a missing known group or known field so additive fields can be
  introduced without losing established values.
- Malformed JSON, a non-object root, a missing or wrongly typed schema version,
  null or wrongly typed known values, unexpected fields at any level, and
  unknown enum values are distinct typed local failures. Public errors identify
  only the known object or field path and never echo an attacker-controlled
  schema number, enum value, or unexpected field name. Version `0` and future
  versions are unsupported. No legacy v0 shape or migration is inferred; a
  migration fixture is added only when a real earlier persisted schema exists.
- A missing file returns the complete documented defaults without creating or
  rewriting a file. Corrupt or unsupported source bytes are preserved
  byte-for-byte and are never replaced by defaults during load.
- Loads and saves through the process-owned repository are serialized. Every
  save atomically replaces from the same directory, requests complete file
  protection, and remains eligible for system-managed device backup. A failed
  replacement preserves the previously durable bytes.
- Simulator tests prove that Complete protection is requested but may not
  report an effective protection class on the resulting file. Effective Data
  Protection remains a signed physical-device verification gate.

### App-private Library v1

- The containing app's canonical Library record lives at the stable relative
  path `HoldType/ios-library.json` inside its Application Support directory. It
  is never stored in `UserDefaults`, an App Group, CloudKit, or iCloud Drive.
- The runtime Library value is an `Equatable` and `Sendable`, non-`Codable`
  composition of `CustomDictionary`, `EmojiCommandsConfiguration`, and the
  ordered `[TextReplacementRule]` collection. Its complete defaults are an
  empty dictionary, enabled emoji commands with only English selected, no
  custom emoji commands, and no replacement rules.
- The private v1 root contains only `schemaVersion`, `dictionary`,
  `emojiCommands`, and `replacementRules`. A canonical save writes every group
  and field and uses sorted object keys. It preserves exact replacement-rule
  order and the relative order of dictionary entries and custom commands that
  survive normalization; normalization may reduce those arrays. Dictionary
  entries and custom emoji commands use the current shared-domain rules before
  they become durable. Replacement search, replacement, enabled state,
  identifier, and row order remain raw; repeated search text is valid and is
  not deduplicated.
- A load may default a missing known root group or a missing known group field.
  Every field of an existing custom-command or replacement-rule row is
  required. Nulls, wrong types, non-object rows, malformed identifiers, and
  unexpected fields at any level fail instead of defaulting or being ignored.
  A custom-command row also fails with a redacted known-field error when its
  normalized emoji or normalized spoken phrases are empty. Among otherwise
  valid commands, current domain normalization keeps the first semantic
  duplicate.
- `schemaVersion` is required and must be exactly integer `1`. Version `0` and
  future versions are unsupported, and no legacy shape or migration is
  inferred until an earlier durable schema actually exists.
- The only built-in emoji-set identifiers accepted by v1 are the exact values
  `en`, `ru`, `es`, `de`, `fr`, and `pt`; case or surrounding-whitespace
  variants fail on load and runtime save. The stored selection contains zero or
  one identifier; every identifier is validated before cardinality, so an
  unknown identifier fails even when a second item is present. More than one
  known item fails instead of silently choosing one. Custom-command UUIDs must
  be unique within their collection, and replacement-rule UUIDs must be unique
  within theirs. The duplicate check happens on the raw rows before normalized
  usability is validated and before semantic normalization can keep only the
  first equivalent custom command. Reusing one UUID across the two
  independently addressed collections is allowed.
- Public errors identify only known field locations and failure classes. They
  never echo dictionary text, emoji or command content, replacement content,
  unknown identifiers or fields, raw file locations, or system error numbers.
- A missing file returns the complete defaults without creating a file.
  Corrupt, invalid, or unsupported source bytes are preserved byte-for-byte
  and are never rewritten as defaults during load.
- The process-owned actor serializes Library loads and saves. The shared
  protected atomic-file boundary limits both source and canonical encoding to
  1 MiB, requests Complete protection before the first content write, and
  keeps the final Library record eligible for system-managed device backup. A
  failed replacement preserves the previous durable bytes.
- Simulator verification may prove only that Complete protection was requested.
  Effective protection remains a signed physical-device gate.

### Credential-presence marker v1

- The runtime marker is a non-transport value with an update date and exactly
  one state: `present`, `absent`, `unknown`, or `mutationInProgress`.
- `mutationInProgress` also records exactly one mutation kind,
  `saveOrReplace` or `remove`. Other states never carry a mutation kind.
- The private v1 file contains only `schemaVersion`, `state`, `updatedAt`, and
  the conditional `mutationKind`. It contains no key material, masked key,
  Keychain service or account, provider status or content, App Group data, or
  keyboard data.
- A missing file means that no marker has been recorded; it does not imply
  `absent`.
- Every replacement is atomic, requests complete file protection, and excludes
  the marker from device backup. A failed replacement preserves the previously
  durable bytes.
- Corrupt data, unsupported schema versions, unexpected fields, and invalid
  state/mutation combinations produce a typed local error. The source file is
  preserved for recovery and is never rewritten as part of a failed load.
- Marker errors never echo an unsupported schema number, unknown state,
  unknown mutation kind, unexpected field name, file location, or system error
  number.
- Version dispatch starts at v1. There is no inferred legacy schema or migration
  until an actual earlier persisted format exists.

## Validation and editor behavior

- Empty Custom language falls back to Auto. A non-empty code must be a valid
  supported two- or three-letter code or show inline validation.
- Empty model fields resolve to their documented defaults.
- Dictionary entries trim surrounding whitespace, ignore empty values, and
  deduplicate case-insensitively while preserving the first spelling.
- Correction and translation prompts remain editable while their remote stage
  is off and provide Reset to the standard prompt.
- Translation remains visible but unavailable with an in-app route to
  Translation setup until its target configuration is valid. The keyboard can
  only instruct the user to configure Translation in HoldType; it cannot launch
  the containing app.
- Local usage is labelled `Transcription Usage Estimate`, is device-local, and
  is never presented as the user's OpenAI invoice or balance.
- Usage presentation, retention, and Reset behavior follow
  `ios-usage-estimate.md`.

## Truthful setup status

- API-key readiness is separate from microphone and keyboard setup.
- Keyboard enablement/default status is not claimed as programmatically proven;
  setup uses a Settings route, instructions, and the practice field.
- Full Access in the containing app is only `recently verified enabled` or
  `not currently verified`.
- Freshness comes only from the short-lived extension-owned
  `KeyboardReadinessHeartbeat` in `ios-keyboard-shared-state.md`. A published
  preference revision or past practice-field use is not Full Access evidence.
- The app never reports a saved preference as active before its owning feature
  consumes it.

## Migrations

- Every persisted schema has an explicit version and deterministic migration.
- Corrupt or unsupported data produces a visible local error and safe defaults;
  it does not silently overwrite the source before recovery is decided.
- Extracting shared domain types must preserve current macOS defaults and keys
  through the macOS compatibility facade.
- iOS migrations never import macOS Keychain items, absolute sandbox paths, or
  platform-only behavior settings.

## Invariants

- API keys never enter UserDefaults, Library data, App Group, logs, diagnostics,
  history, or source control.
- Settings changes do not start microphone capture or provider work.
- No background or passive Keychain polling.
- No setting silently enables network processing without the applicable
  disclosure and consent.
- No account, telemetry, cloud, or server-owned settings state.

## Edge cases and failure policy

- If settings cannot be read, HoldType shows a local configuration error and
  keeps unrelated History and diagnostics available.
- If a settings write fails, the UI restores the last durable value instead of
  pretending the change persisted.
- If Library data is corrupt, HoldType preserves the file for bounded local
  recovery and does not publish it to the keyboard.
- If a credential becomes unavailable after recording, the protected pending
  attempt remains recoverable and no unauthenticated request is sent.
- If App Group publication fails, canonical app settings remain intact and the
  keyboard keeps its last valid snapshot or bundled fallback, Settings shows
  that keyboard publication is stale, and no risk-increasing live authorization
  is enabled from the failed revision.

## Verification mapping

- Test every default, validation rule, save/load, schema migration, corrupt
  data path, and failed-write rollback.
- Test both exact byte limits and one byte over; non-regular path rejection;
  prewrite protection, ownership, and backup metadata; partial/interrupted I/O;
  same-inode mutation detection; failed publish cleanup; and the rule that a
  post-commit directory-sync failure cannot reverse the reported outcome.
- Test Keychain add/replace/delete, stable item identity, non-synchronizable and
  accessibility attributes, locked-device behavior, and no passive reads with
  fakes in normal automation.
- Test explicit paste versus manual commit and preservation of the previous key
  after replacement failure.
- Test fresh-process marker-only status, honest unknown state, explicit
  reconciliation, pre-mutation marker failure, every crash point between marker
  and Keychain commits, and partial write failures without passive Keychain
  access.
- Test FIFO non-interleaving across suspended save, remove, and resolve calls;
  cancellation before and after the mutation lease; stale provider-rejection
  suppression; cache-first voice behavior; forced Settings refresh; and the
  rule that unreadable marker bytes are never rewritten by resolution.
- Test redaction and absence of secrets from all non-Keychain stores.
- Test iPhone/iPad navigation and that gated controls are absent rather than
  inert.

## Unknowns requiring confirmation

- Exact first production typing layouts and dictionaries are settled by the
  production keyboard entry gate, not by the Phase 0 locale.
