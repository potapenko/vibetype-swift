# iOS Diagnostics

## Goal

Give users and support a local, privacy-conscious way to understand iOS app and
keyboard failures without exposing dictated content or pretending that an app
can browse system-owned iOS crash files.

## Scope

- a Development section at the bottom of Settings with a Diagnostics & Support
  destination
- bounded app-owned runtime logs
- redacted app, device, settings, audio-session, and bridge summaries
- explicit Copy Recent Logs and Share Diagnostic File actions
- locally delivered MetricKit crash and hang diagnostics
- local failure behavior when logs or export are unavailable

## Non-goals

- automatic upload, telemetry, analytics, or account-backed support
- reading or deleting system crash reports from inside HoldType
- collecting broad device or Console logs
- storing transcripts, prompts, dictionary entries, raw audio, API keys,
  keystrokes, host-app identity, or provider payloads
- automatic crash or diagnostic upload
- installing a custom crash handler or claiming access to system-owned iOS
  Analytics Data

## User-visible behavior

- Settings keeps its four top-level app destinations unchanged. Its final
  section is Development, containing one Diagnostics & Support row.
- Diagnostics shows app version/build, iOS or iPadOS version, device family, and
  compact setup status without exposing secrets or user content.
- Diagnostics may show microphone authorization, current audio-session phase,
  last bridge schema/revision/expiry status, and whether Full Access was
  recently verified or is not currently verified.
- It must not claim `Full Access: disabled` from stale containing-app state.
- Recent Runtime Events shows short lifecycle lines such as app launch, voice
  session start/stop/expiry, recording start/stop, provider stage outcome,
  retry, insertion-claim consumption acknowledgement, cache outcome, and export
  outcome.
- Event lines use stable categories and scalar metadata. They never show the
  transcript, prompt, dictionary term, audio path, API key, authorization
  header, ordinary keystroke, surrounding text, or full provider response.
- The portable diagnostics API accepts typed event categories with a closed
  allowlist of scalar fields such as phase, duration bucket, schema version,
  revision, expiry category, retry count, and success/failure category. It does
  not accept arbitrary string dictionaries and does not treat punctuation
  replacement as redaction.
- Keyboard delivery events may correlate one request and claim with source and
  current document identity plus the current keyboard-controller lifetime. They
  use only opaque content-free tags, never raw identifiers, host-app identity,
  text-input contents, or surrounding text.
- Delivery events distinguish an `insertText` invocation, its synchronous
  return, optional text-change observations, and claim-consumption
  acknowledgement. None of those events claims that text became visible or
  remained in the intended host input.
- Diagnostics may project `VoiceAttemptStage` to one closed content-free stage
  category. That projection is not serialization of the runtime enum and
  carries no error message, transcript, model, prompt, file path, provider
  payload, or host context.
- Copy Recent Logs is an explicit user action and copies only the redacted,
  bounded visible event window.
- Share Diagnostic File creates one readable UTF-8 text file only after the
  user taps the action, then presents the system share sheet. HoldType never
  selects a recipient or uploads the file automatically.
- The file contains app/build/device metadata, recent app-owned runtime events,
  locally delivered crash or hang diagnostics, and non-content bridge health.
- The file excludes raw audio and all user-authored or provider-returned text.
- When no events exist, Diagnostics shows an honest empty state.
- When no crash diagnostics have been delivered, Diagnostics says that no
  crash evidence has been delivered to HoldType; it must not claim the app has
  never crashed.
- When the app cannot launch, support recovery uses Xcode device logs,
  TestFlight/App Store crash diagnostics, or a user-provided system diagnostic;
  the in-app UI does not promise access to those artifacts.

## Retention

- App-owned runtime logs are local-only and capped by both age and size.
- The default cap is seven days and five megabytes.
- A diagnostic bundle includes at most the most recent 48 hours of runtime
  events.
- Locally delivered crash and hang diagnostics use the same seven-day age cap
  and are included only by explicit Share Diagnostic File.
- Pruning happens during normal app use and affects only HoldType-owned logs.
- Export artifacts are created only for an explicit export and remain visible
  to the user through the chosen destination or system share flow.

## Invariants

- Diagnostics works without microphone access, Full Access, Keychain reads,
  live OpenAI, or an active keyboard extension.
- Default product logs remain short, scannable, local, and redacted.
- The app and extension each log only their own lifecycle; neither copies
  sensitive cross-process state into logs.
- Existing generic macOS diagnostic formatting is not a portable privacy
  contract. It cannot be extracted or reused for iOS until it is replaced by
  the typed allowlist and forbidden-value tests above.
- An insertion snapshot may contain short-lived accepted text under its own
  contract, but Diagnostics must never include that field.
- Diagnostics never labels an insertion as delivered, inserted, confirmed, or
  successful solely because `insertText` returned or UIKit reported a document
  change. Correlation tags are supporting evidence, never delivery authority.
- Diagnostics never mutates system-owned crash or diagnostic files.
- MetricKit subscription and local ingestion perform no network upload and do
  not replace TestFlight or App Store crash collection.
- Verbose/debug logging is opt-in, bounded, and returned to the default level
  after investigation.

## Edge cases and failure policy

- If runtime logs cannot be read, Diagnostics shows a compact local error and
  still permits a metadata-only export.
- If pruning fails, normal product behavior continues and the next bounded
  maintenance pass retries without deleting unrelated files.
- If export fails, HoldType shows a local error and removes any incomplete
  app-owned export artifact.
- If a bridge record is missing, expired, corrupt, or incompatible, Diagnostics
  reports only that category and schema metadata, never raw record contents.
- If device storage is low, export may fail visibly without affecting history,
  recordings, settings, or the API key.

## Route / state / data implications

- Diagnostics is an app Settings route reached from the final Development
  section, not a permission, History, or top-level tab destination.
- Runtime logs live in the shared App Group cache so the containing app can
  export separate app and keyboard-extension event streams. Each process owns
  its own files and never appends to the other process's active file.
- Runtime log and delivered-diagnostic files use Data Protection and are
  excluded from cloud backup.
- Diagnostic export is derived local data and is never a keyboard bridge
  record.

## Verification mapping

- Test bounded append, chronological display, seven-day/five-megabyte pruning,
  and 48-hour export selection with fake storage and clocks.
- Test metadata-only export, failed export cleanup, missing logs, corrupt logs,
  and expired/corrupt bridge health summaries.
- Test MetricKit payload persistence, seven-day pruning, empty delivery, and
  diagnostic-file inclusion with content-free fixtures.
- Test every forbidden field against recent-event copy and bundle contents.
- Test keyboard delivery formatting with distinct request, claim, source
  document, current document, and controller-lifetime tags. Verify that raw
  identifiers, proxy text state, and successful-insertion claims are absent.
- Test that arbitrary string metadata cannot enter the portable event API and
  that representative forbidden values never survive formatting or export.
- Verify that normal diagnostics paths perform no Keychain, microphone,
  provider, or network access.
- Use manual simulator/device QA for system share and file-export presentation.
