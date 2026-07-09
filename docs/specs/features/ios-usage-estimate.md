# iOS Transcription Usage Estimate

## Goal

Show a transparent device-local estimate of successful OpenAI audio
transcription usage without presenting it as an invoice, account balance, or
complete provider-usage dashboard.

## Scope

- one local event for each successful audio transcription
- today, recent daily average, last-30-day total, and projected 30-day cost
- daily cost/minutes chart
- known, unknown, and mixed local pricing behavior
- bounded versioned persistence, empty/error states, and Reset

## Non-goals

- OpenAI billing, usage, balance, or account API calls
- correction or translation token/cost estimates
- failed, rejected, empty, locally invalid, or cancelled-before-acceptance
  transcription attempts
- raw audio, transcript text, prompts, dictionary content, credentials, or
  provider payloads in usage records
- analytics, telemetry, cloud sync, or cross-device aggregation

## Recording Contract

- A successful provider transcription records exactly one event after a
  non-empty transcript is accepted from the transcription stage. Later local
  cleanup, correction, translation, output delivery, or History failure does
  not create a second audio-usage event.
- The containing app creates the usage handoff immediately after accepting that
  non-empty provider transcript and before correction, translation, History,
  or output delivery. A later failure in any of those stages does not revoke
  the already successful audio transcription or create another handoff.
- A successful explicit retry with valid positive finite duration metadata
  records one event for that new provider transcription. A failed retry or one
  cancelled before acceptance records none. Cancellation after its
  transcription was already accepted does not revoke that event. A successful
  legacy retry with missing or invalid duration still returns its text but
  creates no invented usage event.
- Before each actual audio-transcription provider request, the containing app
  creates one local transcription UUID. Callback duplication or replay for
  that request reuses the UUID; every new provider request, including an
  explicit Retry, gets a new one. Correction, translation, History, and output
  retries never get audio-transcription IDs.
- The portable handoff contains only that local idempotency UUID, the
  lowercased surrounding-whitespace-trimmed model, and a finite audio duration
  greater than zero. Empty models, zero or negative durations, NaN, and
  infinite durations are invalid and produce no event; rejection is
  non-blocking for the accepted transcript.
- The handoff is an `Equatable`, `Sendable`, runtime-only non-Codable value. It
  has no timestamp, price, persistence, transcript, prompt, provider payload,
  credential, or keyboard/App Group meaning. The UUID is not a provider,
  analytics, session, document, or account identifier. The containing-app usage
  repository uses it as the event ID, adds time and the frozen local price
  snapshot, and treats a repeated UUID as an idempotent no-op.
- Each event contains only a local ID, timestamp, normalized transcription
  model, positive audio duration, optional known USD-per-minute price, optional
  calculated cost, and optional local pricing-source/version label.
- The event freezes the known rate used at recording time. Later price-table
  updates do not silently rewrite historical estimates.

## User-Visible Behavior

- Settings labels the destination `Transcription Usage Estimate` and explains
  that values come only from successful transcriptions made by this device.
- The summary shows `Today`, `Average per day`, `Last 30 days`, and `Estimated
  30-day cost`. Duration is always available in minutes when valid events
  exist.
- The recent average uses the elapsed calendar days from the first event in the
  30-day window through today, with at least one day. Projection is that recent
  known-cost daily average multiplied by 30; it is not a promise about future
  use.
- A segmented daily chart switches between estimated cost and audio minutes
  over the same 30-day calendar window.
- If every event uses an unknown model price, cost is `Unavailable` while
  minutes remain visible. If known and unknown prices are mixed, known cost may
  be shown only with a clear `partial` warning; unknown minutes are never priced
  by guessing.
- With no events, the surface says that an estimate appears after successful
  transcriptions. A storage/decode failure shows a local error rather than an
  empty-success state.
- `Reset Usage Estimate` requires destructive confirmation, removes only local
  usage events, and immediately returns this surface to its empty state. It does
  not change the API key, settings, History, latest result, recordings, cache,
  consent, or any external OpenAI data.

## Persistence And Privacy

- The containing app is the only writer. Events use versioned app-private
  persistence with Data Protection and retain at most the most recent 365
  calendar days.
- Before dispatching a replayable provider request, the pending-attempt journal
  durably stores its local transcription UUID. Replaying the same accepted
  handoff reuses that UUID; only a genuinely new provider request allocates a
  new one.
- Usage data is excluded from device backup and never enters App Group,
  Keychain, the keyboard extension, logs, diagnostics, or exports by default.
- Normal app use and automated tests never call a live provider billing or
  usage endpoint.

## Invariants

- Newly created handoffs and events require finite, strictly positive audio
  duration, and cost is never invented for an unknown model. Legacy decoded
  zero, negative, or non-finite events are quarantined or migrated by the
  versioned repository before they enter summaries; they are never silently
  clamped into new valid events.
- One successful audio request produces at most one event even after callback
  duplication, lifecycle replay, or output retry.
- Correction and translation requests do not affect this estimate until a
  separate token-estimate contract is approved.
- Reset isolation is exact and a failed reset does not pretend the events were
  removed.

## Edge Cases And Failure Policy

- Unsupported schema or corrupt storage produces a recoverable local error and
  preserves the source for bounded recovery; it is not silently overwritten.
- A failed append leaves the successful dictation/output available and shows a
  non-blocking estimate-storage error.
- Calendar/time-zone changes regroup the 30-day presentation by the current
  local calendar without changing event timestamps or duplicating events.
- A future pricing-table update applies only to new events unless a separate
  migration contract explicitly says otherwise.

## Verification Mapping

- Test exactly-once success/retry recording and exclusion of every failed,
  cancelled, duplicate, correction, and translation path.
- Test today, elapsed-day average, 30-day window, projection, daily buckets,
  time zones, known/unknown/mixed pricing, and frozen historical rates.
- Test 365-day pruning, migrations, corrupt storage, append/reset failures,
  confirmation, and reset isolation.
- Inspect fixtures and stores for all forbidden content and prove normal tests
  make no live billing/usage request.

## Unknowns Requiring Confirmation

- Correction and translation token estimates require a separate product and
  pricing contract.
