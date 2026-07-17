# iOS V1.1 Voice State Persistence

Status: approved product contract; 2026-07-13.

This spec narrows the Pending and Latest Result portions of
`ios-v1-release.md` into one replacement contract. It supersedes the legacy
transactional Pending, accepted-output delivery, accepted History, and failed
History contracts for V1.1. Compact successful-text History remains a separate
repository and screen.

## Goal

Preserve one unfinished foreground dictation and one accepted result across
process loss without replaying remote work or retaining a multi-record
transaction system.

## Durable State

The containing app owns at most:

- one Pending attempt with a stable attempt identifier and one protected audio
  file;
- one Latest Result with result identifier, source attempt identifier,
  accepted text, and creation date;
- one separate compact History record governed by `ios-v1-release.md`.

Pending has four local meanings:

- `ready`: audio is durable and may be sent only by an explicit active flow;
- `processing`: a provider operation started in this process;
- `failed`: audio remains available, while Retry is offered only when durable
  evidence proves which provider or local stage is safe to resume;
- `acceptedCleanup`: Latest was committed and only local History/cleanup work
  may remain.

After transcription succeeds, Pending durably keeps the accepted normalized
transcript, its operation identifier, the current downstream text, and one
stage boundary:

- `transcriptionAccepted`: transcription is complete; correction or local
  post-processing may begin without retranscribing audio;
- `correctionInFlight`: correction was launched but its outcome is unknown;
  retry fails open from the pre-correction text and never repeats correction;
- `translationReady`: local text is ready for one explicit translation attempt;
- `translationInFlight`: translation was launched but its outcome is unknown;
  the attempt is blocked from provider replay and remains Play/Discard only;
- `outputReady`: final text is durable and acceptance resumes locally without
  provider configuration, consent, or credentials.

The accepted-transcription checkpoint is committed before correction,
translation, or output delivery begins. If that checkpoint cannot be confirmed,
the attempt fails locally and transcription is never repeated automatically.

Capture metadata stores the 1-15 minute recording limit frozen at Start. Older
capture schemas without that field migrate as five-minute attempts. Recovery,
duration validation, and protected limit-ended retention always use this stored
value rather than the current Settings value.

Pending also records accepted-audio retention ownership. Ordinary success
follows the optional Recording Cache policy. A selected-limit automatic Finish,
or canonical finalized media within 500 milliseconds of that attempt's frozen
boundary when Done wins the stop race, uses protected limit-ended retention.
This does not change provider
eligibility or create a separate provider state.

No durable record stores a credential, prompt, provider body, raw provider
response, or accepted/failed History transaction capability. Only the bounded
normalized text and stage evidence above survives process loss.

## User Flow

- A completed capture becomes Pending before the first provider request.
- Reaching the selected recording limit closes capture and follows the same
  completed-capture
  path. It becomes Pending, then starts the normal provider operation exactly
  once.
- Only one Pending attempt may own audio. A second recording stays unavailable
  until the first attempt is accepted and cleaned up or explicitly discarded.
- Provider failure leaves the exact Pending attempt and usable audio visible.
  It offers Retry only when the last confirmed stage is safe to repeat or
  resume; an outcome-unknown provider stage offers Play and Discard instead of
  pretending that a retry is safe.
- The containing app may expose an opaque local Play capability for the exact
  Pending audio. UI never receives or stores the protected file URL.
- Cancellation never silently discards a durable Pending attempt. If the
  interrupted flow reports recoverable Pending audio, the UI exposes the same
  Retry or Discard choice.
- Retry is always explicit. It either finishes entirely from a durable local
  checkpoint or uses current settings for only the next confirmed-safe provider
  stage. It never repeats a completed or outcome-unknown provider operation.
- Discard removes only the exact Pending metadata and audio. It never changes
  Latest Result or compact History.
- A successful provider result commits Latest before compact History append is
  attempted. History failure is a nonblocking local warning.
- Pending metadata and audio cleanup continue after the History attempt,
  whether History succeeds, is disabled, or fails.
- After protected limit-ended success, acceptance publishes the exact audio to
  the bounded `saved-v1-*` namespace before unlinking Pending. Publish failure
  leaves `acceptedCleanup` and its only source intact; Latest may remain ready,
  but the app must not show a Saved Recording until publication succeeds.
- Once the exact Saved Recording is confirmed by result identity, protected
  namespace, media extension, and byte count, it independently owns the audio.
  Before relying on that retained copy, cleanup still reconciles the bounded
  Saved Recording set; reconciliation failure preserves `acceptedCleanup` for
  a later retry. If Pending unlink succeeds but the final metadata write fails,
  relaunch accepts the missing Pending source, preserves the playable Saved
  Recording, and completes only the remaining metadata cleanup.
- Once Latest is committed, a local cleanup failure never hides or rolls back
  that result. The UI may show a nonblocking cleanup warning while relaunch or
  a later lifecycle opportunity retries only the remaining local cleanup.
- Clear Latest is idempotent and never changes an unrelated Pending attempt.

## Relaunch And Recovery

- Relaunch performs local reconciliation only and makes zero provider calls.
- Before the ordinary process-launch observation, one bounded orphan repair
  examines only canonical `recording` or `finalizing` capture metadata and its
  exact descriptor-open source. Any non-empty regular source below the bounded
  audio-size limit becomes a durable `completed` capture; a measured value
  below 300 milliseconds, beyond the finalized-media bound, invalid media
  metadata, or a validator timeout stores duration `0` as the internal
  unknown/suspect marker. The two-second validator remains the maximum wait.
- Exact empty or descriptor-proven absent orphan media is classified
  Discard-only without automatic deletion. Oversized media, protected-data
  unavailability, source uncertainty, or an atomic metadata-write failure
  remains blocked and retriable at a later
  process launch. No launch-repair classification deletes source bytes.
- Unknown/suspect completed audio remains visible with Play and explicit
  Transcribe/Discard. It never starts a provider request automatically; an
  explicit Transcribe/Retry may admit the descriptor-validated non-empty source
  exactly once while accepted usage duration remains unknown. If that attempt
  succeeds, the audio uses bounded Saved Recording retention (newest five), not
  the optional Recording Cache policy, because unknown duration may conceal the
  selected recording boundary.
- Foreground opportunities do not run orphan repair. They only observe the
  durable state left by live capture or process-launch recovery.
- A relaunched transcription with no accepted-transcription checkpoint becomes
  `failed` with provider replay blocked. The audio remains visible with Play and
  Discard, but the app never uploads it again because the prior transcription
  outcome is unknown.
- The same replay block is committed immediately when a live provider dispatch
  ends in timeout, transport loss, or cancellation without a definitive remote
  response. Relaunch preserves that non-retryable classification; it does not
  downgrade the row to an ordinary failed Retry.
- A relaunched downstream `processing` attempt becomes `failed` while retaining
  its exact checkpoint. `correctionInFlight` resumes fail-open locally,
  `translationReady` may start translation only after explicit Retry,
  `translationInFlight` remains Play/Discard only, and `outputReady` resumes
  acceptance locally.
- A relaunched `acceptedCleanup` attempt may idempotently append the matching
  Latest result to enabled compact History, then finish exact local cleanup.
- For protected limit-ended audio, that cleanup first retries only the local
  Saved Recording publication. It never re-enters provider processing.
- Local reconciliation never repeats provider work, never duplicates a
  History entry, and never retains Pending solely because History is
  unavailable.
- Corrupt, unsupported, oversized, locked, or otherwise uncertain state is
  visible as local recovery failure. It blocks a second recording and
  preserves source bytes whenever safe absence cannot be proved.
- A finalized media duration slightly beyond the frozen recorder deadline is
  valid through that limit plus two seconds to tolerate recorder/delegate
  closure latency. The absolute supported ceiling is 902 seconds.
  For bounded positive-byte media beyond that tolerance, live finalization uses
  the clamped monotonic fallback or internal unknown duration `0`; the source
  remains explicit recovery and is never deleted merely for crossing an
  internal duration bound. Oversize or identity/protection uncertainty remains
  blocked.

## Storage And Privacy

- Voice metadata is one bounded, app-private atomic record. The actor that
  owns it serializes every mutation.
- Pending audio is app-private, protected, backup-excluded, and addressed only
  through the exact Pending identity.
- Successful protected limit-ended audio is app-private, protected,
  backup-excluded, independent from Pending and accepted-text History, and
  bounded newest-first to five exact recordings.
- Canonical Latest and all Pending metadata remain app-private, protected, and
  backup-excluded. The app may derive only the single accepted-History
  projection allowed by `ios-v1-release.md` for explicit keyboard insertion.
- That separate app-written, extension-read-only keyboard snapshot is the only
  App Group text record. It contains at most the first accepted History item,
  with no independent expiry, and never additional accepted texts, Pending
  state, or the canonical History record.
- Product logs redact text, paths, identifiers, prompts, provider payloads,
  credentials, and audio contents.

## Legacy Development Data

V1.1 is the first planned iOS release. The replacement uses a new storage
namespace and does not migrate or automatically delete unshipped legacy
Pending, accepted-delivery, accepted/failed History, outbox, generation,
receipt, tombstone, or retry-audio files. Those files are ignored by the new
runtime. Simulator and internal development installs may be reset explicitly
when testing the cutover.

## Verification Contract

Focused tests must prove:

- capture -> Pending -> provider -> Latest -> History -> exact cleanup order;
- success with History enabled, disabled, and failing;
- provider failure, explicit Retry, and exact Discard isolation;
- accepted-transcription checkpoint failure blocks replay of the same audio;
- relaunch during transcription blocks retranscription while preserving Play
  and Discard;
- correction-in-flight retry is local and fail-open, translation-ready retry
  starts only translation, and translation-in-flight never repeats translation;
- output-ready retry commits locally without provider configuration, consent,
  or credentials;
- selected-limit automatic Finish -> Pending -> provider, Pending playback, and
  post-close duration tolerance;
- Done/watchdog stop-authority race near the frozen boundary preserves protected
  retention and dispatches provider work once;
- limit-ended provider failure -> relaunch -> explicit Retry -> success keeps
  the same protected retention and creates one `saved-v1-*` recording;
- failed protected publish keeps `acceptedCleanup` and source bytes, creates no
  false saved row, and relaunch retries no provider work;
- protected publish plus Pending unlink plus failed final metadata write leaves
  one playable Saved Recording, and relaunch completes cleanup without needing
  the already-unlinked Pending source;
- protected publish followed by a failed bounded-cache prune leaves cleanup
  pending, and relaunch completes the prune before unlinking Pending or
  finishing metadata cleanup;
- a same-result, same-size Saved Recording with a different media extension
  never proves publication and never authorizes Pending deletion;
- relaunch before provider, during provider, after Latest, and after History,
  with zero automatic provider calls;
- idempotent History reconciliation and Latest Clear;
- one-Pending admission and corrupt/unavailable-state preservation;
- atomic-write failure leaves the last confirmed state unchanged.

Signed-device qualification remains necessary for real Data Protection and
process-eviction behavior.
