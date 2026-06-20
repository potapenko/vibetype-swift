# <Task Or Feature> macOS QA Case

Priority: P0/P1/P2
Status: VERIFIED / PARTIALLY_VERIFIED / UNVERIFIED
Source reference:
Spec reference:
Code reference:

## Functional Interpretation

Short description of the user-facing behavior this case proves.

## Preconditions

- Fresh app build is available.
- No live OpenAI call or real microphone input is required unless the case
  explicitly opts into manual evidence.
- Required fake/local state is prepared.

## Steps

1. Launch or relaunch the built macOS app.
2. Use Computer Use to open the relevant menu, window, panel, or target app.
3. Perform the changed user action.
4. Inspect the visible result.

## Expected Results

- The changed action is reachable.
- The visible state matches the spec.
- No unexpected permission prompt, crash, hang, or sensitive default log output
  appears.

## Evidence

- Screenshot:
- Observation:
- Blocker:
