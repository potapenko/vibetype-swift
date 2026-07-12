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
- The Settings root exposes OpenAI as a native detail destination. Merely
  opening the Settings root does not inspect the credential marker or
  Keychain. Each OpenAI-detail appearance refreshes its payload-free,
  marker-only status and the first appearance starts one process-owned,
  event-driven status observation; neither action reads Keychain. Keychain
  remains untouched until an explicit key mutation or `Check Saved Key`
  action.

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
- Repository automation and XCTest host launches select a disabled Keychain
  access mode before the containing-app coordinator is constructed. In that
  mode every load, save/replace, and remove fails locally without calling any
  Security item API, inspecting an existing item, or changing it. The mode is
  process-local, is never selected by a normal production launch, and does not
  turn an inaccessible item into `not configured`.
- Saving or replacing a manually entered key occurs when the user commits the
  field with Done/Return or leaves the field with a non-empty valid candidate;
  it does not write a partial key on every character.
- An explicit Paste action with non-empty text commits immediately. HoldType
  does not inspect the clipboard passively.
- No separate Save button is required.
- The API-key draft belongs only to one scene's ephemeral OpenAI editor state.
  It may survive a transient navigation dismissal so a failed focus-loss save
  can be retried, but it is never copied into the process-owned presentation
  owner, another scene, app settings, diagnostics, `SceneStorage`, App Group,
  or durable navigation state. The editor uses a secure, privacy-sensitive
  field with capitalization and correction disabled. A successful save clears
  the draft. A failed save keeps the still-masked draft and visible failure for
  an explicit retry while preserving the previous saved item and status.
- Return/Done attempts one manual commit. Leaving the field commits only a
  non-empty candidate. Typing alone performs no credential operation. Empty
  or whitespace-only submitted and pasted candidates are rejected locally;
  HoldType does not require an `sk-` prefix or otherwise infer provider key
  formats.
- Remove is a destructive action with confirmation. A successful remove also
  clears the visible draft; a failed remove retains both the previous status
  and any draft.
- While one credential action is in progress, the OpenAI detail disables
  refresh, save, paste, and remove actions. The process-owned coordinator
  remains the final FIFO transaction boundary if another scene or voice flow
  already has an operation queued.
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
- The marker's canonical app-private location is
  `HoldType/ios-openai-credential-presence.json` beneath Application Support.
  Production composition does not accept an alternate marker path from a
  scene, view, or Retry caller.
- A failed replacement leaves the previous saved item and runtime credential
  intact and shows a visible error.
- Remove requires explicit user action. A failed delete must not present the key
  as removed.
- Provider rejection never deletes, replaces, or rewrites the saved key.
- Provider rejection is process-only status tied to the exact current runtime
  credential generation. A late rejection for a replaced credential is
  ignored, and voice preflight never silently reuses a current credential that
  is already marked rejected.
- Failed-History Retry uses the same process-owned credential coordinator.
  Credential rejection from its Transcription, Correction, or Translation
  adapter records the exact generation before the result is reduced to a
  payload-free failure; no provider status or credential value enters History.
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
- An explicit failed-History Retry is a requested voice preflight. Its
  process-owned session factory resolves the canonical credential coordinator,
  current app settings, and current Library content for that action, then binds
  the resolved credential to one transient provider adapter before the durable
  Retry reservation. The public Retry call accepts no caller-mintable
  credential-eligibility flag and no stored credential snapshot.
- Launch, foreground, History cleanup, failed-Retry process-loss recovery, and
  failed-row reads are passive operations. They do not resolve Keychain or
  construct a provider session. Missing or unavailable credentials are
  discovered only after the person explicitly requests Retry and route to the
  OpenAI owning destination without changing the row or retry count.

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

The OpenAI detail labels a successful mutation as `Saved in HoldType`; it does
not claim that the credential is provider-accepted, active in the keyboard, or
published anywhere. A partial success adds the existing `status needs refresh`
warning. Unknown failures are reduced to fixed redacted UI categories rather
than retaining an arbitrary `Error` or its description in observable state.

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
without discarding a successfully resolved runtime credential or absence. The
coordinator retains that redacted issue in process memory across later passive
status reads, subscriptions, and provider-status events. It clears the issue
only after a successful reconciliation, save, or removal proves durable marker
truth. The explicit resolution outcome and the status stream publish the same
revisioned status update, so no presentation layer reconstructs or weakens the
result after the operation returns.

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

### Bounded JSON structural validation

- Before Foundation turns JSON objects into dictionaries, the credential
  marker, general settings, and Library decoders run one shared structural pass
  over the complete source. It accepts strict UTF-8 JSON and JSON whitespace;
  a byte-order mark, invalid UTF-8, malformed token, trailing value, or
  truncated document is corrupt input.
- Object-member identity matches Swift `String` equality over the decoded UTF-8
  scalars, because the repositories consume Swift dictionaries. Literal and
  escaped spellings plus canonically equivalent Unicode names are duplicates;
  case differences and compatibility-only equivalents are not folded together.
  A duplicate at any nesting level is rejected before schema, field, or value
  validation.
- The pass allows at most 64 nested object/array containers, 1,024 members in
  one object, 262,144 object members in the document, 65,536 elements in one
  array, 524,288 total values, 4,096 decoded UTF-8 bytes in one member name,
  and 256 bytes in one number token. Hitting a structural limit is corruption,
  not a partial decode.
- The repository byte limit is checked first. A source beyond that limit keeps
  the existing settings/Library source-too-large or marker storage-limit error;
  malformed JSON, duplicate members, and structural resource-limit failures
  map to the repository's existing malformed/corrupt-data error. The complete
  structural pass precedes unsupported-schema and unexpected-field checks, so
  structural corruption wins when both are present.
- Every validation failure preserves the exact source and performs no rewrite,
  removal, default publication, or Usage-style compaction. This pass is scoped
  to app-private `HoldTypePersistence` metadata; the bounded App Group bridge
  and legacy macOS/UserDefaults stores remain governed by their own contracts.

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
  semantic UUID identity, and row order are preserved; repeated search text is
  valid and is not deduplicated. A noncanonical UUID string may be written in
  canonical `UUID.uuidString` form by a later save without changing identity.
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
- The process has exactly one composition-owned Settings state owner and one
  Library state owner before any editor is exposed. Failed-History Retry is a
  consumer of those exact owners rather than an owner of separate repositories.
  Every scene shares them. Separate scene-local repository instances and
  read-then-save mutations outside those state owners are unsupported because
  one actor serializes only its own method calls, not a transaction split
  across actors or calls.
- Simulator verification may prove only that Complete protection was requested.
  Effective protection remains a signed physical-device gate.

### P3 process-owned Settings and Library state

- After the canonical storage root resolves, the containing-app composition
  constructs exactly one Settings state owner and one Library state owner for
  the process, before creating scene content or the failed-History service. If
  root resolution fails, both owners remain unavailable and defaults are not
  presented as durable state. State-owner construction is passive: it creates
  no settings or Library file, performs no load or save, reads no Keychain
  item, and contacts no provider.
- Each owner exposes one app-private snapshot with exactly four semantic
  states: `notLoaded`, `ready(value)`, `loadFailed`, or
  `saveFailed(lastDurableValue)`. A missing canonical file loads as
  `ready(defaults)` without writing. A read or decode failure exposes no
  substitute value and preserves the source bytes. Snapshot descriptions,
  debug descriptions, reflection, and failures are redacted; the associated
  runtime value itself remains app-private and non-Codable rather than
  redacted.
- The first load, every mutation, and every failed-History Retry value
  resolution are serialized as whole owner transactions, including suspension
  at repository I/O. A mutation that starts before initial load first resolves
  the durable value inside that same transaction, then applies one
  read-modify-save operation. Scene code never performs a separate read and
  later full-value save. Each transaction publishes its resulting observable
  snapshot on `MainActor` before releasing the FIFO lease, so a later
  transaction cannot make progress and then be visually overwritten by an
  older continuation.
- A candidate value is not published as ready until its atomic repository save
  succeeds. The commit returns the exact canonical runtime value encoded by
  the repository, so Library normalization can never leave the owner
  presenting an optimistic pre-normalization candidate. If save fails, the
  candidate is discarded, the owner reports a typed redacted write failure,
  and its snapshot becomes
  `saveFailed(lastDurableValue)`. The next mutation starts from that last
  durable value; a later successful save clears the failure state.
- Owners expose serialized read-modify-save changes, not a public replacement
  of an entire stale draft. An editor commits its semantic field or collection
  change against the latest durable value after acquiring the owner
  transaction.
- Failed-History Retry receives these exact two owner identities from the
  composition root. It waits behind an in-flight mutation and resolves the
  newly durable value after success or the previous durable value after a
  failed save. It never creates another Settings or Library repository and
  never consumes an optimistic editor value.
- Settings and Library remain independent records in this checkpoint. Retry
  freezes one individually durable Settings value and then one individually
  durable Library value; P3 does not claim a cross-file atomic revision. A
  later feature that requires both records from one logical instant must add
  an explicit pair coordinator rather than infer atomicity from the two owners.
- Every iPhone and iPad scene receives the same two owner identities. A scene
  may observe or mutate through them but cannot construct a replacement owner
  or repository. Storage-root failure leaves both owners unavailable rather
  than presenting defaults as durable state.

### P3 process-owned credential presentation state

- After constructing the one credential coordinator, the composition root
  constructs exactly one app-private credential presentation owner and gives
  that same identity to every scene. SwiftUI receives this owner, not the
  coordinator, Keychain adapter, or containing-app composition. The owner
  wraps a narrow client whose production closures all capture the exact
  process-owned coordinator.
- If secure credential construction is unavailable, the presentation owner
  still exists in an explicit `unavailable` state. It never converts that
  condition to `not configured`; local Settings and Library remain usable.
  Storage-root failure prevents all three presentation owners from being
  created and uses the existing blocking local-storage surface.
- Construction is passive. Each OpenAI detail task requests
  `credentialStatusUpdate()`, which reads the non-secret marker, and the first task
  subscribes to one payload-free coordinator status stream. The stream emits
  an initial marker/cache status and event-driven changes after credential
  mutations, voice preflight, or provider rejection. Every emitted status has
  a monotonic process-local revision that contains no credential identity or
  generation, so a late passive snapshot cannot overwrite newer truth. The
  stream never polls Keychain and contains no credential or generation.
  `Check Saved Key` calls
  `resolve(for: .openAISettingsRefresh)` and stores only the returned
  payload-free status; the credential resolution and generation never enter
  SwiftUI state.
- The owner stores only availability, payload-free status, a closed operation
  state, and closed redacted notice or failure categories. It never stores an
  API-key candidate, clipboard value, resolved credential, provider request,
  or arbitrary error. After save or remove it reloads marker/cache status
  through `credentialStatusUpdate()` without performing another Keychain read.
- A single owner operation state prevents overlapping UI actions across
  scenes. Save and remove report success only after the coordinator returns;
  refresh failure re-reads marker/cache presentation state so process truth
  can be shown without another Keychain access, but that older cached truth
  does not hide the supplementary failure of the user's explicit Keychain
  check. Re-entering the detail also does not erase a failed mutation or its
  retry draft. Event-driven status
  changes received while an owner action is in progress are retained by
  revision, and an older action result cannot overwrite them. A newer external
  status clears only an action notice or failure that the payload-free status
  itself makes obsolete. A cache-only voice preflight does not prove that a
  previously locked or unreadable Keychain item recovered, so Keychain-access
  failures remain until a successful explicit Settings refresh, save/replace,
  or remove begins a new action. A newer same-status event likewise preserves
  a still-relevant failed replacement error. The coordinator stream therefore
  keeps an open detail current when voice or Retry changes process truth
  without overstating what its cache-only events verified.
- The SwiftUI root stores only the exact Settings, Library, and credential
  presentation-owner identities plus payload-free provider availability. It
  never stores or receives the containing-app composition, credential
  coordinator, Keychain adapter, or failed-History service.
- The narrow client, presentation owner, draft wrapper, coordinator, and
  containing-app composition have redacted description, debug, and reflection
  surfaces so a debug dump cannot traverse into key material or captured
  credential state.

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

### P3 general Settings editors

- The Settings root pushes four native containing-app `Form` destinations:
  Transcription, Writing & Correction, Translation, and Voice & Recording.
  They expose only fields already present in general app settings v1. They do
  not expose keyboard typing, Quick Session, History, recording-cache,
  automatic-insertion, Nearby Text, or macOS-only controls.
- Each destination owns one scene-local, memory-only non-secret draft created
  from the latest durable semantic group. Editing never performs provider,
  microphone, Keychain, clipboard, App Group, or filesystem work. A draft is
  not stored in `SceneStorage`, `UserDefaults`, diagnostics, or a replacement
  repository.
- `Save` is explicit. It validates the visible group and calls the exact
  process-owned Settings owner once. The owner applies only that semantic
  group to its latest durable value, so an older screen cannot overwrite
  unrelated changes from another scene. A clean editor adopts a newer durable
  group automatically. A dirty editor retains its draft, identifies that
  settings changed elsewhere, and makes the pending overwrite explicit.
- A dirty editor replaces the normal Back action with Cancel and a discard
  confirmation. Switching an iPhone tab or iPad sidebar destination while a
  general-Settings draft is dirty requires the same confirmation before the
  detail can be replaced. Until the choice is made, the same editor and draft
  remain visible; Keep Editing or dismissal retains them, while confirmed
  discard clears the Settings route and enters the requested destination. A
  failed write keeps the scene-local draft visibly
  marked `Not Saved`, while shared summaries and provider snapshots remain on
  the last durable value. The warning remains visible in a persistent bottom
  status while the user edits lower form content. The user may retry or
  discard; the failed draft is never presented as saved. A successful commit
  adopts the exact value returned by the owner and clears the warning only
  while that semantic group is still current. If a newer same-group value has
  already reached the process owner before the older caller resumes, the newer
  value remains authoritative and the older draft stays visibly unsaved as
  `changed elsewhere`. A transition to either warning posts one content-free
  accessibility announcement.
- Blank transcription, correction, or translation model fields visibly use
  their documented default. Transcription Custom with an empty code visibly
  falls back to Auto. A non-empty custom language code must be two or three
  ASCII letters before Save is enabled. Language choices use a dedicated
  searchable list rather than a long menu, including an explicit Custom row.
  Translation may be saved while its route is incomplete; the action remains
  unavailable and the editor states exactly which source or target
  configuration is missing. Custom-code fields expose a content-free
  accessibility hint and announce invalid-to-valid transitions without
  reading the entered value.
- Correction and Translation prompts and models remain editable while their
  remote stage or action preference is off. Reset restores the exact shared
  standard prompt in the draft, announces that the draft is not saved, and
  does not save until the user taps `Save`.
- Voice & Recording exposes only recording cues, stop tail, and the fixed
  five-minute utterance limit explanation. `Keep Latest Result` is not
  editable in P3: turning it off requires coordinated accepted-output,
  bridge-revocation, and History-outbox cleanup under `ios-output-actions.md`.
  Its control appears only with that owning storage/recovery coordinator.
- Model identifiers and prompts are private app content. Editor state,
  validation, notices, accessibility announcements, diagnostics, reflection,
  and default logs never echo their values.

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
- Corrupt or unsupported data produces a visible local error and no editable
  substitute value; defaults become durable runtime state only when the
  canonical file is missing. A failed load never overwrites the source.
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
- If a settings write fails, shared UI truth restores the last durable value
  instead of pretending the change persisted. A scene may retain its local
  editor draft only while it is explicitly labelled unsaved and offers retry
  or discard.
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
