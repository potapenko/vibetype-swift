# iOS Voice Draft

Status: approved product contract; revised 2026-07-15.

## Goal

Make Voice the useful default iPhone screen for dictating inside HoldType,
reviewing one composed text, copying it, and continuing with another dictation
without opening the custom keyboard.

## Launch And Navigation

- Voice is the first tab and the destination for every cold launch or new
  scene.
- Returning from the background preserves the current tab while that scene is
  alive.
- History remains a separate containing-app tab. Voice contains no History
  list or preview and adds no duplicate History toolbar action.
- Append, Auto Translate, and Auto Correction are session modes in one compact
  `Auto` menu at the leading edge of the bottom Draft action area. Flexible
  space separates that menu from the labeled `Copy` capsule at the trailing
  edge. Neither control expands to fill the row. The existing one-shot
  Translate and Correction actions, plus Undo and Redo, remain together as a
  compact leading icon group in the top action area. Clear remains the only
  trailing top action and is a neutral labeled Draft action, not a red delete
  or History action. On compact widths or at large Dynamic Type sizes, the
  leading icon group may wrap internally without moving Clear into that group
  or removing its label.
  Keyboard Dictation Session and the practice field remain reachable from the
  compact Voice More menu; the keyboard tools are presented as a sheet and
  none of them occupies the primary Voice canvas.

## Draft

- Voice presents one app-private composed Draft independently from Latest,
  History, Pending, Recording Cache, and the keyboard projection.
- The Draft is a vertically scrollable text editor that starts unfocused.
  Launch never focuses it or opens the keyboard. A direct tap focuses it and
  enables normal selection, typing, paste, and system emoji input.
- Draft text uses one adaptive reading step before it scrolls. At standard
  Dynamic Type sizes it starts at approximately 20 points, moves once to an
  approximately 18-point compact size when the complete text no longer fits
  the visible text viewport, and never shrinks further. The transition avoids
  repeated reflow around the boundary by keeping one to two lines of return
  headroom. Accessibility Dynamic Type sizes never auto-shrink.
- After the compact size also overflows, the Draft keeps that size and scrolls
  vertically. A swipe that begins inside the text viewport scrolls the Draft;
  the containing Voice screen does not steal that gesture. Useful Draft text
  remains selectable in both editable and read-only states.
- A newly accepted Append follows the end only while the user is already at
  the end and has not moved or selected text manually. Manual scrolling or
  selection suspends follow-tail. A later Append then preserves the user's
  reading position and exposes one compact action for returning to the newest
  text; reaching the end or activating that action resumes follow-tail.
- A newly accepted replacement starts at the beginning of its new text. Clear
  also returns to the beginning. Undo and Redo preserve the reading position
  where possible. While editing, the system owns caret visibility and HoldType
  performs no competing programmatic scroll or font-size transition.
- The keyboard exposes Done and supports interactive dismissal. Ending focus
  commits the edit as one app-level Undo snapshot. While focused, system text
  editing owns character-level Undo and the app-level Undo and Redo actions are
  unavailable.
- Copy operates on the visible working text. Clear first commits the visible
  working text when editing is active, then atomically replaces that exact
  Draft with empty so Undo restores what the user saw before Clear. Translate,
  Correction, and new dictation are unavailable until the edit is safely
  committed.
- Starting, Listening, Finalizing, or Processing makes the editor read-only and
  cannot summon the keyboard. Clear and other Draft mutation controls remain
  unavailable throughout those active Voice phases. App-level Undo and Redo
  remain unavailable while an edit is active.
- A newly accepted containing-app Voice dictation replaces the visible Draft
  by default. As soon as a Replace attempt is admitted, the editor hides the
  previous Draft and presents the current recording or processing state plus a
  clear promise that the new text will appear there after completion. This is
  a presentation-only replacement preview: the confirmed Draft is not cleared
  or mutated before a new result is accepted.
- Cancel, failure, and recoverable Pending remove the replacement preview and
  reveal the latest confirmed Draft without creating an Undo mutation. A
  successful replacement publishes the accepted text and creates its normal
  single Undo snapshot.
- Append is an explicit session mode. While enabled, each newly accepted
  containing-app Voice dictation appends exactly once by accepted `resultID`,
  with one blank line between the existing Draft and the new text. During an
  admitted Append attempt, the existing Draft remains visible and the editor
  states that the new text will be added below after completion.
- The active editor promise follows the insertion mode frozen at Start, not a
  later local toggle or another scene's controls. VoiceOver exposes the same
  Replace-or-Append promise while the editor is read-only.
- Keyboard-controlled dictation follows the containing app's safe default and
  replaces the Draft unless a future keyboard contract exposes Append.
- Replace and Append are atomic Draft mutations. Both preserve exact-once
  accepted-result handling, create one process-local Undo snapshot when the
  previous Draft contains meaningful text, and never roll back Latest, History,
  or Pending cleanup when Draft persistence fails.
- The current Draft survives relaunch. Its canonical editable text is stored
  separately from the bounded accepted result identifiers used for exact-once
  append. It contains no audio, provider payload, prompt, credential, host
  context, or creation-history log.
- Copy writes the entire current Draft to the clipboard. It remains visible in
  the bottom Draft action area, is unavailable while the visible working text
  is empty, and has at least a 44-point tap target. A successful Copy does not
  add a visible notice or change the Draft card's layout; assistive technology
  still receives a concise confirmation.
- A Draft containing only spaces, tabs, or line breaks is treated as empty.
  Committing such an edit stores the canonical empty Draft rather than a hidden
  visually blank state.
- Clear atomically replaces the current Draft with empty. It never changes
  Latest, History, Pending, Recording Cache, usage, settings, or the keyboard
  projection. A neutral `Clear` control with an `xmark.circle` symbol appears
  only while the Draft contains visible working text, has at least a 44-point
  tap target, and does not require confirmation. Confirmed Clear presents
  `Draft cleared` with an explicit Undo action and a matching accessibility
  announcement.
- Undo and Redo cover successful replace, append, committed edit, and Clear
  mutations in the current process only. They retain at most twenty snapshots
  with meaningful text and are not persisted. Empty or visually
  blank Drafts are never Undo or Redo targets: creating the first meaningful
  Draft has no empty Undo target, and Undo may restore a Draft after Clear or a
  delete-to-empty edit without making that empty state available through Redo.
  A cold launch restores the current Draft but no hidden prior text.
- New mutation after Undo removes the forward Redo branch.
- A refresh that observes a different confirmed Draft removes the process-local
  Undo and Redo branches instead of applying snapshots from an older state.
- The durable Draft is one bounded protected atomic record with at most one
  hundred accepted result identifiers and four MiB of encoded data. Existing
  segment records migrate without losing text or exact-once identifiers. A
  full or unavailable Draft fails visibly without changing Latest or History.
- An edit uses compare-and-swap against its confirmed starting snapshot. A
  concurrent append or another scene never gets overwritten; the unsaved
  working text stays available for Copy while the user reloads or retries.

## Primary Voice Control

- A large Start Dictation action stays below the status and remains vertically
  centered inside the flexible free area above the tab bar. It must not stick
  to the bottom when that free area grows. It uses the same text-free HoldType
  activity artwork and motion as the macOS floating indicator instead of
  placing a microphone, progress spinner, or action label over the artwork.
  Its action name and state remain available to VoiceOver.
- Ready shows the complete cyan recording artwork as a static, full-color Start
  Dictation control. iOS does not invent a grey idle phase because the macOS
  floating indicator has only recording and transcribing phases.
- Listening uses the same primary location for Done and switches the control
  to the cyan recording phase: two rotating orbit lines, an orbiting point,
  and a subtle pulse. Voice never reserves layout space for a separate Cancel
  action. A deliberate long press on the primary activity reveals one compact
  cancellation icon over the activity without moving it; activating that icon
  cancels the currently admitted Start, recording, or processing command.
- Finalizing and provider processing switch the unavailable primary control to
  the purple recognition phase: a rotating particle ring and slower subtle
  pulse. The status row continues to distinguish local finalization,
  transcription, refinement, and result saving in text.
- Arming replaces the primary control with a native progress state while the
  status row shows exact progress. Its admitted cancellation uses the same
  long-press affordance and never appears in the ordinary action layout.
- In Ready, Arming, Listening, Finalizing, and Processing, the primary activity
  occupies one stable envelope whose center is exactly half the width and half
  the height of the flexible Voice area below the Draft. Status copy and the
  temporary cancellation overlay do not participate in that position's layout,
  so changing phase or status length never moves the activity.
- After activating the audio session, Voice freezes and validates the exact
  microphone input before it observes route changes or plays the start cue.
  An output-only route notification during Arming revalidates that frozen
  input and continues; a changed, unavailable, or muted input stops safely.
- After recorder finalization publishes Pending, the first transcription uses
  the canonical record read back from protected persistence. It must not reject
  that same recording as stale because persisted timestamps were normalized;
  Retry remains recovery for a real failed provider attempt, not a required
  second step for every new dictation.
- Setup, Pending recovery, blocked local recovery, unavailable runtime, and an
  unavailable Draft never show a disabled activity image. They replace the
  activity control with an explicit native recovery state containing the
  problem, the next action, and every exact corrective command currently
  admitted by the controller.
- `Voice unavailable` is not a user-facing diagnosis. Setup availability,
  microphone availability, credential access, protected local recovery, and a
  transiently interrupted Start remain distinct states with distinct copy.
- A transient Start failure keeps valid setup ready and restores Start
  Dictation immediately so the user can retry. It never converts a usable
  configuration into an unavailable setup state.
- A credential-access failure routes to OpenAI Settings and explains that the
  saved key must be reviewed or saved again. A microphone availability failure
  routes to Privacy & Permissions and explains what access or input to check.
- If a protected recording is already waiting to retry, the blocking Settings
  action remains visible alongside Retry and Discard; the recovery controls do
  not hide the action required to make Retry succeed.
- If HoldType cannot safely classify local Voice readiness, the recovery state
  includes Check Again. Check Again performs a bounded, non-destructive local
  readiness refresh; it never starts provider work, deletes a Draft, or
  discards a protected recording.
- A setup problem that belongs to Settings exposes one direct action to its
  owning OpenAI, Transcription, Translation, Keyboard, or Privacy & Permissions
  destination. Draft capacity and Draft storage problems stay on Voice and
  offer only their local Copy, Clear, or Retry resolution.
- A transient reconciliation interval says that Voice or Draft is being
  checked and shows progress; it never presents Ready while Start Dictation is
  not admitted.
- No unavailable state fabricates readiness or starts provider work.
- Reduce Motion replaces rotating and pulsing phases with their corresponding
  complete static recording or recognition artwork, preserving truthful state.

## Voice Session Modes

- A compact labeled `Auto` menu below the text editor contains the independent
  `Auto-Append`, `Auto-Translate`, and `Auto-Correct` toggles. The menu has no
  heading, subtitles, or explanatory copy. It presents in a compact popover
  above its leading-edge button in the normal portrait Voice layout and may
  reposition only when needed to remain onscreen. Each selected item shows a
  native checkmark, and toggling one item keeps the menu available so the user
  can change multiple modes in one visit.
- The `Auto` button has an intrinsic width and at least a 44-point tap target.
  With no selected modes it uses a neutral treatment and no count badge. With
  one or more selected modes it uses an accent treatment and a numeric badge
  showing the selected count. Accessibility exposes the count as `N of 3 on`.
  Flexible space keeps the independently sized `Copy` action aligned to the
  trailing edge of the same row.
- All three modes start off on cold launch. They remain selected for subsequent
  containing-app Voice attempts in the current process until the user turns
  them off. They do not rewrite durable Settings.
- The top one-shot Translate and Correction actions transform the complete
  current Draft in place. They never start recording or transcription and do
  not change the selected state of the bottom Auto menu.
- A one-shot action freezes the current confirmed Draft, shows the purple
  processing activity, and atomically replaces that same Draft only after the
  provider result is accepted. Translate uses the saved Translation route;
  Correction forces the saved Writing & Correction model and prompt without
  changing the durable correction preference.
- If Translation setup is incomplete, Translate remains tappable and opens the
  exact invalid source or missing target input with inline guidance. Provider,
  consent, timeout, validation, or local-save failure leaves the Draft
  unchanged and reports a short actionable failure.
- A successful one-shot replacement creates one app-level Undo snapshot and
  clears Redo. Repeating either action after completion processes the newly
  confirmed Draft. A tap while another one-shot action is active is ignored;
  actions are never queued or run concurrently.
- Translate and Correction may be enabled together. The existing processing
  order remains correction before translation for new dictation attempts.
- The exact selected modes are frozen at Start and carried by recoverable
  Pending state so Retry and relaunch cannot change the meaning of that attempt.
- Auto modes never transform text already visible in Draft. Replace or Append
  happens only after the new dictation result is accepted.
- Starting, Listening, Finalizing, Processing, editing, or a non-writable Draft
  may temporarily prevent conflicting session changes. Missing Translation
  setup is not such a safety state and never turns Translate into a dead control.

## Recovery

- Safely loaded Draft text remains visible and copyable while new dictation is
  unavailable.
- A stable setup blocker discovered at launch or during Voice preflight opens
  its exact owning Settings destination once. Returning to Voice without
  resolving it does not create an automatic navigation loop; the centered
  recovery state keeps the same direct action available.
- OpenAI, transcription, translation, and microphone/privacy setup route to
  their existing owning Settings screens. The destination scrolls the exact
  owning input into view and shows a contextual explanation beside it.
- Keyboard and Full Access recovery route to a dedicated Keyboard & Full Access
  setup screen with the complete public Settings path, an Open System Settings
  action, and a practice field. The containing app reports Full Access as not
  currently verified; it never invents a direct reading of the system switch.
- Missing Full Access blocks keyboard-controlled voice only. It never disables
  standalone foreground dictation, Draft editing, Copy, or safe Latest use.
- Recoverable capture and Pending states expose only the exact Recover, Retry,
  and confirmed Discard commands admitted by the shared Voice controller.
- Draft load or mutation failure preserves the last confirmed presentation and
  offers Retry where a safe read is possible.
- History-save and local-cleanup warnings remain nonblocking after an accepted
  result.

## Accessibility And Appearance

- VoiceOver exposes Draft as an editable text area when editing is available
  and names every available action and disabled reason.
- Dynamic Type may move actions vertically without clipping the Draft or
  recovery explanation.
- Draft body text uses the same scalable large-or-compact reading policy in
  both editing and read-only presentation. Reduce Motion makes adaptive type
  and follow-tail position changes immediate instead of animated.
- Light and Dark use the same geometry. Increase Contrast strengthens native
  boundaries; Reduce Transparency removes nonessential glow.
- Every activity PNG preserves transparent outer pixels and is rendered without
  a theme-colored bitmap background, grayscale filter, or disabled opacity
  transform. The cyan and purple artwork must remain legible in both Light and
  Dark appearance.
- The image asset contains no action label. Native text and SF Symbols remain
  crisp, localizable, and state-aware at every scale.

## Verification

- Focused persistence tests prove strict bounded decoding, exact-once append,
  atomic Clear/restore, identifier collision handling, and no hidden durable
  undo record.
- State-owner tests prove load, append, edit, Clear, meaningful-only Undo and
  Redo, forward-branch removal, refresh invalidation, conflict handling, and
  failure preservation.
- presentation tests cover empty, populated, loading, listening, processing,
  setup, Pending recovery, full Draft, unavailable states, Replace hiding,
  Append preservation, cancellation/failure restoration, adaptive type
  thresholds, and follow-tail suspension and resumption.
- Simulator QA covers cold launch without focus, tap-to-edit, keyboard Done and
  dismissal, the labeled bottom Copy action at compact and accessibility
  sizes, Clear/Undo, short and overflowing Drafts, Append while at the end and
  while reading earlier text, selection, ready, listening,
  recognition, setup, Draft failure and recovery routing, both appearances,
  Dynamic Type, Reduce Motion, and Reduce Transparency. A signed physical
  iPhone proves real microphone metering and Full Access behavior.
