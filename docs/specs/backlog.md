# Spec Backlog

This backlog was created during the initial spec-first bootstrap for
`vibetype-swift`.

This file is a product/spec planning note. Executable agent tasks now live in
the root `backlog/` directory and are selected with
`python3 scripts/backlog_next.py --json`.

## Evidence Used

- Local checkout has no implementation files, docs, tests, or commits.
- GitHub repository description: "Project for an app for work - text input via
  microphone".
- Product brief: `docs/openwhispr_swiftui_codex_tz.md`.
- Bootstrap reference: `https://github.com/potapenko/spec-first-bootstrap`.

## First-Pass Specs Created

- `features/microphone-text-input.md`
- `features/privacy-and-permissions.md`
- `features/menu-bar-app-shell.md`
- `features/settings-and-secret-storage.md`
- `features/text-output-workflow.md`
- `features/global-hotkey.md`
- `features/openai-transcription.md`

## Next Specs To Create

1. Transcript history
   - Decide whether the optional local last-20 transcript history is in the MVP,
     where it is stored, how it is cleared, and whether it is enabled by
     default.
   - Executable task: `backlog/vt-003-transcript-history-decision.md`.

2. Floating indicator
   - Define exact visibility, text, placement, focus behavior, and error/done
     transitions for the floating panel.
   - Executable task: `backlog/vt-004-floating-indicator-contract.md`.

3. Verification strategy
   - Define the first testable seams for microphone input, transcription
     providers, permission denial, timeout behavior, and text handoff.
   - Executable task: `backlog/vt-005-verification-strategy.md`.

4. Platform testing and QA evidence
   - Define how agents choose between unit tests, build checks, macOS runtime
     smoke checks, Computer Use, and future iOS simulator checks.
   - Product contract: `features/platform-testing-strategy.md`.

## Seeded Backlog Shape

The executable backlog is split into umbrella parent tasks and small child
tasks. Parent tasks describe product areas, while child tasks should be short
implementation slices that a single agent checkpoint can claim, implement,
verify, and commit.

The first implementation slice should establish a visible native menu bar item
before deeper recording, transcription, permission, or settings work proceeds.

## Highest-Priority Unknowns

- Final app name: `OpenWhisprSwift`, `DictationBar`, `VibeType`, or another
  name.
- Deployment target: macOS 14+ or macOS 13+ if it stays simple.
- Default hotkey: Control + Space or Option + Space.
- Primary recording mode: hold-to-record first, or toggle first if hold mode is
  unstable.
- Whether the default OpenAI transcription model and timeout should change
  after real-world QA.
- Whether transcript history is included in MVP and whether it is enabled by
  default.
