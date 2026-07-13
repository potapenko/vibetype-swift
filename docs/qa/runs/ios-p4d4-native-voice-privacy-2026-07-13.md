# iOS P4D-4 Native Voice And Privacy QA

Date: 2026-07-13
Milestone: P4D-4 native Voice and Privacy presentation

## Decision

P4D-4 is complete. The containing app now presents the shared foreground Voice
runtime through native iPhone and iPad Voice and Privacy surfaces. Every
command remains bound to exact process, scene, presentation-revision, and
content-revision authority; stale confirmations and stale Latest Result actions
fail closed.

This is not approval of P4, P4D-2, or the recorder candidate for release.
P4D-2C physical-device validation and P4D-5 release/runtime qualification
remain pending.

## Delivered Contract

- Every scene receives the exact shared controller, its own scene owner, the
  shared Latest Result owner, and the process provider-consent presentation
  owner.
- Recovery and active dictation state take precedence over onboarding guidance.
  Setup, capture, finalization, processing, cancellation, recoverable failure,
  and accepted-result states expose only their frozen commands.
- Latest Result remains independent from the active attempt. Copy, Share, Use
  in Practice, and Clear require exact current content authority.
- Discard and Clear use destructive confirmation tied to the exact current
  revision.
- The practice draft belongs to the invoking scene's shell. It survives
  iPhone tab and iPad detail round-trips without becoming process-shared.
- VoiceOver receives content-free announcements for meaningful Voice, Latest
  Result, consent, Copy, and Use in Practice changes. Listening elapsed time is
  queryable without posting an announcement every second.
- Provider-consent accept, withdraw, and reset confirmations use exact process
  confirmation tokens. Passive refresh or a newer action invalidates an older
  dialog or disclosure sheet.
- Privacy presents passive microphone state, the public System Settings route,
  current consent state, complete provider disclosure, and the local/remote
  data boundary.
- The disclosure covers audio, model/language and processing hints sent to
  OpenAI; API-key ownership; ordinary keystrokes and surrounding host text that
  are not sent; local Library configuration that is not copied to the keyboard;
  and P4 recording/Latest Result retention.
- The implementation adds no background audio, Quick Session, App Group Voice
  publication, keyboard command, external-app insertion, or History UI.

## Automated Evidence

- Strict selected Voice, lifecycle, presentation, consent, scene, shell, and
  Latest Result run with warnings as errors and parallel testing disabled
  - Result: 149 tests in 11 suites passed.
  - Result bundle:
    `/Users/eugenepotapenko/Library/Developer/Xcode/DerivedData/HoldType-aiagnlkblhltvacjmbtlpyjistgi/Logs/Test/Test-HoldType-iOS-2026.07.13_06-51-30-+0200.xcresult`.
  - Log: `/tmp/p4d4-ui-broad-final.log`.
- Focused strict post-review presentation and shell run
  - Suites: `IOSNativeVoicePresentationTests` and
    `IOSContainingAppShellTests`.
  - Result: 10 tests in 2 suites passed.
  - Log: `/tmp/p4d4-ui-review-fixes-focused.log`.
- Warnings-as-errors `HoldType-iOS` build
  - Result: passed.
  - Log: `/tmp/p4d4-ui-build5.log`.
- macOS `HoldType` baseline build with automation Keychain access disabled
  - Result: passed.
  - Log: `/tmp/p4d4-ui-macos-build.log`.
- `git diff --check`
  - Result: passed before the documentation checkpoint.

Xcode emitted only the expected AppIntents metadata-tool notice that extraction
was skipped because the targets do not depend on AppIntents.

## Full-Suite Qualification Note

A full parallel `HoldType-iOS` test attempt was non-qualifying and was stopped
after existing foreground-workflow coordination fixtures reached their bounded
test waits under parallel load. It is not reported as a passing full-suite gate
and was not used as the P4D-4 decision. The strict selected suites covering the
changed Voice graph, presentation, consent-confirmation, scene, shell, and
Latest Result boundaries passed. Log: `/tmp/p4d4-ui-full-tests.log`.

## Runtime And Visual Evidence

- The current build launched with `HOLDTYPE_AUTOMATION=1` on a clean iPhone 16 /
  iOS 18.6 simulator.
- Voice rendered recovery ahead of setup guidance, retained native grouped
  hierarchy, and kept the practice field reachable.
- The Voice information action opened Privacy & Permissions through the native
  Settings stack.
- Review and Accept presented the complete disclosure. The flow was dismissed
  without accepting or mutating consent.
- The practice field accepted scene-local text.
- The same practice draft survived Voice → Settings → Voice on both an iPhone
  tab shell and an iPad split shell.
- An iPad Pro 11-inch (M4) regular-width split presentation and
  accessibility-extra-extra-large Dynamic Type remained readable and
  scrollable.
- No runtime check requested microphone permission, activated a real audio
  session, recorded audio, contacted OpenAI, used a live API key, accessed a
  live Keychain item, or changed durable provider consent.

## Review And Privacy Assessment

Independent review covered exact scene ownership, stale destructive actions,
permission refresh, recovery prominence, complete provider disclosure,
confirmation-token invalidation, app-only product claims, practice-draft
lifetime, and VoiceOver status delivery. After the corresponding fixes and two
focused re-reviews, no unresolved P1 or P2 finding remained.

Observable Voice and consent presentation stays payload-free. Accepted text is
available only through exact Latest Result content commands and is not copied
to App Group, the keyboard, diagnostics, or product logs.

## Remaining Gates

- P4D-2C must prove recorder/source identity and the frozen permission, route,
  interruption, lock, cue, microphone-indicator, and finalization matrix on a
  physical iPhone or iPad.
- P4D-5 owns final simulator, Release, keyboard-isolation, accessibility, and
  physical-device qualification.
- P4 remains foreground-only and app-only until those gates pass.
