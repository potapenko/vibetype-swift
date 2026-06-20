# macOS QA Runner

Use this guide for bounded Computer Use QA on the VibeType macOS app.

## Hard Requirements

- Use a real launched app, not code inspection, for runtime QA.
- Use Computer Use to inspect and operate the UI when the task changes a
  visible surface or user interaction.
- Prefer accessibility-visible controls, labels, states, and stable identifiers
  over visual guesses.
- Test the changed user action, not only app launch.
- Keep the run bounded. If launch, inspection, permission, microphone, network,
  or paste cannot complete quickly, record a blocker instead of waiting.
- Do not call the live OpenAI API, require real microphone input, or change
  system permissions unless the selected task explicitly requires that opt-in
  evidence.
- Do not store API keys, authorization headers, raw dictated text, raw audio,
  prompts, or full provider responses.

## Standard Runtime Flow

1. Build the app with the task's required `xcodebuild` command.
2. Stop or replace only run-owned app instances when ownership is clear.
3. Launch the freshly built app.
4. Use Computer Use to inspect the relevant macOS surface.
5. Perform the task-specific action:
   - open the menu bar item and inspect changed menu entries;
   - open Settings and exercise changed controls;
   - trigger the changed permission, recording, status, indicator, or output
     path with fakes or safe local state when possible;
   - verify copy/paste or active-app handoff only when the task explicitly
     requires bounded runtime evidence.
6. Capture a short observation: expected, observed, result, screenshot path if
   available, and blocker if any.
7. Close run-owned app windows or app instances when safe.

## Result Values

- `PASS`: the runtime behavior was inspected and matched the task expectation.
- `FAIL`: the app launched but behavior did not match the expectation.
- `BLOCKED`: the runtime check could not reach the relevant UI or action within
  the bounded run.
- `SKIPPED`: runtime QA was not applicable because the task changed only
  non-UI internals and had build/test evidence.

## Minimum Report Fields

```text
Runtime QA: required | not_applicable | blocked
Tool: Computer Use | XcodeBuildMCP | none
Scenario:
Actions:
Expected:
Observed:
Result: PASS | FAIL | BLOCKED | SKIPPED
Evidence:
Blocker:
```

If the task touches UI and this section is missing, the run is incomplete.
