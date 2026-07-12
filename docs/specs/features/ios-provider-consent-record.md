# iOS Provider Consent Record

## Goal

Make OpenAI-processing consent a strict, app-private, revisioned authority so a
stale scene or provider stage cannot dispatch after withdrawal or a disclosure
change.

## Scope

- exact app-private provider-consent record;
- process-owned observation and compare-and-swap mutation;
- provider-stage authorization and late-result rejection;
- explicit review, acceptance, withdrawal, and unreadable-record reset;
- storage durability, privacy, and redaction.

## Non-goals

- legal privacy-policy wording;
- API-key storage or validation;
- microphone authorization;
- Quick Session consent;
- general settings, History, App Group, keyboard, analytics, or cloud sync.

## Version-1 Record

The canonical relative path is
`HoldType/ios-openai-provider-consent.json` beneath the containing app's
Application Support directory. The strict UTF-8 JSON object contains exactly:

1. `schemaVersion`: integer `1`;
2. `epochID`: lowercase canonical UUID string;
3. `revision`: signed integer in `1...Int64.max`;
4. `disclosureVersion`: signed integer in `1...Int64.max`;
5. `state`: exactly `accepted` or `withdrawn`;
6. `decisionAt`: canonical UTC timestamp with millisecond precision.

The current P4 `disclosureVersion` is integer `1`. It describes foreground
app-only transcription, optional correction/translation, protected Pending
recovery, app-private Latest Result, and no History or Recording Cache product.
Enabling P5 History/retention or materially changing provider, transmitted data,
or purpose requires a later disclosure version and renewed acceptance.

The timestamp uses exactly `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`, a proleptic Gregorian
calendar, four calendar-year digits, and no leap second. The complete file is at
most 4,096 bytes. It contains no optional, omitted, null, nested, array, or
additional value.

The decoder accepts only strict UTF-8 JSON without a byte-order mark, duplicate
or canonically equivalent keys, unknown or missing keys, numeric aliases,
non-canonical UUID/date values, unsupported states, or unsupported schema.
Malformed and future-version bytes are preserved byte-for-byte and are never
interpreted as absence, withdrawal, or acceptance.

A missing file means no consent decision. It returns a stable absent observation
without creating defaults. `accepted` authorizes only the exact current
disclosure version. An older accepted disclosure requires review again;
`withdrawn`, future, corrupt, unavailable, or commit-uncertain state is not
consent.

## Process Ownership And Presentation

- The containing-app composition owns one provider-consent coordinator for the
  canonical physical repository root. Every scene and provider stage uses that
  same identity; views and services never create fallback stores or retain a
  Boolean authorization.
- A public observation is one content-free state: not reviewed, review required,
  accepted current disclosure, withdrawn, local data unavailable, or mutation
  not saved. It may show the decision date intentionally on Privacy &
  Permissions but exposes no repository path, raw bytes, UUID, revision, or
  system error.
- Loading or observing the record is passive. It performs no Keychain,
  microphone, audio-session, provider, clipboard, App Group, or keyboard work.
- Runtime values, errors, expectations, authorizations, and coordinator state
  have redacted descriptions, debug output, reflection, logs, and diagnostics.

## Mutation And Compare-And-Swap

- Each observation carries one opaque expectation: exact absence or the current
  readable epoch ID plus revision, together with the process gate fence current
  when that value was observed. Acceptance and withdrawal require that complete
  expectation and fail without writing when either the repository value or gate
  fence is stale.
- The first readable decision mints a fresh epoch ID and starts at revision `1`.
  Each later committed decision in that epoch increments revision exactly once.
  The composite epoch/revision authority is never reused; overflow fails closed.
  Repeating an already-current accepted disclosure or already-withdrawn state is
  an exact no-op.
- Withdrawal closes the process provider gate and advances its fence before it
  waits for repository I/O. That fence invalidates every earlier observation
  even when the withdrawal write later fails and the prior accepted bytes remain
  durable. A queued or late Accept made from an older observation cannot reopen
  the gate or overwrite the decision; re-acceptance requires a fresh post-fence
  observation, an explicit new decision, and renewed durability confirmation.
  Repeating identical accepted bytes is a durable no-op only after those checks;
  it is never permission to reuse a pre-withdrawal observation.
- A successful mutation publishes the exact canonical value returned by the
  repository. The coordinator never synthesizes a success from its request or
  increments presentation state before durable confirmation.
- A failure before publish preserves the previous file. If a repository result
  is commit-uncertain, the coordinator reloads and compares the exact intended
  epoch ID, revision, state, version, and date. An exact match becomes committed
  only after the required directory durability barrier is repeated successfully;
  an exact prior value remains prior truth, and any other result stays
  unavailable. It never guesses authority.
- An ordinary load preserves corrupt or future bytes. Privacy & Permissions may
  offer `Reset Unreadable Consent Data` only after explicit confirmation. Reset
  first closes the process gate and invalidates every process authorization,
  then removes only the exact observed unreadable record. Failure or identity
  uncertainty preserves it and remains blocked. Successful reset establishes a
  new absent state; a later acceptance mints a fresh epoch ID and starts at
  revision `1`. No authorization from the prior epoch can survive in the
  process, and the composite revision authority is not reused.

## Provider Authorization Gate

- Durable acceptance creates only local eligibility. The process coordinator
  mints an opaque authorization bound to the exact repository epoch ID,
  revision, current disclosure version, exact confirmed consent-file physical
  revision, current gate fence, and canonical physical repository-root identity.
  It contains no key, prompt, content, provider configuration, path, or user-
  facing copy. A substituted root, same-root consent replacement/deletion,
  unreadable or unavailable data, a different physical alias, or loss of root
  identity invalidates it.
- Transcription, correction, and translation use one atomic gate operation that
  validates the authorization, rereads the exact durable consent snapshot,
  revalidates the same physical root before and after that read, registers
  cancellation, and grants launch. There is no validation-
  to-dispatch window: withdrawal either closes the gate first or observes the
  already registered task and cancels it.
- Provider response handling atomically consumes a one-shot result authorization
  under that same gate before it can advance Pending state or create accepted
  output. Withdrawal, reset, a newer decision, disclosure-version change,
  repository/root unavailability, process-gate closure, duplicate completion,
  or physical-root mismatch makes matching output ineligible. There is no
  validation-to-result-consumption window.
- The containing-app stage executor prepares one cancellable task behind a
  closed launch permit before registration. Registration installs cancellation
  first; the atomic launch operation may then release that exact task. Losing
  consent before launch never invokes the provider operation. Losing it after
  launch cancels the task, completes the caller without waiting for a
  non-cooperative late result, and makes that late result ineligible.
- Before result consumption, the containing-app adapter normalizes provider
  success or failure into one payload-minimized `Sendable` stage outcome. A raw
  `Error`, provider response, URL response, credential, prompt, audio reader,
  path, storage capability, or provider task never crosses the synchronous
  consent-consumption closure or appears in the returned authorization outcome.
- Result consumption performs only one synchronous, non-suspending handoff
  while the consent fence is held. Transcription, optional correction, and
  Translation each obtain their own registration and one-shot result
  authorization. The consumed normalized outcome is returned exactly once;
  authorization loss returns no provider payload.
- Pending, accepted-output, usage, or other local persistence runs
  asynchronously only after successful result consumption and outside the
  consent fence. Local mutation failure or uncertainty retains provider-free
  recovery work and never reuses the consumed result authorization or repeats
  provider work in the same process.
- Provider acceptance does not replace microphone or credential preflight. All
  three gates must independently succeed in their specified order.
- A request already received by OpenAI cannot be recalled. Withdrawal cancels
  supported local tasks, retires their dispatch authority, and rejects later
  local results without claiming remote deletion.

## Storage And Durability

- The record uses the protected atomic metadata-file boundary defined by
  `ios-settings-and-secret-storage.md` for app-private regular-file validation,
  bounded reads, owner-only temporary publication, Complete Data Protection
  before the first byte, synchronized contents, identity validation, and atomic
  replace. Unlike ordinary settings metadata, consent requires the containing
  directory durability barrier after every rename or unlink.
- Acceptance, withdrawal, and reset report success only after the exact intended
  bytes or absence are revalidated and the containing directory synchronization
  succeeds. A post-rename or post-unlink failure is `commitUncertain`; it does
  not mint provider authorization, reopen the process gate, or confirm the
  user-visible decision. Reconciliation reloads exact bytes/absence and repeats
  the required directory barrier before resolving the operation.
- It remains eligible for system-managed app backup like other user decisions;
  it is not CloudKit or iCloud Drive state. A restored decision never implies a
  restored `ThisDeviceOnly` API key, microphone permission, or provider
  readiness.
- The record never enters UserDefaults, Keychain, App Group, keyboard storage,
  History, usage, diagnostics export, provider requests, or source control.
- Production construction does not accept an alternate path from a scene,
  preview, provider service, or runtime request. Test repositories remain
  isolated and cannot mint production authority. On a fresh app container, the
  no-path composition constructor securely creates and synchronizes the missing
  canonical Application Support directory through a descriptor-relative,
  no-symlink, owner-only bootstrap before the process context pins its physical
  root. Bootstrap failure leaves consent unavailable and cannot permanently mint
  a pathless fallback context.

## Invariants

- No provider request without a current durable accepted decision and a matching
  live authorization.
- No stale Accept can overwrite a later Withdrawal.
- No observation issued before any Withdrawal or Reset attempt can reopen the
  gate, even when that attempted mutation fails.
- No old provider stage or late result can reuse an epoch/revision authority.
- No consent authority survives a canonical physical-root mismatch or alternate
  production repository path.
- No time-of-check/time-of-use gap exists between gate validation and provider
  launch or one-shot result consumption.
- No passive status read grants consent or starts dependent work.
- No malformed, future, inaccessible, or ambiguous file is treated as consent.
- Reset is explicit, fail-closed, and cannot delete an unobserved replacement.

## Verification Mapping

- Test strict v1 encode/decode, exact path, byte limit, dates, UUIDs, duplicate
  keys, unexpected fields, corrupt/future preservation, missing baseline, Data
  Protection request, backup eligibility, and atomic replacement failure.
- Test absent-to-accept, accept no-op, withdrawal, re-acceptance, stale CAS,
  failed Withdrawal versus queued old Accept, multi-scene queued Accept versus
  Withdrawal, overflow, fresh epoch IDs, commit-uncertain reconciliation,
  confirmed reset, and reset identity races.
- Test stage dispatch and response validation for Transcription, Correction,
  and Translation across withdrawal-versus-launch, withdrawal-versus-result,
  duplicate result, reset, disclosure update, another scene, root alias/root
  substitution, same-root accepted-file withdrawal/corruption/deletion or
  unavailability, cancellation, and non-cooperative late completion.
- Test the containing-app executor for a closed pre-launch permit, cancellation
  before launch and during result handoff, discarded late completion,
  normalized thrown failure, exactly-once consumption, all three provider
  stages, and payload/redaction canaries. Prove that no asynchronous local
  persistence operation executes inside the consent-consumption closure.
- Test fresh-container canonical-root bootstrap, owner-only mode, symlink/path
  substitution, bounded interrupted syscalls, and fail-closed bootstrap errors.
- Test public state, errors, reflection, logs, and diagnostics with forbidden
  canaries. No normal test uses a real API key, microphone, or live OpenAI call.
