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
  processes may belong to other active user or automation threads.

At the end of every scheduled automation run, after verification and checkpoint
handling are complete and before the final response, request archive of the
current automation thread with `set_thread_archived` using `archived: true` and
no `threadId` when the thread-management tool is available. Report
`Thread archive: requested`. If the archive tool is unavailable, report
`Thread archive: unavailable` and keep the rest of the cleanup bounded to
artifacts clearly owned by the current run.

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
