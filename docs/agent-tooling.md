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
handling are complete and before the final response, request archive of the
current automation thread with `set_thread_archived` using `archived: true` and
no `threadId` when the thread-management tool is available. Report
`Thread archive: requested`. If the archive tool is unavailable, report
`Thread archive: unavailable` and keep the rest of the cleanup bounded to
artifacts clearly owned by the current run.

## Run-Owned Resource Cleanup And Archive Gate

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
  gate or the archive-housekeeping cleanup run described below.

## Current-User MCP Killall Script

Only these automations may run the broad current-user MCP cleanup script:

- `vibetype-swift-implementer`, once at the end of an implementation run;
- `vibetype-swift-archive-completed-automation-threads`, on its 3-hour
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

Information-gathering, backlog-grooming, blocker-resolution, tooling-unblocker,
and backlog-archiver automations must not call this script. They should report
only resources they clearly started themselves.

At the end of scheduled automation runs, request archive of the current thread
with `set_thread_archived` using `archived: true` and no `threadId` when that
tool is available. The final response must include both:

```text
Cleanup: <terminated/cleaned resources, or residual resources with reasons>
Thread archive: requested | unavailable
```

Do not send the final response until this gate has been attempted and reported.

## Build macOS Apps And XcodeBuildMCP

Official documentation:

- `https://www.xcodebuildmcp.com/docs`
- `https://www.xcodebuildmcp.com/docs/tools`
- `https://www.xcodebuildmcp.com/docs/configuration`

For this repository, useful defaults are:

```text
projectPath: /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/vibetype.xcodeproj
macOS scheme: vibetype
configuration: Debug
platform: macOS for the macOS app
iOS scheme: vibetype-iOS, deferred to v2-only tasks
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

Use Build iOS Apps / simulator tools only when a v2 iOS task is explicitly
selected with deferred lanes included. Normal macOS MVP runs must not spend
bounded verification time proving iOS simulator state.

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
