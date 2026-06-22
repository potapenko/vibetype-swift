---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: archive-completed-automation-threads
status: active
---

# Archive Completed Automation Threads

This runbook is the runtime contract for the installed VibeType Swift
archive-housekeeping Codex automation. It is also the only scheduled
non-implementer automation that may run the broad current-user MCP cleanup
script.

Configured automation cwd:

```text
/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift
```

Codex home:

```text
/Users/eugenepotapenko/.codex
```

Expected schedule:

```text
FREQ=MINUTELY;INTERVAL=15
```

## Resource Cleanup Gate

At the end of the run, after verification/report preparation and immediately
before the final response, run from the repository root:

```sh
python3 scripts/automation_resource_cleanup.py
```

Include the cleanup JSON summary in the final report. If the script reports
remaining current-user processes, report the owner, pid, command, and reason
instead of claiming cleanup succeeded. Do not inspect or clean processes owned
by other OS users. Do not pass parameters to the script.

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

One scheduled automation invocation must drain pages internally. It must not
archive one visible page and rely on a later scheduled invocation to expose and
archive older pages. Within the same run, keep cycling through exact
current-repository automation id/name searches, readback, and archive calls
until a fresh post-archive tail check finds at most two remaining
readback-eligible threads, or until a real tool, readback, active-work, or
safety blocker prevents further progress.

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

If a candidate is active, running, pending, or otherwise not terminal, skip it
as `active_or_pending` and keep sweeping other candidates. Active or pending
current-repository automation threads are not archive-eligible, but their
presence must not block archiving separate readback-verified completed
automation-run threads in the same visible page.

If archive or readback reports `No Codex thread found` for a visible candidate
id, count it as `orphaned_or_stale` and continue. Do not report it as active
work.

## Page Drain Loop

Run discovery and archiving as an internal loop inside this single automation
invocation.

1. Build the search key set only from installed automation ids and names in the
   current-repository subset.
2. For each search key, call `list_threads` with that exact key and the largest
   practical `limit` supported by the tool so the sweep is not capped at the
   default recent-thread page.
3. Also call `list_threads` for the housekeeping automation id and name when
   the housekeeping automation definition belongs to the current repository.
4. De-duplicate candidate thread ids across all search results in the current
   sweep.
5. For each candidate id whose list result reports another cwd, skip it as
   `out_of_scope` without readback unless readback is needed to disambiguate a
   missing cwd.
6. For each in-scope candidate id, call `read_thread` before deciding.
7. Archive only candidates that pass the hard safety gate by calling
   `set_thread_archived` with `archived=true` and the explicit candidate id.
8. After archiving every eligible candidate from the visible batch, immediately
   run a fresh exact-key search/readback tail check in this same automation
   invocation.
9. If the fresh readback-verified eligible tail is more than two threads,
   immediately start the next loop iteration from step 1. Do not wait for the
   next scheduled run.
10. If the fresh readback-verified eligible tail is two or fewer threads, exit
    the page-drain loop successfully.

Do not stop just because a single list call returned one page, no page, no new
ids, or exactly the default-size result set. Re-run exact automation-id and
automation-name searches after each archive batch because archiving one visible
page can expose older unarchived threads. The two-thread allowance is only the
single-run loop escape hatch for concurrent automation runs created during
cleanup; it is not permission to leave additional eligible pages for a future
scheduled invocation.

## Tail Exit Rule

After each loop iteration and fresh tail check, calculate:

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

The two-thread allowance is not permission to skip the first visible batch. It
only prevents an endless loop after one full page has already been inspected
and every readback-eligible thread in that page has been archived. If more than
two eligible threads remain after the fresh tail check, run another page-drain
loop iteration in the same automation invocation.

If `remaining_eligible_tail_count > 2` and the latest loop iteration archived
zero threads after at least one visible batch has been inspected, stop with:

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
`remaining_eligible_tail_count` must be `0`, `1`, or `2`, and `sweeps` must
show that the internal page-drain loop completed inside this automation
invocation.
