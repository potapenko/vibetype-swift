# Agent Tooling

This document records repository-local expectations for Codex tools and MCP
servers. It is workflow guidance, not product behavior.

## Primary Target

The current product target is the native macOS menu bar MVP. iOS companion,
simulator, and keyboard-extension work is deferred to a future v2 phase unless
a direct user request or v2-specific automation run explicitly opts into those
lanes.

Normal implementer, blocker-resolver, and groomer runs should spend their
tooling budget on macOS build, run, runtime UI, and permission/paste evidence.

## Tool Discovery

Available MCP tools are session-local and can change with Codex configuration.
Before choosing a verification or UI-inspection path for Xcode, simulator, or
browser-visible work, inspect the active tool surface with `tool_search`. When
the Build macOS Apps plugin or macOS-capable XcodeBuildMCP tools are available,
prefer them for macOS Xcode build/run/test and interface inspection before
falling back to shell commands.

Use the most specific available tool first:

- Build macOS Apps or macOS-capable XcodeBuildMCP for Xcode project discovery,
  build settings, macOS app build/run/test, screenshots, runtime UI snapshots,
  and simple UI interactions when those tools are exposed in the current
  session.
- Standard `xcodebuild` shell commands for the macOS verification baseline when
  no matching macOS MCP tool is exposed or the MCP transport is unavailable.
- Computer Use only for bounded macOS runtime smoke of the actual app UI when
  the selected task changes a visible macOS surface or user interaction and the
  MCP surface cannot operate it directly.
- Build iOS Apps / iOS simulator tooling only for explicit v2 iOS work, not for
  ordinary macOS MVP implementation.

Do not assume that internet access or an open Xcode window means GUI
automation is available. Internet access, Build macOS Apps, XcodeBuildMCP,
Build iOS Apps, and Computer Use are separate capabilities.

## MCP And Thread Lifecycle

Local Codex automation threads may start MCP server processes for available
tool surfaces when a run thread is opened. Closing run-owned browser sessions,
apps, simulators, or dev servers does not by itself close the MCP server
processes owned by the Codex thread.

Keep MCP use narrow:

- Do not inspect MCP tools unless the selected task requires Xcode, simulator,
  browser-visible, or macOS runtime QA evidence.
- Prefer the documented shell `xcodebuild` commands for the macOS build/test
  baseline when they satisfy the selected task's verification.
- Use Computer Use only for changed visible macOS runtime behavior.
- Do not manually kill broad MCP process names from an automation run. Use the
  repository cleanup script only from the implementer final gate or the
  scheduled archive-housekeeping cleanup run.
- Use `python3 scripts/local_tooling_recover.py --apply --json` for
  allowlisted stale `xcodebuild`, `xctest`, `SWBBuildService`,
  compiler-probe, and project-scoped DerivedData recovery.

At the end of every scheduled automation run, after verification and checkpoint
handling are complete and before the final response, do not archive the current
automation thread. Normal workers must not call `set_thread_archived`.
Housekeeping is the only automation role that may call `set_thread_archived`,
and only for a different completed or safely stale automation thread after
`read_thread` verification, using an explicit `threadId`. Report
`Thread archive: external_sweeper`; a later housekeeping run from another
thread may archive the completed worker after readback verification.

## Run-Owned Resource Cleanup And Completion Gate

Every scheduled automation run must release resources it clearly started or
opened during that run:

- terminate run-owned app launches, dev servers, preview servers, browser
  sessions, Playwright/Chrome sessions, simulator sessions, Xcode/build/test
  subprocesses, audio or media helpers, and other local tool subprocesses;
- close or stop run-owned MCP/browser/computer-use sessions when the active
  tool surface exposes a scoped close or stop action;
- clean run-owned temporary screenshots, traces, profiles, downloads, bytecode,
  logs, and generated caches that are not durable evidence;
- preserve repository sources, committed evidence, durable reports, user-owned
  browser sessions, unrelated application state, databases, and object storage;
- never kill broad process-name matches unless the run is the implementer final
  gate, tooling-unblocker final gate, or archive-housekeeping cleanup run
  described below.

## Current-User MCP Killall Script

Only these automations may run the broad current-user MCP cleanup script:

- `holdtype-swift-implementer`, once at the end of an implementation run;
- `holdtype-swift-tooling-unblocker`, once at the end of a tooling recovery
  run;
- `holdtype-swift-archive-completed-automation-threads`, on its 3-hour
  housekeeping schedule.

The script takes no parameters. Run it from the repository root exactly as:

```sh
python3 scripts/automation_resource_cleanup.py
```

The script runs `killall -u <current-user>` for `SkyComputerUseClient`,
`mcp-server-darwin-arm64`, `node`, and `node_repl`, then terminates any
remaining allowlisted current-user Codex helper/MCP parent processes such as
`npm exec xcodebuildmcp@latest mcp`, `npm exec @playwright/mcp@latest`,
XcodeBuildMCP, Playwright MCP, Pencil MCP, Codex `node_repl`, and Codex browser
MCP.

The cleanup script is intentionally scoped to the current OS user only. Do not
pass another owner, do not prepare `sudo -u` cleanup commands for other users,
and do not treat processes owned by other users as part of this repository's
automation cleanup. If other-user processes are visible in `ps`, leave them out
of the cleanup result.

Information-gathering, backlog-grooming, blocker-resolution, and
backlog-archiver automations must not call this script. They should report only
resources they clearly started themselves.

At the end of scheduled automation runs, finish with the operator report only.
Do not call `set_thread_archived` for the current thread. The final response
must include both:

```text
Cleanup: <terminated/cleaned resources, or residual resources with reasons>
Thread archive: external_sweeper
```

Do not send the final response until cleanup has been attempted and reported.

## Build macOS Apps And XcodeBuildMCP

Official documentation:

- `https://www.xcodebuildmcp.com/docs`
- `https://www.xcodebuildmcp.com/docs/tools`
- `https://www.xcodebuildmcp.com/docs/configuration`

For this repository, useful defaults are:

```text
projectPath: /Users/eugenepotapenko/Projects/potapenko-github/holdtype-swift/HoldType.xcodeproj
macOS scheme: HoldType
configuration: Debug
platform: macOS for the macOS app
iOS scheme: HoldType-iOS, deferred to v2-only tasks
```

Set session defaults for the current run when the tool is available. Do not
persist `.xcodebuildmcp/config.yaml` unless the selected task explicitly asks
for version-controlled MCP configuration.

Prefer Build macOS Apps or macOS-capable XcodeBuildMCP for:

- discovering `.xcodeproj` and schemes;
- reading build settings, bundle ids, product paths, and DerivedData paths;
- macOS build, run, test, screenshot, UI snapshot, and simple interaction
  workflows when the active tool surface exposes them;
- LLDB/debugging workflows when a selected task asks for that evidence.

Use the repo's normal `xcodebuild` commands when:

- the current MCP tool surface does not expose a matching macOS build/run/test
  tool;
- full build or test logs are needed beyond the structured MCP response;
- the selected task's verification explicitly names `xcodebuild`.

`script/build_and_run.sh --verify` is the default automated runtime smoke path.
It launches with `HOLDTYPE_AUTOMATION=1`, which disables live Keychain access
and ignores any Debug key-file source.

`script/build_and_run.sh --live-debug` is an explicit manual live-provider path
for Debug builds. It reads `Config/HoldTypeDebugAPIKey.local` or
`HOLDTYPE_DEBUG_API_KEY_FILE` lazily, and must not be used for normal automated
verification, scheduled runs, UI tests, or Computer Use smoke unless the user
explicitly asks for a live OpenAI debug session.

Use Build iOS Apps / simulator tools only when a v2 iOS task is explicitly
selected with deferred lanes included. Normal macOS MVP runs must not spend
bounded verification time proving iOS simulator state.

## iOS Simulator, Mirroring, And Physical Device QA

Read this section before every explicit iOS interactive or device qualification
task. It defines workflow and evidence ownership; a feature plan may narrow a
lane further but must not silently broaden what that lane proves.

### Start And Tool Setup

Before the first UI action, start a scoped idle guard and record its PID:

```sh
caffeinate -dimsu >/dev/null 2>&1 &
echo $!
```

Keep that exact process alive for the complete Computer Use session. Stop it by
PID after all run-owned UI windows and previews are closed. Do not use a broad
`killall caffeinate` because another session may own a different guard.

```sh
kill <recorded-caffeinate-PID>
```

Use CLI or Xcode tooling for device discovery, builds, installation, launch
arguments, deterministic preparation, tests, and console capture. Use Computer
Use for every Mac-visible interaction that it can perform. Inspect fresh app
state before acting and after each meaningful action; prefer accessibility
elements and use coordinates only when no accessible control exists. Ask the
operator only for a genuinely unavailable physical or authentication gesture,
such as unlocking, trusting, or reconnecting the iPhone.

All waits, builds, launches, and log captures must be bounded. Never introduce
an unbounded poll while waiting for an app, Simulator, device, or UI state.

### Simulator Lane: Actual Keyboard And Host Interaction

Use Simulator for the custom-keyboard interaction lane unless the governing
task explicitly requires a signed-device keyboard matrix:

- build and install the current `HoldType-iOS` product with its embedded
  `HoldTypeKeyboard` extension;
- launch through a sanitized automation path so QA cannot read live Keychain
  credentials or call a live provider;
- enable and present the actual HoldType extension in a real editable host
  field, not a mock keyboard view or isolated rendering;
- use Notes when the selected Simulator runtime contains it; otherwise use the
  containing app's standard Keyboard Practice field only when the governing
  plan permits that substitution, and name the host honestly in evidence;
- record the observed Full Access setting before testing it. With Full Access
  off, exercise punctuation, Space, Delete, Return, and the system Globe on the
  real extension; with Full Access on, exercise only the bounded shared-
  container behavior required by the task;
- use focused tests for command/state reduction, expiry, stale request
  rejection, and the exact `UITextDocumentProxy` insertion count, but do not
  replace the interactive extension pass with those tests;
- capture screenshots only after the corresponding interaction and verify that
  visible labels are not clipped at the tested host width.

Simulator evidence does not prove physical microphone behavior, effective
device signing, device privacy indicators, secure-field substitution, or a
signed Notes-host release matrix.

### iPhone Mirroring Lane: Containing App Inspection Only

iPhone Mirroring is an optional Computer Use surface for operating and
observing the containing app. It is not a custom-keyboard qualification
surface: the Mac is treated as an external keyboard and may suppress the iPhone
onscreen keyboard. Do not spend time trying to present or test HoldType Keyboard
through Mirroring.

Do not use Mirroring as real-recording evidence when macOS reports
`iPhone microphone is not available from Mac`. Disconnect Mirroring before the
recording pass and drive the signed containing app directly on the iPhone with
an in-app DEBUG qualification control, a physical-device UI test, or a bounded
CoreDevice launch route. Mirroring screenshots may document containing-app
state only; they cannot substitute for recorder logs or device checks.

### Physical iPhone Lane: Signing And Real Recorder

Before implementation or qualification, confirm that a physical iPhone is
connected, paired, trusted, in Developer Mode, and available for development
services. Start with bounded read-only discovery such as:

```sh
xcrun devicectl list devices
xcrun xcdevice list
```

Build the current iOS scheme for the discovered UDID with the configured team
and automatic development signing. Do not hardcode a developer team, UDID,
profile, or device name in repository files:

```sh
xcodebuild -project HoldType.xcodeproj -scheme HoldType-iOS \
  -configuration Debug -destination 'id=<physical-device-UDID>' \
  DEVELOPMENT_TEAM=<configured-team> CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates build
```

Inspect the signed app and embedded extension products, not only source
settings. Record bundle identifiers, signing team/profile, OS/device model, and
matching App Group entitlements. Confirm that the microphone purpose string,
audio-session owner, and recorder exist only in the containing app; confirm the
extension's `RequestsOpenAccess` declaration separately.

For real recording, use bounded containing-app instrumentation that exercises
the same recorder lifecycle as the feature without requiring the keyboard:

1. Start an explicit session with a fixed deadline.
2. Publish Listening only after the real recording start call succeeds and the
   recorder reports that it is recording.
3. Drive Finish and confirm recording plus the audio session stop before any
   deterministic result becomes ready.
4. Run Cancel separately and confirm capture stops without a result or
   insertion.
5. Stop or expire the session and confirm there is no idle recorder, silent-
   audio keepalive, or retained temporary audio.

Use device console evidence for lifecycle transitions. Record the system
microphone indicator only when the selected wired capture surface exposes it;
if QuickTime or another preview omits the indicator while device logs confirm
recording, report the visual observation as unavailable rather than inventing
it. A physical containing-app probe does not by itself prove keyboard insertion
in Notes.

### Evidence And Cleanup

Keep Simulator keyboard results, Mirroring containing-app observations, and
physical-device signing/recording results in separate QA sections. Every result
must name commit/build, device or Simulator, OS, starting state, action,
expected result, actual result, and privacy/energy observations. Never call a
physical gate passed from Simulator-only evidence, and never reuse a bounded
feasibility split to waive a later signed-device release matrix.

At the end, close only run-owned Mirroring, QuickTime preview, Simulator, Xcode,
and helper sessions; preserve user-owned app state and durable QA artifacts.
Stop the recorded `caffeinate` PID and report any lane that remained blocked.

## Local Xcode Recovery

Agents repair local tooling problems themselves. Before stopping on a local
Xcode, simulator, build-service, test-runner, compiler-probe, cache, project
DerivedData, missing command-line utility, missing Apple platform, or missing
local library blocker, agents must run:

```sh
python3 scripts/local_tooling_recover.py --apply --json
```

Then install or configure any missing local utility/library/platform needed for
the selected task and rerun the narrow bounded verification that originally
failed. Report the recovery summary, install/configuration action when used,
and the rerun result. Local Xcode/tooling problems are automation-recoverable;
reserve `operator-only` for actions that need a real user decision, external
login, privacy approval, payment/account change, destructive Git rollback, or
destructive database/object-storage operation.

## macOS Runtime QA

Build macOS Apps / macOS-capable XcodeBuildMCP can prove project and runtime
state when exposed in the current session. When the task changes menu bar UI,
Settings, permission/status UI, recording controls, floating indicator, or paste
handoff, follow `docs/qa/macos/AGENTS.run.md` and record the runtime QA decision
from `docs/specs/features/platform-testing-strategy.md`.

If the MCP surface cannot operate the changed UI, use Computer Use for bounded
runtime smoke. If Computer Use or app launch is blocked, report `Runtime QA:
blocked` with the exact blocker and keep build/test evidence explicit. Do not
silently downgrade a visible UI task to code-only verification.

## Reporting

Automation reports should include the Xcode/MCP path used:

```text
Tooling: XcodeBuildMCP | xcodebuild | Computer Use | not_applicable
MCP tools checked: yes | no, reason
Runtime QA: required | not_applicable | blocked
```
