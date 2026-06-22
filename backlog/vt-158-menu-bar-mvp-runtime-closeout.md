---
id: VT-158
title: Menu Bar MVP Runtime Closeout
status: blocked
priority: P0
lane: swift-app-shell
parent: VT-010
dependencies:
  - VT-000
  - VT-011
  - VT-012
  - VT-013
  - VT-014
  - VT-015
  - VT-112
allowed_paths:
  - backlog/vt-010-menu-bar-mvp-umbrella.md
  - backlog/vt-158-menu-bar-mvp-runtime-closeout.md
  - docs/qa/macos/**
  - docs/specs/features/menu-bar-app-shell.md
  - docs/specs/features/platform-testing-strategy.md
  - vibetype/**
  - vibetypeTests/**
  - vibetype.xcodeproj/**
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests
  - git diff --check
---

# VT-158 - Menu Bar MVP Runtime Closeout

Status: blocked
Priority: P0
Lane: swift-app-shell
Dependencies: VT-000, VT-011, VT-012, VT-013, VT-014, VT-015, VT-112
Expected outputs: executable menu-surface evidence or repair, VT-010 closeout update
Verification: macOS build; focused macOS unit tests when Swift/tests change; git diff --check

## Goal

Produce the product delta that `VT-010` could not produce from its docs/spec
umbrella scope: prove or repair the native menu bar MVP shell as executable app
behavior.

## Scope

- Build the macOS app from the canonical checkout.
- Inspect the implemented menu bar MVP against
  `docs/specs/features/menu-bar-app-shell.md`.
- If the current tool surface can operate the real app safely, perform bounded
  macOS runtime QA for menu presence, Start/Stop binding, Settings entry, Last
  Transcript, Copy Last Transcript disabled/enabled state where safely
  reachable, and Quit visibility. Save concise evidence under `docs/qa/macos/`.
- If real menu operation remains blocked by the available Computer Use surface,
  add or tighten executable Swift coverage for the menu-surface state contract
  instead of writing another docs-only closeout.
- Fix only small menu-shell defects found during that verification. Do not
  widen into recording, transcription, hotkey registration, or Settings form
  implementation beyond what the menu shell already exposes.
- Update `VT-010` with the resulting evidence and mark it `done` only when the
  product delta is verified. If a local tooling or runtime inspection blocker
  remains after recovery/retry, keep `VT-010` blocked with fresh evidence.

## Acceptance

- The run produces a concrete product delta: executable menu-shell tests,
  bounded runtime evidence, or a small verified menu-shell repair.
- `VT-010` is updated with the result and no longer relies on docs/spec review
  alone.
- Runtime QA is recorded as `required`, `not_applicable`, or `blocked` with the
  exact reason.
- No live OpenAI request, real microphone input, or system permission change is
  required.
- Verification commands are recorded with pass/fail/blocker results.

## Verification

- Run local tooling recovery first if Xcode/build/test/runtime tooling is
  stale or blocked.
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
- Bounded Computer Use runtime QA when the active tool surface can inspect and
  operate the relevant macOS app surface; otherwise record the capability gap
  and rely on executable Swift coverage for the product delta.
- `git diff --check`

## Result

Blocked on 2026-06-22 after adding executable menu-surface coverage.

- Product delta: added `MenuBarPresentation` so the menu bar MVP shell has a
  deterministic, testable state contract for app identity, permission status
  copy, recording action labels/enabled states, transcript display/copy state,
  Settings, and Quit.
- Added `MenuBarPresentationTests` covering idle, recording, transcribing,
  microphone-permission-needed, microphone-denied, Accessibility-not-trusted,
  and successful-transcript menu states.
- Wired `MenuBarView` and `VibeTypeApp` through the shared presentation and
  identity constants without changing the intended visible menu behavior.
- Runtime QA: blocked. The current Computer Use surface can read app state, but
  exposes no safe macOS interaction action to open the menu bar extra, and the
  app could not be freshly launched because the required Xcode build did not
  produce a product.

Verification evidence:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json` terminated
  stale local Xcode probe/test processes and removed generated project
  DerivedData before retry.
- Blocked: `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  reached Xcode's early `clang -v -E -dM ... /dev/null` external-tool probe,
  produced no compiler diagnostics, and exited 124 with `** BUILD INTERRUPTED **`.
- Passed with one existing deprecation warning:
  `/opt/homebrew/bin/timeout 90 xcrun swiftc -typecheck -parse-as-library $(rg --files vibetype Shared -g '*.swift' | sort)`.
- Blocked: `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached the same Xcode external-tool probe before test discovery or test
  execution and exited 124 with `** BUILD INTERRUPTED **`.
- Cleanup after the timed-out focused test removed generated DerivedData and
  terminated stale `SWBBuildService` pid `87805`.

2026-06-22 01:12 CEST blocker resolver refresh:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json`
  terminated stale VibeType build/test tooling before retry:
  `xcodebuild` pids `15276` and `15277`, `SWBBuildService` pid `15810`, and
  clang probe pid `15886`.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  again reached the early `clang -v -E -dM ... /dev/null` probe before
  compiler diagnostics and exited 143 with `** BUILD INTERRUPTED **`.
- Passed: recovery after the build retry found no remaining stale processes or
  generated artifacts.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode external-tool probing before test discovery or execution and
  exited 143 with `** BUILD INTERRUPTED **`.
- Passed: final recovery found no remaining stale processes or generated
  artifacts.
- Runtime QA remains blocked because no fresh macOS app build product was
  produced.

2026-06-22 02:16 CEST blocker resolver refresh:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json`
  terminated stale VibeType build/test tooling before blocked-task selection:
  timeout-wrapped `xcodebuild` pid `69184`, child `xcodebuild` pid `69185`,
  `SWBBuildService` pid `69758`, and clang probe pid `69877`.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  reached the early `clang -v -E -dM ... /dev/null` probe before compiler
  diagnostics and exited 143 with `** BUILD INTERRUPTED **`.
- Passed: recovery after the build retry found no remaining stale processes or
  generated artifacts.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode external-tool probing before test discovery or execution and
  exited 124 with `** BUILD INTERRUPTED **`.
- Passed: final recovery found no remaining stale processes or generated
  artifacts.
- Runtime QA remains blocked because no fresh macOS app build product was
  produced.

2026-06-22 03:17 CEST blocker resolver refresh:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json`
  terminated stale VibeType build/test tooling before blocked-task selection:
  timeout-wrapped `xcodebuild` pid `68758`, child `xcodebuild` pid `68759`,
  `SWBBuildService` pid `69427`, and clang probe pid `69690`; it also removed
  generated `scripts/__pycache__`.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  reached the early `clang -v -E -dM ... /dev/null` probe before compiler
  diagnostics and exited 143 with `** BUILD INTERRUPTED **`.
- Passed: recovery after the build retry found no remaining stale processes or
  generated artifacts.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode external-tool probing before test discovery or execution and
  exited 143 with `** BUILD INTERRUPTED **`.
- Passed: final recovery found no remaining stale processes or generated
  artifacts.
- Runtime QA remains blocked because no fresh macOS app build product was
  produced.

2026-06-22 04:17 CEST blocker resolver refresh:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json` before
  blocked-task selection removed generated `scripts/__pycache__` and
  project-scoped DerivedData and found no stale Xcode/build/test processes.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  reached Xcode's early `clang -v -E -dM ... /dev/null` external-tool probe
  before compiler diagnostics and exited 143 with `** BUILD INTERRUPTED **`.
- Passed: recovery after the build retry found no remaining stale processes or
  generated artifacts.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode external-tool probing before test discovery or execution and
  exited 143 with `** BUILD INTERRUPTED **`.
- Passed: final recovery removed regenerated project-scoped DerivedData and
  found no stale processes.
- Runtime QA remains blocked because no fresh macOS app build product was
  produced.

2026-06-22 05:18 CEST blocker resolver refresh:

- Passed: `python3 scripts/local_tooling_recover.py --apply --json` before
  blocked-task selection removed project-scoped DerivedData and found no stale
  Xcode/build/test processes.
- Tooling surface checked: XcodeBuildMCP was available, but the exposed tool
  set did not provide a matching macOS build/test action for the selected
  `xcodebuild` verification, so the resolver used bounded shell `xcodebuild`.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
  reached Xcode's early `clang -v -E -dM ... /dev/null` external-tool probe
  before compiler diagnostics and exited 124 with `** BUILD INTERRUPTED **`.
- Passed: recovery after the build retry found no remaining stale processes or
  generated artifacts.
- Blocked:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests`
  reached Xcode external-tool probing before test discovery or execution and
  exited 143 with `** BUILD INTERRUPTED **`.
- Passed: final recovery found no remaining stale processes or generated
  artifacts.
- Runtime QA remains blocked because no fresh macOS app build product was
  produced.

Durable QA note:

- `docs/qa/macos/vt-158-2026-06-22-menu-bar-runtime-closeout.md`

## Resolution Path

- Blocker category: local Xcode build/test tooling timeout before compiler or
  unit-test execution; macOS runtime menu QA also remains blocked until a build
  product exists and the tool surface can operate the menu bar extra.
- Existing infrastructure evidence: `VT-148`
  (`backlog/done/vt-148-xcode-build-service-health.md`) records the same
  automation-recoverable Xcode build-service timeout class.
- Unblock condition: local Xcode build/test health must reach compiler output
  and focused `vibetypeTests` execution after `scripts/local_tooling_recover.py
  --apply --json`; then rerun the VT-158 build, focused unit tests, and menu
  runtime QA if a macOS UI interaction tool is available.
- The latest resolver run could not finish directly because both required Xcode
  commands were interrupted after local recovery, before they could build the
  app or execute the new menu presentation tests.
