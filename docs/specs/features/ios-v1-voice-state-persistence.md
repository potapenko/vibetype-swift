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
- `failed`: the user may explicitly Retry or Discard;
- `acceptedCleanup`: Latest was committed and only local History/cleanup work
  may remain.

No durable record stores a credential, prompt, provider body, raw provider
response, or accepted/failed History transaction capability.

## User Flow

- A completed capture becomes Pending before the first provider request.
- Only one Pending attempt may own audio. A second recording stays unavailable
  until the first attempt is accepted and cleaned up or explicitly discarded.
- Provider failure leaves the exact Pending attempt available for Retry or
  Discard when the audio is still usable.
- Cancellation never silently discards a durable Pending attempt. If the
  interrupted flow reports recoverable Pending audio, the UI exposes the same
  Retry or Discard choice.
- Retry is always explicit, uses current settings, and starts one fresh
  provider operation.
- Discard removes only the exact Pending metadata and audio. It never changes
  Latest Result or compact History.
- A successful provider result commits Latest before compact History append is
  attempted. History failure is a nonblocking local warning.
- Pending metadata and audio cleanup continue after the History attempt,
  whether History succeeds, is disabled, or fails.
- Once Latest is committed, a local cleanup failure never hides or rolls back
  that result. The UI may show a nonblocking cleanup warning while relaunch or
  a later lifecycle opportunity retries only the remaining local cleanup.
- Clear Latest is idempotent and never changes an unrelated Pending attempt.

## Relaunch And Recovery

- Relaunch performs local reconciliation only and makes zero provider calls.
- A relaunched `processing` attempt becomes recoverable `failed`; the user
  chooses Retry or Discard.
- A relaunched `acceptedCleanup` attempt may idempotently append the matching
  Latest result to enabled compact History, then finish exact local cleanup.
- Local reconciliation never repeats provider work, never duplicates a
  History entry, and never retains Pending solely because History is
  unavailable.
- Corrupt, unsupported, oversized, locked, or otherwise uncertain state is
  visible as local recovery failure. It blocks a second recording and
  preserves source bytes whenever safe absence cannot be proved.

## Storage And Privacy

- Voice metadata is one bounded, app-private atomic record. The actor that
  owns it serializes every mutation.
- Pending audio is app-private, protected, backup-excluded, and addressed only
  through the exact Pending identity.
- Canonical Latest and all Pending metadata remain app-private, protected, and
  backup-excluded. The app may derive only the bounded accepted-text projection
  allowed by `ios-v1-release.md` for explicit keyboard insertion.
- That separate app-written, extension-read-only keyboard snapshot is the only
  App Group text record. It contains one 10-minute Latest item and at most five
  accepted texts with a 24-hour expiry, never Pending state or the canonical
  History record.
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
- relaunch before provider, during provider, after Latest, and after History,
  with zero automatic provider calls;
- idempotent History reconciliation and Latest Clear;
- one-Pending admission and corrupt/unavailable-state preservation;
- atomic-write failure leaves the last confirmed state unchanged.

Signed-device qualification remains necessary for real Data Protection and
process-eviction behavior.
