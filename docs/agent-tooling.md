# Agent Tooling

This document records repository-local expectations for Codex tools and MCP
servers. It is workflow guidance, not product behavior.

## Tool Discovery

Available MCP tools are session-local and can change with Codex configuration.
Before choosing a verification or UI-inspection path for Xcode, simulator, or
browser-visible work, inspect the active tool surface with `tool_search`.

Use the most specific available tool first:

- XcodeBuildMCP for Xcode project discovery, build settings, simulator
  build/run/test, simulator screenshots, simulator UI snapshots, and simple
  simulator interactions.
- Standard `xcodebuild` shell commands for the macOS verification baseline
  when no matching macOS MCP tool is exposed in the current session.
- Computer Use only for bounded macOS runtime smoke of the actual app UI when
  the selected task changes a visible macOS surface or user interaction.

Do not assume that internet access or an open Xcode window means GUI
automation is available. Internet access, XcodeBuildMCP, and Computer Use are
separate capabilities.

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
- Do not manually kill broad MCP process names from an automation run; those
  processes may belong to other active user or automation threads. This does
  not make stale Xcode build/test tooling operator-only. Use
  `python3 scripts/local_tooling_recover.py --apply --json` for allowlisted
  stale `xcodebuild`, `xctest`, `SWBBuildService`, compiler-probe, and
  project-scoped DerivedData recovery.

At the end of every scheduled automation run, after verification and checkpoint
handling are complete and before the final response, request archive of the
current automation thread with `set_thread_archived` using `archived: true` and
no `threadId` when the thread-management tool is available. Report
`Thread archive: requested`. If the archive tool is unavailable, report
`Thread archive: unavailable` and keep the rest of the cleanup bounded to
artifacts clearly owned by the current run.

## Hard Final Resource Cleanup And Archive Gate

Every scheduled automation run must treat resource cleanup as a required final
gate, not a best-effort note. Before the final response, the run must release
everything it started or opened during that run:

- terminate run-owned app launches, dev servers, preview servers, browser
  sessions, Playwright/Chrome sessions, simulator sessions, Xcode/build/test
  subprocesses, audio or media helpers, and other local tool subprocesses;
- close or stop run-owned MCP/browser/computer-use sessions when the active
  tool surface exposes a scoped close or stop action;
- clean run-owned temporary screenshots, traces, profiles, downloads, bytecode,
  logs, and generated caches that are not durable evidence;
- preserve repository sources, committed evidence, durable reports, user-owned
  browser sessions, unrelated application state, databases, and object storage;
- never kill broad process-name matches unless the process is clearly owned by
  the current run, current process tree, selected task, or repository recovery
  helper.

If a process or session cannot be terminated because ownership is ambiguous,
the OS denies permission, or the tool surface has no scoped close action, the
run must report the residual resource with the best available `pid`, owner,
command, cwd or tool name, and reason it was left running. This is still a
cleanup result; silently leaving resources behind is not allowed.

After cleanup, the run must request archive of the current automation thread
with `set_thread_archived` using `archived: true` and no `threadId` when that
tool is available. The final response must include both:

```text
Cleanup: <terminated/cleaned resources, or residual resources with reasons>
Thread archive: requested | unavailable
```

Do not send the final response until this gate has been attempted and reported.

## XcodeBuildMCP

Official documentation:

- `https://www.xcodebuildmcp.com/docs`
- `https://www.xcodebuildmcp.com/docs/tools`
- `https://www.xcodebuildmcp.com/docs/configuration`

For this repository, useful defaults are:

```text
projectPath: /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/vibetype.xcodeproj
macOS scheme: vibetype
iOS scheme: vibetype-iOS
configuration: Debug
platform: macOS for the macOS app
```

Set session defaults for the current run when the tool is available. Do not
persist `.xcodebuildmcp/config.yaml` unless the selected task explicitly asks
for version-controlled MCP configuration.

Prefer XcodeBuildMCP for:

- discovering `.xcodeproj` and schemes;
- reading build settings, bundle ids, product paths, and DerivedData paths;
- iOS simulator build/run/test, screenshots, UI snapshots, and interactions;
- LLDB/debugging workflows when a selected task asks for that evidence.

Use the repo's normal `xcodebuild` commands when:

- the selected task is macOS-only and the current MCP tool surface does not
  expose a matching macOS build/run/test tool;
- full build or test logs are needed beyond the structured MCP response;
- the selected task's verification explicitly names `xcodebuild`.

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

XcodeBuildMCP can prove project and simulator state, but it is not a substitute
for operating a changed macOS app surface. When the task changes menu bar UI,
Settings, permission/status UI, recording controls, floating indicator, or
paste handoff, follow `docs/qa/macos/AGENTS.run.md` and record the runtime QA
decision from `docs/specs/features/platform-testing-strategy.md`.

If Computer Use or app launch is blocked, report `Runtime QA: blocked` with
the exact blocker and keep build/test evidence explicit. Do not silently
downgrade a visible UI task to code-only verification.

## Reporting

Automation reports should include the Xcode/MCP path used:

```text
Tooling: XcodeBuildMCP | xcodebuild | Computer Use | not_applicable
MCP tools checked: yes | no, reason
Runtime QA: required | not_applicable | blocked
```
