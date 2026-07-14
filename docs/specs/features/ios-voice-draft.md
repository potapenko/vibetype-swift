# iOS Voice Draft

Status: approved product contract; 2026-07-14.

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
- Translate and Correction are visible one-shot actions in the Draft action
  row.
  Keyboard Dictation Session and the practice field remain reachable from the
  compact Voice More menu; the keyboard tools are presented as a sheet and
  none of them occupies the primary Voice canvas.

## Draft

- Voice presents one app-private composed Draft independently from Latest,
  History, Pending, Recording Cache, and the keyboard projection.
- The Draft is a vertically scrollable text editor that starts unfocused.
  Launch never focuses it or opens the keyboard. A direct tap focuses it and
  enables normal selection, typing, paste, and system emoji input.
- The keyboard exposes Done and supports interactive dismissal. Ending focus
  commits the edit as one app-level Undo snapshot. While focused, system text
  editing owns character-level Undo and the app-level Undo and Redo actions are
  unavailable.
- Copy and Clear operate on the visible working text. Translate, Correction,
  and new dictation are unavailable until the edit is safely committed.
- Starting, Listening, Finalizing, or Processing makes the editor read-only and
  cannot summon the keyboard. Draft mutation controls remain unavailable while
  an edit is active.
- Each accepted Voice or keyboard-controlled dictation appends exactly once by
  accepted `resultID`. Accepted chunks are separated by one blank line.
- The current Draft survives relaunch. Its canonical editable text is stored
  separately from the bounded accepted result identifiers used for exact-once
  append. It contains no audio, provider payload, prompt, credential, host
  context, or creation-history log.
- Copy writes the entire current Draft to the clipboard.
- Clear atomically replaces the current Draft with empty. It never changes
  Latest, History, Pending, Recording Cache, usage, settings, or the keyboard
  projection.
- Undo and Redo cover successful append, committed edit, and Clear mutations in
  the current process only. They are bounded to twenty snapshots and are not
  persisted.
  A cold launch restores the current Draft but no hidden prior text.
- New mutation after Undo removes the forward Redo branch.
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
- Listening uses the same primary location for Done, shows elapsed time plus a
  separate Cancel action, and switches the control to the cyan recording
  phase: two rotating orbit lines, an orbiting point, and a subtle pulse.
- Finalizing and provider processing switch the unavailable primary control to
  the purple recognition phase: a rotating particle ring and slower subtle
  pulse. The status row continues to distinguish local finalization,
  transcription, refinement, and result saving in text.
- Arming replaces the primary control with a native progress state while the
  status row shows exact progress. Cancel appears only when the controller
  admits it.
- Setup, Pending recovery, blocked local recovery, unavailable runtime, and an
  unavailable Draft never show a disabled activity image. They replace the
  activity control with an explicit native recovery state containing the
  problem, the next action, and every exact corrective command currently
  admitted by the controller.
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

## One-Shot Processing Actions

- Translate and Correction are compact icon-only buttons at the leading edge
  of the Draft action row. A flexible gap separates them from Undo, Redo,
  Copy, and Clear at the trailing edge. The row has no visible title because
  the Draft surface itself already supplies the necessary context. VoiceOver
  still exposes a text label for each icon.
- Translate and Correction remain visible but unavailable unless the shared
  Voice controller admits the corresponding Start action.
- Translate starts one new dictation with the saved Translation route. It is
  enabled only while Voice is ready and the current translation target and
  source route are valid.
- Correction starts one new standard-output dictation and forces the saved
  Writing & Correction model and prompt for that request only. It does not
  change the durable correction preference and retains the existing safe
  fallback to the accepted transcript.
- Neither action transforms the text already shown in Draft. An accepted
  result appends through the same exact-once Draft path as standard dictation.
- The selected action is frozen at Start. Translate and Correction are not
  toggles, expose no selected state, and do not change Settings. Once started,
  the existing Done and Cancel controls own the attempt.
- Starting, Listening, Finalizing, Processing, recovery, setup, unavailable,
  or non-writable Draft states keep both actions visible and disabled.

## Recovery

- Safely loaded Draft text remains visible and copyable while new dictation is
  unavailable.
- A stable setup blocker discovered at launch or during Voice preflight opens
  its exact owning Settings destination once. Returning to Voice without
  resolving it does not create an automatic navigation loop; the centered
  recovery state keeps the same direct action available.
- OpenAI, transcription, translation, and microphone/privacy setup route to
  their existing owning Settings screens. The destination shows a contextual
  Voice Setup message explaining why it opened and what the user must complete.
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
- State-owner tests prove load, append, edit, Clear, Undo, Redo, forward-branch
  removal, conflict handling, and failure preservation.
- presentation tests cover empty, populated, loading, listening, processing,
  setup, Pending recovery, full Draft, and unavailable states.
- Simulator QA covers cold launch without focus, tap-to-edit, keyboard Done and
  dismissal, Copy, Clear/Undo, ready, listening, recognition, setup, Draft
  failure and recovery routing, both appearances, Dynamic Type, Reduce Motion,
  and Reduce Transparency. A signed physical iPhone proves real microphone
  metering and Full Access behavior.
