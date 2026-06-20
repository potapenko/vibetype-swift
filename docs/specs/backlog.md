# Spec Backlog

This backlog was created during the initial spec-first bootstrap for
`vibetype-swift`.

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

## Next Specs To Create

1. OpenAI transcription contract
   - Define exact request/response behavior, model setting, language setting,
     prompt/vocabulary hint handling, retry policy, timeout, and error mapping.

2. Global hotkey
   - Define the default shortcut, hold-to-record vs toggle behavior, repeated
     press handling, collision handling, and shortcut customization.

3. Transcript history
   - Decide whether the optional local last-20 transcript history is in the MVP,
     where it is stored, how it is cleared, and whether it is enabled by
     default.

4. Floating indicator
   - Define exact visibility, text, placement, focus behavior, and error/done
     transitions for the floating panel.

5. Verification strategy
   - Define the first testable seams for microphone input, transcription
     providers, permission denial, timeout behavior, and text handoff.

## Highest-Priority Unknowns

- Final app name: `OpenWhisprSwift`, `DictationBar`, `VibeType`, or another
  name.
- Deployment target: macOS 14+ or macOS 13+ if it stays simple.
- Default hotkey: Control + Space or Option + Space.
- Primary recording mode: hold-to-record first, or toggle first if hold mode is
  unstable.
- Exact OpenAI transcription model default and timeout values.
- Whether transcript history is included in MVP and whether it is enabled by
  default.
