---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: archive-completed-automation-threads
status: active
---

# Archive Completed Automation Threads

This runbook is the runtime contract for the installed VibeType Swift
archive-housekeeping Codex automation.

Configured automation cwd:

```text
/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift
```

Codex home:

```text
/Users/eugenepotapenko/.codex
```

## Resource Cleanup Gate

At the start of the run, before thread-tool discovery or MCP-heavy work, run
from the repository root:

```sh
python3 scripts/automation_resource_cleanup.py --apply --min-age-seconds 60 --json
```

At the end of the run, after verification/report preparation and immediately
before the final response, run:

```sh
python3 scripts/automation_resource_cleanup.py --apply --min-age-seconds 0 --json
```

Include both cleanup JSON summaries in the final report. If the script reports
`permission_required`, `operator_commands`, or remaining processes, report the
owner, pid, command, and reason instead of claiming cleanup succeeded.

## Goal

Run one bounded housekeeping pass that archives temporary Codex threads created
by recurring automations for this repository after they are no longer live
work.

The primary eligible case is a completed automation run. A stale interrupted
automation run is also eligible only when readback proves it is not active work
and contains no manual continuation.

Do not archive manual or user-owned discussion threads.

Do not inspect, count, or archive automation threads from other repositories.
This runbook is scoped only to the configured automation cwd above. Threads
from any other cwd are out of scope even when they are visible in thread search
and even when they are also recurring automation runs.

The run must not finish after one discovery page or one search pass when more
eligible automation-run threads remain. Continue sweeping until the verified
remaining eligible tail is at most two threads, or until a real tool, readback,
active-work, or safety blocker prevents further progress.

## Required Tools

Use thread-management tools, not filesystem or database state, as the source of
truth for thread state:

- `list_threads`
- `read_thread`
- `set_thread_archived`

If these tools are not already visible in the active tool list, use tool
discovery first. If discovery cannot expose all three tools, stop and report:

```text
blocker=thread_tools_unavailable
```

Do not treat an empty initial discovery result as success. Try exact searches
by installed automation id and name before declaring that no candidates exist.

## Installed Automation Inventory

At the start of every run, inspect installed automation definitions from:

```text
/Users/eugenepotapenko/.codex/automations/*/automation.toml
```

Collect each installed automation id, name, prompt, cwd, status, schedule,
execution environment, and model. Keep only installed automations whose `cwd`
or `cwds` value contains this exact repository path:

```text
/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift
```

Use the live installed registry as the source of truth for this filtered
current-repository subset. Repository inventory docs are observational and may
be stale. Do not use installed automations from any other cwd to build search
keys, read threads, archive threads, or calculate the remaining tail.

The expected current-repository automation roles are implementation, backlog
grooming, blocker resolution, and archive housekeeping. This list is
descriptive only; the live installed registry controls the actual search key
set.

## Hard Safety Gate

A thread is archive-eligible only when every condition below is true:

- the thread belongs to the configured automation cwd exactly:
  `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`;
- the matched installed automation definition also belongs to that exact cwd;
- readback gives positive automation provenance, such as an automation id,
  automation name, automation run marker, or root user prompt matching an
  installed automation prompt from the current-repository automation subset;
- thread readback shows no active, running, pending, or live unfinished turn;
- the latest turn is terminal by one of these readback-verified states:
  - `completed`; or
  - `interrupted` and stale: the thread is not active, running, or pending, the
    visible update or start time is at least 30 minutes old, there is no tool
    call still running, no user message after the root automation prompt, no
    final question waiting for the user, and no active repo claim or blocker
    that the run is still expected to resolve;
- the thread is not pinned;
- the thread has no normal back-and-forth manual user conversation;
- the thread has no unresolved user question or blocker expecting user input;
- ownership is unambiguous.

Never archive a thread based only on title, preview, cwd, project name, topic
words, idle/notLoaded status, or a broad recent-thread page. These signals may
only provide candidate ids for readback verification.

Never archive a thread merely because it mentions automation, backlog,
implementer, blocker resolver, VibeType, Swift, archive, housekeeping, or any
known automation name.

If a candidate belongs to another cwd, skip it as `out_of_scope`.

If a candidate is ambiguous, unreadable, or lacks positive automation
provenance for the current repository, skip it as `manual_or_unclear`.

If archive or readback reports `No Codex thread found` for a visible candidate
id, count it as `orphaned_or_stale` and continue. Do not report it as active
work.

## Sweep Loop

Run discovery and archiving as a loop.

1. Build the search key set only from installed automation ids and names in the
   current-repository subset.
2. For each search key, call `list_threads` with that exact key.
3. Also call `list_threads` for the housekeeping automation id and name when
   the housekeeping automation definition belongs to the current repository.
4. De-duplicate candidate thread ids across all result pages searched.
5. For each candidate id whose list result reports another cwd, skip it as
   `out_of_scope` without readback unless readback is needed to disambiguate a
   missing cwd.
6. For each in-scope candidate id, call `read_thread` before deciding.
7. Archive only candidates that pass the hard safety gate by calling
   `set_thread_archived` with `archived=true` and the explicit candidate id.
8. After archiving the current batch, start a new sweep from step 1.

Do not stop just because a single list call returned one page, no page, or no
new ids. Re-run exact automation-id and automation-name searches after each
batch because archiving one page can expose older unarchived threads.

## Tail Exit Rule

After each full sweep, calculate:

```text
remaining_eligible_tail_count
```

This count is the number of currently visible, readback-verified,
archive-eligible current-repository automation-run threads that remain
unarchived after the sweep, including both completed runs and stale interrupted
runs that pass the hard safety gate.

Exit successfully only when:

```text
remaining_eligible_tail_count <= 2
```

The two-thread allowance prevents an endless loop while new automation runs are
being created during cleanup.

If `remaining_eligible_tail_count > 2` and the latest sweep archived zero
threads, stop with:

```text
blocker=no_progress_tail_above_threshold
```

Include candidate ids and skip reasons that prevented further progress. Do not
report success in this state.

## Current Run Thread

At the end, after the final report has enough information, follow the hard
final resource cleanup and MCP/thread lifecycle guidance in
`docs/agent-tooling.md`: terminate or close every resource the run started,
clean only non-durable run-owned temporary artifacts, and report any residual
resource that cannot be terminated. Then request archive of the current
housekeeping automation run thread by calling `set_thread_archived` with
`archived=true` and no `threadId`, when that tool is available.

Do not archive the current housekeeping thread before completing the sweep
report.

## Final Report

Report a compact operator summary with these fields:

- `automation`
- `schedule`
- `cwd`
- `installed_housekeeping_readback`
- `sweeps`
- `archived_count`
- `remaining_eligible_tail_count`
- `skipped_out_of_scope`
- `skipped_manual_or_unclear`
- `skipped_active_or_pending`
- `orphaned_or_stale`
- `blocker`
- `cleanup`
- `current_thread_archive`

`installed_housekeeping_readback` must include the readback-verified
housekeeping automation id, `status`, `rrule`, `execution_environment`, and
`cwds` from `/Users/eugenepotapenko/.codex/automations/*/automation.toml`.

If the run exits successfully, `blocker` must be `none` and
`remaining_eligible_tail_count` must be `0`, `1`, or `2`.
