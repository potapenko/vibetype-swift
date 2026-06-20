# Verification Strategy

## Goal

Define how VibeType proves MVP dictation behavior without depending on live
OpenAI calls, real microphone input, uncontrolled permission prompts, or
unbounded platform waits in normal automation.

Verification should keep each backlog slice small: deterministic product logic
uses unit tests and fakes, while real macOS surfaces use bounded runtime smoke
only when a task changes that surface.

## Scope

This spec covers:

- test seams for microphone capture, transcription, permissions, timeout
  behavior, hotkeys, settings, and text handoff
- the boundary between unit tests, fake-backed integration tests, UI tests, and
  manual QA
- behavior that must never use live providers or uncontrolled platform prompts
  in normal automated tests
- timeout expectations for service and platform checks

## Non-goals

- implementing test infrastructure
- defining final UI test coverage for every screen
- requiring live OpenAI, real microphone, or real active-app paste checks in
  normal automation
- replacing the per-task evidence rules in `platform-testing-strategy.md`

## User-visible behavior

- Core dictation state must be testable without launching the full app.
- Recording, transcribing, success, and error states must be represented by
  deterministic model or controller tests before platform adapters become the
  main source of evidence.
- Permission-denied, missing-key, timeout, no-speech, provider-failure, and
  output-failure paths must be covered by fakes or fixtures before they are
  treated as implemented behavior.
- Real microphone recording, real Accessibility trust, real global hotkeys,
  and paste into another app are platform behavior. They require bounded smoke
  or manual QA only when the selected task changes that platform surface.
- Default automated verification must not call the live OpenAI API.
- Default automated verification must not require a real system permission
  prompt, real microphone input, or a real target app accepting paste.
- Failed sessions must be verified not to overwrite the previous successful
  transcript.
- Default logs must be checked by review or tests to avoid API keys, raw audio,
  dictated text, authorization headers, prompts, and full provider responses.

## Test seams by MVP area

### Dictation session state

- Use a central model or controller seam for start, stop, cancel, transcribe,
  accept transcript, and fail session transitions.
- Use fake recorder, transcription, settings, permissions, history, and output
  services.
- Cover repeated start suppression, stop-without-recording, cancellation,
  transcription failure, output failure, and preserving the last good
  transcript after failure.

### Microphone and recorder

- Use fake recorder tests for app logic that starts, stops, cancels, and
  receives an audio file URL.
- Use local temporary files for file-validation tests when needed.
- Keep AVFoundation adapter checks behind build coverage, focused unit seams
  where practical, and bounded manual or runtime QA when actual microphone
  capture behavior changes.
- Tests must not wait indefinitely for recording callbacks or file creation.

### Permissions

- Use fake microphone and Accessibility permission clients for normal tests.
- Test product states rather than platform prompt UI: allowed, denied, not
  determined, unavailable, trusted, and not trusted.
- The production Accessibility status check should be non-prompting by default.
- Real System Settings navigation or permission prompt behavior is manual or
  bounded smoke evidence, not a normal unit-test dependency.

### OpenAI transcription

- Use request-builder and response-parser tests for multipart shape, model,
  language, prompt, supported file formats, successful response parsing, and
  empty transcript rejection.
- Use URLSession fakes, protocol stubs, or service fakes for provider errors,
  invalid credentials, rate limits, server failures, network failures, and
  cancellation.
- Timeout behavior must use an injectable delay, clock, or bounded fake.
- Normal tests and automations must not send audio to OpenAI.

### Settings and Keychain

- Use isolated UserDefaults suites or in-memory stores for non-secret settings.
- Use fake Keychain clients for normal save, load, delete, missing-key, and
  Keychain-failure tests.
- Tests must prove the API key is not stored in UserDefaults and is not logged.

### Text output and clipboard

- Use fake clipboard and paste clients for output decision tests.
- Cover auto-paste enabled, copy-only mode, missing Accessibility fallback,
  empty transcript suppression, clipboard restore success, clipboard restore
  failure, and paste failure.
- Real active-app paste behavior is bounded runtime smoke or manual QA only
  when a task changes the paste adapter or visible output flow.

### Global hotkey

- Use fake hotkey event streams for hold-to-record, toggle fallback, key repeat
  suppression, key-up without matching key-down, transcribing-state rejection,
  registration failure, and fallback shortcut selection.
- Real macOS hotkey registration is platform smoke or manual QA when the
  selected task changes the registration adapter.

### UI surfaces

- Use model and view tests where they can assert state without app launch.
- Use macOS build verification for app-shell changes.
- Add bounded Computer Use smoke only for changed visible surfaces such as menu
  contents, Settings, permission UI, floating indicator, or active-app paste.

## Invariants

- No normal automated test may call live OpenAI.
- No normal automated test may require real microphone input.
- No normal automated test may depend on uncontrolled system permission prompts.
- External waits must be bounded and fail the current attempt on timeout.
- Fakes must model product outcomes, not hide errors by always succeeding.
- Platform smoke checks must be short and may report a blocker instead of
  turning into open-ended manual sessions.
- Verification evidence belongs in tests, QA artifacts, task files, or final
  reports. It does not replace product behavior specs.

## Edge cases and failure policy

- If a platform smoke check cannot launch or inspect the app quickly, record
  the blocker and keep unit/build evidence explicit.
- If a full Xcode scheme test fails only because a platform UI-test runner
  needs off-console interaction, run and report the narrow target evidence that
  proves the changed logic.
- If a fake-backed test cannot express the product behavior clearly, add a
  small protocol or adapter seam before implementing broad platform logic.
- If a task needs live provider or real microphone evidence, it must say so
  explicitly and use a bounded, opt-in manual QA path.
- If debug logging is enabled during investigation, it must be disabled again
  before completion.

## Route / state / data implications

- Service boundaries should expose testable protocols or small adapters for
  recorder, transcription, permissions, Keychain, clipboard, paste, hotkey,
  settings, history, and logging.
- The dictation coordinator should accept fakes for service dependencies so
  session behavior can be verified without platform side effects.
- Timeout configuration should be injectable or otherwise controllable in tests.
- Logs should use compact error categories that can be tested without
  containing sensitive user content.

## Verification mapping

- Docs/spec-only tasks: `git diff --check`.
- Swift model or service behavior: macOS test command plus `git diff --check`.
- Swift UI or app-shell behavior: macOS build command plus `git diff --check`;
  add Computer Use smoke when visible runtime UI changes.
- Provider behavior: fake-backed URL or service tests, bounded timeout tests,
  and no live OpenAI call.
- Permission behavior: fake-backed state tests; bounded runtime or manual QA
  only for platform prompt or System Settings behavior.
- Microphone behavior: fake-backed state tests; bounded manual or runtime QA
  only for actual AVFoundation capture changes.
- Text handoff behavior: fake-backed output tests; bounded runtime or manual QA
  only for actual active-app paste changes.

## Unknowns requiring confirmation

- Whether future release candidates require a separate opt-in live OpenAI smoke
  checklist.
- Whether full UI-test targets should stay in the scheme if they remain
  unreliable in unattended off-console automation.
- Whether real microphone and paste QA should be captured as durable Markdown
  artifacts or kept in task completion reports until those flows stabilize.
