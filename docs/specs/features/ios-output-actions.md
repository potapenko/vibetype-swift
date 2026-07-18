# iOS Output Actions

Status: legacy automatic-delivery contract. V1.1 does not use automatic
insertion, acknowledgement, or wrong-field matching; current Latest and
explicit Insert behavior is governed by `ios-v1-release.md`.

## Goal

Define how final accepted HoldType text becomes recoverable and reaches an iOS
destination without guessing the previous app or inserting a late result into
the wrong field.

Output delivery must prefer safety over seamlessness. Automatic insertion is
on by default as a preference, but it becomes eligible only after the
bidirectional acknowledgement gate passes and the current keyboard target can
be matched conservatively.

## Scope

- final accepted text and output intent;
- latest and pending result behavior;
- containing-app practice, Copy, and Share actions;
- keyboard automatic and explicit insertion;
- insertion identity, acknowledgement, duplicate prevention, and Undo;
- recovery when the keyboard, target, bridge, or app lifecycle changes.

## Non-goals

- transcription, correction, or translation request internals;
- durable transcript-history and recording-retention policy;
- rich text, templates, snippets, or an external-app editor;
- a general clipboard manager;
- automatic keyboard selection, app launch, host-app identification, or return
  to the previous field;
- writing text from the containing app into an unrelated external app.

## Accepted Output

- Only trimmed, non-empty final text is eligible for output.
- Normal sessions output the accepted transcription after configured local and
  optional correction stages.
- Translation-mode sessions output only successful final translated text. A
  failed translation must not silently insert, copy, share, or save the
  untranslated transcript as though translation succeeded.
- The output record carries one session identity and one transcript identity.
  Repeated provider responses or bridge refreshes for those identities must not
  create additional accepted outputs.
- Raw provider responses, pre-correction text, prompts, audio, API keys, and
  surrounding host text are not output records.

## Defaults

- `Insert automatically when the current target matches` is on by default.
  The preference does not bypass the eligibility and gate rules below.
- `Keep latest result` is on by default and does not write to the system
  clipboard automatically.
- Normal literal dictation with punctuation is the default output intent.
- The Translate action remains visible and tappable while its target
  configuration is incomplete. Voice and Keyboard route that tap to the exact
  Translation setting that needs attention; no partial output work starts.
- Copy and Share always require explicit user action.

## Runtime Output Adapter Request

`OutputDeliveryRequest` is the transient containing-app input to one platform
output adapter call. It contains exactly one validated `AcceptedTranscript`
and one `OutputDeliveryPreferences` value. It is created only after the final
normal, corrected, or translated text has been accepted; provider failure,
empty final text, or required Translation failure creates no request.

The request preserves both preference intents exactly. Automatic insertion
preference is not target eligibility, authorization, a pre-insert claim, or
proof that insertion was attempted. Keep Latest Result is not proof that the
mandatory delivery record or History write committed. A failed-attempt Retry
in Save Only mode forces only automatic insertion preference off and preserves
the current Keep Latest Result preference. Follow Automatic Insertion uses both
current preferences unchanged.

This value is runtime-only, `Equatable`, `Sendable`, and non-Codable. It has no
session, transcript, document, target, or retry identity; output intent;
timestamp or expiry; delivery state; recovery destination; authorization;
acknowledgement; platform result; or user-facing copy. It is not the protected
app-private delivery record, an App Group snapshot, a keyboard command, or an
insertion claim. The platform adapter result and macOS accessibility/AppKit
behavior remain platform-owned.

## Containing-App Actions

- The Voice destination shows the final accepted result and may place it in
  HoldType's own practice/editor field.
- Copy writes only the selected accepted text to the system clipboard after an
  explicit tap. It does not count as insertion, alter insertion identity, or
  start provider work.
- Share exposes only the selected accepted text or an explicitly selected
  app-owned recording. Cancelling Share does not delete or consume the result.
- The Latest Result card on Voice provides `Clear Latest Result` for a terminal
  result. After confirmation, the app first revokes any bridge projection and
  proves that no matching accepted-History outbox membership still needs the
  terminal marker. It then removes only the app-private latest record and
  leaves any durable History row, recording cache, usage, and API key
  unchanged. If that local reconciliation is uncertain, the result remains
  recoverable and the action reports a retryable local error instead of
  claiming that it was cleared.
- While keyboard delivery is still pending, that action is labelled `Cancel
  Delivery and Clear Latest`. Confirmation first makes the app-owned bridge
  result ineligible and schedules its physical cleanup, then clears the latest
  record. It still does not delete History or independently retained audio.
- The containing app may publish an accepted result for keyboard delivery, but
  it cannot insert into the previously active external app or return the user
  there automatically.
- Turning Keep latest result off disables post-session latest-result retention;
  it does not allow HoldType to discard an in-flight accepted result before its
  current delivery or recovery decision finishes.
- Latest result is independent of History. Clearing or disabling History does
  not silently rewrite the current latest result, and Copy does not create a
  History entry by itself.
- History cutover may cancel only a stale unresolved nested `historyWrite`
  marker. It does not clear accepted text, change delivery or publication state,
  revoke bridge eligibility, or consume Copy/Share/Latest recovery. A cleanup
  failure therefore remains app-private History maintenance and is not a failed
  output action.
- The keyboard never receives the History enabled state, policy generation,
  rows, receipts, or cleanup status. Clear History is not a keyboard command and
  never writes an App Group snapshot.

### P4 App-Only Delivery

- P4 commits the mandatory app-private accepted-output record before presenting
  `resultReady`. The record remains `pending`, has publication generation `0`,
  carries `historyWrite: null`, and captures automatic-insertion preference as
  false regardless of the saved future preference. P4 does not mutate that
  saved preference.
- P4 performs no App Group publication, insertion claim, acknowledgement,
  accepted-History write, failed-History write, or History-outbox operation.
  Successful normal or Retry output ends at app-owned result presentation.
- Voice presents the exact accepted text as selectable content with explicit
  `Copy`, `Share`, `Use in Practice`, and `Clear Latest Result`. It never labels
  Clear as `Cancel Delivery and Clear Latest`, because keyboard delivery does
  not exist in this milestone.
- Copy writes the exact accepted text only after the tap. P4 Share contains only
  that text. Failure or cancellation changes no delivery state and removes no
  recovery owner.
- Use in Practice replaces only HoldType's app-owned practice-field draft with
  the exact accepted text. It does not touch the clipboard, write outside
  HoldType, acknowledge insertion, or consume the accepted result.
- Clear Latest Result is confirmed. Before clearing, P4 proves that the exact
  `PendingRecording.outputDelivery` owner no longer depends on this delivery.
  An exact generation-0, never-published, `historyWrite: null` record requires
  no bridge or outbox operation. A failure before a confirmed discarded
  tombstone keeps the result visible. Once that tombstone is durably confirmed,
  the UI clears the text even if physical unlink is still cleanup-pending; it
  never reconstructs text from a tombstone. Commit uncertainty first reconciles
  the intended tombstone bytes and shows a retryable local error until the
  logical state is known.
- Physical cleanup after a confirmed tombstone accepts no caller payload and
  returns no content. The store validates the current canonical tombstone and
  internally derives its opaque expectation; it cannot accept or reconstruct
  accepted text, remove a newer active record, turn the tombstone visible again,
  or grant Copy, Share, or Use in Practice.
- Keep Latest Result off never bypasses the mandatory record or removes text
  while the current app-only result or recovery decision is unresolved. With no
  P4 insertion acknowledgement, the result remains recoverable until confirmed
  Clear, atomic replacement by a newer accepted result, or the 24-hour safety
  expiry. P4 does not expose a control for changing this preference.
- Replacing an existing P4 latest result is one fail-closed atomic old-to-new
  delivery operation. It never clears the previous record first and never
  presents the new result until its durable replacement is confirmed. While the
  new attempt remains in `Saving Result`, the prior confirmed and unexpired
  result may remain visible. Failed invisible replacement preserves that prior
  result; ambiguous replacement blocks another destructive mutation. A
  discarded, expired, or tombstoned predecessor never returns as prior text.

### Frozen P5H Accepted-History Activation

P5H-0 leaves the P4 `historyWrite: null` path active. P5H-2 introduces a named
History-aware foreground mode and its accepted/failed ownership internals, but
production continues to select disclosure version `1` and the app-only mode.
P5H-3 adds the combined local History facade/state owner under the same inactive
boundary. P5H-4 first lands native History plus Storage & Recovery controls,
then atomically makes the captured mode production, makes provider disclosure
version `2` current, and publishes the version-2 copy. P5H-2 through P5H-4 are
one non-release-qualified train until this final activation passes.

- After the P5H-4 activation, before provider work, the app obtains current
  version-2 provider authority; separately, the History coordinator captures
  the canonical enabled state and generation needed by accepted-output
  preparation.
- With History enabled, the mandatory delivery record carries the captured
  pending History write and the coordinator attempts the accepted row before
  result publication. With History disabled, the record retains a null History
  write and remains the independent Latest/Pending recovery destination.
- A History append failure after mandatory delivery commit is a visible
  non-blocking History warning. It retains exact local outbox/recovery work and
  never repeats transcription, correction, or Translation.
- P4 results are not backfilled, and enabling History later does not create rows
  for an older Latest Result.
- Copy, Share, Clear Latest, History Delete, Clear History, and the History
  toggle remain distinct explicit local actions; none grants provider consent
  or writes a keyboard/App Group command.

## Latest And Pending Result Lifetime

- Before any keyboard publication or other output handoff, the containing app
  persists the accepted result in an app-private, versioned delivery record
  with Data Protection. It contains the session/transcript identity, final
  accepted text, output intent, creation/expiry dates, and delivery state; it
  contains no audio, key, prompt, host text, or provider payload.
- This record survives process relaunch so output failure cannot lose newly
  accepted text. It is excluded from device backup and physically removed when
  its retention ends at the containing app's next lifecycle opportunity.
- With `Keep latest result` on, the newest final result remains available for
  24 hours, until a newer result replaces it, or until the user explicitly
  clears it. Expiry is enforced at read time and followed by physical deletion
  at the first app maintenance opportunity.
- Turning `Keep latest result` off applies the preference immediately and
  prevents future post-session retention. Cleanup of an already-terminal
  latest result follows the same bridge-revocation and accepted-History outbox
  guard as explicit Clear Latest; until it succeeds, the result remains a
  recoverable local cleanup item rather than being reported as retained by
  preference. A `submittedUnverified` result remains recoverable until explicit
  clear, replacement, or the 24-hour cap because automatic replay is forbidden
  and insertion success is unknown. A result whose delivery decision is still
  pending remains only until insertion is reconciled, the user explicitly
  dismisses/discards it, or the 24-hour safety cap expires.
- The protected pending/latest delivery record is the mandatory pre-handoff
  recovery and commits before any short-lived keyboard snapshot. When History
  is enabled, normal acceptance stores `historyWrite.state: pending` and also
  attempts its accepted row before publication. A History append failure does
  not suppress an otherwise durable result: output may continue with a visible
  non-blocking History error and the structured History-write object on the
  delivery record. In the narrow proof-bound replacement path, only the
  delivery store may mint `pendingReplacement` after the old pending payload is
  durable in outbox; callers cannot request or construct it. Both unresolved
  states retain the captured policy generation and accepted-row metadata and
  move only to `committed` or `cancelled`; neither is a Boolean or disappearing
  marker. Before Clear Latest, replacement, or non-retention could remove a
  delivery with unresolved History work, the app must durably transfer exact
  ownership to the bounded History outbox or fail closed.
  The app retries only local metadata persistence, never provider work. If the
  mandatory delivery record fails, the new accepted text is not published and
  the journaled attempt remains recoverable. An independently existing prior
  valid Latest Result is not erased by that failure. The exact contract is frozen in
  `ios-accepted-output-delivery-record.md`.

## Keyboard Insertion

- The keyboard inserts text only while HoldType is the active keyboard
  extension in an editable host field.
- Automatic insertion requires all of the following:
  - the production acknowledgement contract and its Full Access disclosure
    have passed M0C;
  - the current result explicitly carries
    `automaticInsertionAuthorized: true` from the containing app;
  - the shared record is supported, unexpired, and contains accepted text;
  - delivery, session, attempt, transcript, and committed publication
    generation match the active delivery;
  - a non-empty source document identifier was captured for the session;
  - the current non-empty document identifier still matches it;
  - the delivery ID has not already received a durable pre-insert claim.
- A document identifier is only a conservative guard. It is not proof of the
  host app, field, cursor position, or user intent.
- If any automatic-insertion condition is missing, HoldType keeps the result
  recoverable and offers explicit keyboard Insert or containing-app Copy where
  the platform and approved bridge allow it.
- Keyboard delivery is limited to 8,192 UTF-8 bytes. A larger accepted result
  remains app-private for Copy/Share recovery and is never inserted in chunks;
  partial chunk delivery would make the insertion outcome ambiguous.
- Explicit Insert is a user confirmation to place the displayed accepted text
  into the field that is active at tap time. It may proceed after a missing or
  changed document identifier, but only while HoldType is visibly active and
  the user can see which result is being inserted.
- One Insert attempt consumes the primary Insert action for that delivery
  across keyboard presentations. Before calling `insertText`, the extension
  atomically records a pre-insert claim in its own sandbox. The bounded ledger
  contains only delivery ID, claim time, and `claimed`, `confirmedInserted`, or
  `submittedUnverified` status; it stores no text or host identity, retains at
  most 512 live IDs, prunes entries after 24 hours, uses Data Protection, and is
  excluded from device backup. A 513th unexpired live claim fails closed; the
  extension never evicts an unexpired duplicate barrier to make room.
- `UITextDocumentProxy.insertText` has no success return. After the call returns,
  the extension may mark `confirmedInserted` only when the same non-empty
  document identifier is still present and the immediately available local
  `documentContextBeforeInput` ends with the exact submitted text. That context
  is compared in memory only and is never persisted, logged, published, or sent
  to a provider.
- If post-insert identity/context is absent, truncated, changed, or does not
  match, the outcome is `submittedUnverified`, not inserted or failed. The UI
  says delivery could not be verified, keeps app-owned recovery, and never
  automatically replays the transcript.
- Accepted text with bidirectional controls is displayed as isolated plain text,
  never interpolated into a status/action label, Markdown, or format string.
- A claimed delivery is never inserted automatically again after refresh,
  reappearance, eviction, or restart. If the extension is interrupted after
  claiming but before it durably records a terminal outcome, the surviving
  `claimed` state is treated as delivery uncertain and directs the user to
  inspect the field or recover the result in HoldType; it does not guess and
  repeat the insertion.
- If the consumed ledger cannot be durably updated, keyboard insertion is
  disabled for that attempt. The containing app's Copy and Share recovery
  remain available.
- Without Full Access, the keyboard remains usable for ordinary typing and may
  explicitly insert a valid read-only result after the M0B read path is proven.
  It cannot send start, stop, or insertion acknowledgement commands to the app,
  so automatic insertion remains unavailable.
- After `confirmedInserted`, the keyboard presents a short Undo opportunity.
  Undo is unavailable for `submittedUnverified` and is available only while the
  same target context still ends with the exact just-inserted text; otherwise it
  disappears without editing another field.
- Copy is always available in the containing app. A keyboard-level Copy action
  is unavailable without Full Access and must not ship until physical-device
  QA proves explicit `UIPasteboard` use under the M0C disclosure; otherwise the
  keyboard directs the user to open History or Latest Result in HoldType.

## Acknowledgement And Recovery

- Automatic insertion must not ship until the shared-state contract includes
  idempotent insertion acknowledgement.
- An acknowledgement identifies the delivery, session, attempt, transcript,
  durable publication generation, source document, and one honest outcome:
  `confirmedInserted` or `submittedUnverified`. It never
  turns a void API call into a success claim and never copies transcript text
  into logs. The
  extension-local pre-insert claim is the at-most-once guard; the App Group
  acknowledgement reconciles app recovery state but is not the first or only
  duplicate barrier.
- A missing or delayed acknowledgement must never trigger a second insertion.
  The keyboard suppresses duplicates locally while visible, and the app keeps
  the result recoverable until delivery is reconciled.
- The containing app applies an acknowledgement only when every immutable
  identity and the current publication generation match. Older-generation,
  cross-attempt, or cross-delivery acknowledgements are harmless no-ops.
- If eligibility fails before the pre-insert claim/call, no insertion was
  attempted and the user may retry explicitly after fixing the target. If the
  call was made but the result cannot be confirmed, use the non-replayable
  `submittedUnverified` recovery above; HoldType does not claim to detect host
  rejection from a void API.
- If the result arrives while HoldType Keyboard is not active, it remains
  pending. HoldType does not open another app, select a keyboard, or guess a
  target.
- While a visible voice action is `listening` or `processing`, the extension
  checks the app-owned snapshot on a bounded local cadence and on normal text-
  context callbacks until a result, failure, cancellation, or expiry appears.
  It stops the cadence when hidden or idle. App Group writes never claim to wake
  an evicted or suspended extension.
- This historical automatic-delivery result may expire before insertion. That
  expiry does not govern the current explicit `Latest` action, which follows
  accepted History without an independent age limit.
- The app physically clears acknowledged, cancelled, replaced, and expired
  accepted-result snapshots plus temporary atomic-write files under
  `ios-keyboard-shared-state.md`; logical ineligibility alone is not retention.
- Copy or Share does not acknowledge insertion or consume a pending insert.
- Dismissing a failure hides the message but must not delete recoverable text or
  audio as a side effect.

## Invariants

- No output path uses a private automatic-return API or claims to know the
  previous host app.
- No automatic insertion occurs with a missing or changed document identifier,
  an expired result, an inactive HoldType keyboard, or an already claimed
  transcript.
- No accepted result is inserted twice because of refresh, retry, process
  restart, or a late provider response.
- Automatic insertion, latest-result retention, History, Copy, and Share are
  separate behaviors and controls.
- The system clipboard is never used as bridge transport, fallback storage, or
  an automatic side effect.
- Output actions and acknowledgements never default-log transcript text, host
  context, ordinary keystrokes, API keys, prompts, audio, or provider payloads.
- Secure fields, selected phone fields, and hosts that reject third-party
  keyboards are platform limitations, not successful delivery.

## Edge Cases And Failure Policy

- Empty or whitespace-only text produces no output action and leaves the
  previous accepted result unchanged.
- If the field, app, cursor context, or keyboard changes while provider work is
  running, automatic insertion is disabled for that result.
- If the user explicitly inserts after a target change, the tap targets only
  the currently visible editable field; HoldType does not claim it is the
  original field.
- If the host field becomes unavailable during Insert, retain the result and
  show recovery instead of falling back to automatic clipboard writes.
- If Copy or Share fails or is cancelled, retain the result and leave insertion
  eligibility unchanged.
- If Full Access is revoked during a session, stop bidirectional commands,
  preserve ordinary typing, and fall back to read-only/manual delivery where
  proven.
- If the bridge record is missing, corrupt, incompatible, or expired, do not
  insert and do not expose raw decoding data in the error.
- If the containing app or extension is evicted, reconcile the latest session,
  transcript, local pre-insert claim, and acknowledgement identities before
  offering another action.
- If Undo can no longer prove that it would remove only the last HoldType
  insertion, it safely becomes unavailable.

## Route, State, And Data Implications

- Output presentation distinguishes pending, automatically eligible, explicit
  action required, confirmed inserted, submitted unverified, recoverable
  pre-attempt failure, and expired.
- Setup errors route to their owning section: OpenAI, Transcription,
  Translation, Keyboard, Full Access, or microphone/privacy.
- The containing app owns complete accepted text and longer-lived recovery. The
  keyboard sees only the bounded accepted-result snapshot required for current
  delivery.
- Pending result, latest result, History entry, and insertion acknowledgement
  have independent lifetimes.
- Accepted-result delivery expiry and snapshot expiry are distinct from Quick
  Session expiry and the utterance duration limit.
- `VoiceAttemptStage.outputDelivery` identifies only the controller operation
  that passed a runtime `OutputDeliveryRequest` to a platform output adapter.
  Eligibility, the pre-insert claim, acknowledgement, `confirmedInserted`,
  `submittedUnverified`, recovery, and expiry remain owned by the concrete
  accepted-result, claim-ledger, acknowledgement, and bridge records. The
  contract does not introduce a second observer-wide delivery enum. A
  delivery-stage failure never recreates provider work or becomes a failed
  transcription History row.
- The production bridge must define bounded expiry before automatic insertion
  is enabled.

## Verification Mapping

- Pure coverage should verify normalization, default settings, eligibility,
  missing or changed identity, expiry, duplicate suppression, local suffix
  confirmation, unverified submission, and truthful acknowledgement.
- Bridge coverage should verify late results, delayed or missing
  acknowledgements, corrupt records, process restart, durable pre-insert claims,
  uncertain delivery, and Full Access revocation without duplicate insertion.
- Containing-app coverage should verify practice-field output, explicit Copy
  and Share, both Clear Latest states, latest-result independence from History,
  and absence of external-app insertion.
- Physical-device QA must cover representative hosts, secure and phone fields,
  host rejection, keyboard switching, process eviction, explicit Insert,
  automatic insertion, and Undo.

## Gates And Deferred Decisions

- M0B must prove the read-only accepted-result path before manual keyboard
  delivery is treated as supported.
- M0C and an updated `ios-keyboard-shared-state.md` must pass before extension
  writes, automatic insertion, or cross-process acknowledgement are enabled.
- Historical automatic-delivery expiry follows its shared-state contract. The
  current explicit `Latest` action instead follows accepted History without an
  independent expiry. The exact Undo duration is chosen with production
  keyboard interaction QA.
- Durable history retention follows `ios-history-and-storage.md`; the latest
  result remains a separate delivery state.
