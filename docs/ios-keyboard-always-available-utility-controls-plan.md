# HoldType iOS Keyboard Always-Available Utility Controls Plan

Status: planning only; no production, spec, or test behavior changed yet;
created 2026-07-16.

This direct-task plan removes the HoldType-owned availability gate from Quick
Insert and Auto and removes visible animation restarts during ordinary keyboard
state refreshes. Product behavior is currently governed by
`docs/specs/features/ios-keyboard-experience.md` and
`docs/specs/features/ios-keyboard-handoff-and-delivery.md`.

## Reported Problem

- The smile/Quick Insert and Auto controls look disabled while keyboard
  dictation is opening, starting, listening, or processing.
- The user cannot insert punctuation or emoji during recording even though the
  host text input remains active.
- Starting a recording produces distracting visual flashes or animation jumps.
- These controls must never be coupled to microphone or provider readiness.

## Verified Current Cause

The disabled state is produced by HoldType, not by iOS or the host app.

- `KeyboardVoiceStagePresentation.keepsVoiceWorkspaceVisible` is true for
  Opening, Starting, Listening, and Processing.
- `BrandStageKeyboardView.render` uses that value to disable both the Quick
  Insert button and the Auto button.
- The same render path forcibly closes Quick Insert and the Auto modes panel
  whenever an active voice state arrives.
- The current keyboard-experience spec explicitly requires these controls to
  be disabled and their panels to close during Starting, Listening, and
  Processing, so the implementation is following an obsolete product rule.

There is a second source-level animation problem. Every render of the central
voice activity view rebuilds its orbit layers, removes its animations, and
starts them again. Repeated controller refreshes in the same Listening or
Processing phase can therefore reset the visible rotation and pulse instead of
letting them continue smoothly.

The disabled Apple Dictation icon that iOS may show in its own bottom strip is
separate and remains system-owned. This plan concerns the HoldType-owned smile,
Auto, and central activity presentation.

## Product Decision

Quick Insert and Auto are independent keyboard utilities. They remain enabled
and visually unchanged in every HoldType voice state, including Ready, Opening,
Starting, Listening, Processing, failure, and recovery.

Voice state may change only the central voice action and its status. It must not
dim, disable, close, or otherwise re-present the left utility controls.

### Quick Insert

- The user may open Quick Insert at any time and insert one punctuation or emoji
  value into the current host input through `UITextDocumentProxy`.
- Opening Quick Insert temporarily covers the central Voice workspace but does
  not start, finish, cancel, pause, or otherwise change the active dictation.
- An incoming voice-state refresh does not close Quick Insert. Closing it or
  selecting an item reveals the latest underlying voice state.
- Selecting an item performs exactly one local insertion and closes Quick
  Insert as it does today.

### Auto

- The user may open Auto and change Translate Result or Correct Result at any
  time.
- Once a microphone tap has created an attempt, that attempt keeps the action
  snapshot chosen at Start. Auto changes made during Opening, Starting,
  Listening, or Processing apply only to the next attempt.
- An incoming voice-state refresh does not close the Auto panel.
- Quick Insert and Auto remain mutually exclusive local surfaces: explicitly
  opening one may close the other. Voice-state changes may not close either.

### Stable Presentation

- The smile and Auto buttons never enter UIKit's disabled visual state because
  of voice activity.
- Re-rendering an unchanged voice phase is idempotent: it does not rebuild
  layers, remove animations, reset rotation, reset pulse, or move accessibility
  focus.
- A real phase transition updates the central artwork once. Listening and
  Processing animations then continue without jumps until the phase actually
  changes, the view leaves the window, its size changes, or an accessibility
  appearance setting changes.
- Reduce Motion and Reduce Transparency behavior remains authoritative and is
  not bypassed to preserve animation continuity.

## Behavior Matrix

| Voice state | Quick Insert | Auto | Auto selection affects |
| --- | --- | --- | --- |
| Ready | Enabled | Enabled | Next attempt |
| Opening HoldType | Enabled | Enabled | Next attempt |
| Starting | Enabled | Enabled | Next attempt |
| Listening | Enabled | Enabled | Next attempt |
| Processing | Enabled | Enabled | Next attempt |
| Failure or recovery | Enabled | Enabled | Next attempt |

`Latest` keeps its existing content-availability gate. Return keeps the host
input's existing semantic gate. The microphone keeps its state-specific action
and availability. This plan does not broaden those controls.

## Planned Changes

### 1. Correct The Product Contract

Update `docs/specs/features/ios-keyboard-experience.md` before production code:

- replace the clauses that disable Quick Insert and Auto during active voice;
- state that both utilities remain available in every voice state;
- state that active voice refreshes preserve an already-open utility surface;
- preserve the current-request action snapshot while making later Auto changes
  next-attempt preferences;
- add stable, non-restarting activity presentation to release acceptance.

Add a matching invariant to
`docs/specs/features/ios-keyboard-handoff-and-delivery.md`: app handoff and
dictation phases cannot gate local Quick Insert or next-attempt Auto selection.

### 2. Remove The HoldType-Owned Availability Gate

In `HoldTypeKeyboard/BrandStageKeyboardView.swift`:

- remove voice-stage-driven `isEnabled` assignments for Quick Insert and Auto;
- remove the voice-stage branch that forcibly clears
  `quickInsertIsPresented` and `automaticModesArePresented`;
- retire `keepsVoiceWorkspaceVisible` if no behavior still needs it;
- keep explicit Quick Insert/Auto mutual exclusion and explicit user dismissal;
- keep the utility controls' enabled appearance stable across voice renders.

No state or command changes are expected in
`HoldTypeKeyboard/KeyboardViewController.swift`. Its presentation mapping should
continue to describe the central voice stage, while `automaticVoiceAction` is
the preference used when the next Start command is created. Controller changes
are allowed only if focused tests reveal that an in-flight action is not already
snapshotted correctly.

### 3. Make Voice Activity Rendering Idempotent

In `HoldTypeKeyboard/KeyboardVoiceActivityIndicatorView.swift`:

- distinguish an actual phase/geometry/appearance change from a repeated render
  of the same phase;
- do not rebuild orbit layers or restart animations for a no-op render;
- avoid unconditional layout-driven orbit reconstruction when bounds are
  unchanged;
- restart only at explicit lifecycle boundaries such as a changed phase,
  changed size, reattachment to a window, or changed Reduce Motion setting;
- preserve the current presentation without implicit UIKit animations during a
  phase transition.

### 4. Replace Obsolete Tests With The New Invariant

Update focused keyboard view tests so they prove:

- Quick Insert and Auto are enabled in Ready, Opening, Starting, Listening, and
  Processing;
- an open Quick Insert surface survives state changes and still inserts exactly
  one punctuation or emoji value;
- an open Auto panel survives state changes and remains interactive;
- changing Auto during an active attempt does not alter that attempt's Start
  command and is used by the next attempt;
- explicitly opening Quick Insert closes Auto and explicitly opening Auto closes
  Quick Insert;
- repeated renders of the same activity phase do not recreate or restart its
  active animations;
- a real Listening-to-Processing transition changes the activity presentation
  once.

Delete or rewrite the current assertions that require Auto to become disabled
or require active voice to close utility surfaces.

## Verification Plan

1. Run focused `BrandStageKeyboardViewTests`,
   `KeyboardVoiceActivityIndicatorViewTests`, and any affected
   `KeyboardViewControllerTests`.
2. Run the iOS test target and build the real keyboard extension.
3. In Simulator, with the repository-required scoped `caffeinate` guard and
   sanitized Keychain launch path, verify every state in Light and Dark Mode and
   with Reduce Motion enabled and disabled.
4. Record a short state-transition capture proving the top utility rail does
   not dim or flash across Ready -> Opening -> Starting -> Listening ->
   Processing -> Ready.
5. On a signed physical iPhone, verify in a normal host text field that emoji
   insertion works during Listening and Processing, Auto remains interactive,
   current dictation is unaffected, and the next dictation uses the newly
   selected modes.
6. Run the repository iOS build/test baseline and `git diff --check` before the
   implementation checkpoint.

Simulator evidence may prove presentation and local insertion. It must not be
reported as proof of real microphone ownership or the signed-device handoff.

## Exit Criteria

- The HoldType smile and Auto controls are never disabled or visually dimmed by
  voice state.
- The user can insert an emoji or punctuation while recording or processing.
- The user can change Auto during an active request without mutating that
  request; the next request uses the new selection.
- Voice-state refreshes do not dismiss an open Quick Insert or Auto surface.
- Repeated same-phase renders do not restart the central activity animation.
- The Ready-to-Listening-to-Processing flow has no utility-control flash or
  animation jump in recorded real-keyboard evidence.
- Governing specs, deterministic tests, Simulator evidence, and signed-device
  evidence agree with the implemented behavior.

## Non-Goals

- No change to Apple's system Dictation button or globe strip.
- No change to microphone ownership, handoff routing, provider processing,
  exactly-once transcript delivery, Latest availability, or Return semantics.
- No alphabet, number, or system emoji keyboard is added to HoldType.
- No implementation is performed as part of this planning task.
