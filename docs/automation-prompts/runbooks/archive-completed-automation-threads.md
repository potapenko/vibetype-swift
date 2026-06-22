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
FREQ=MINUTELY;INTERVAL=1
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

The primary eligible case is a completed automation run. Stale interrupted or
stale hanging in-progress automation runs are also eligible only when readback
proves they are no longer live work and contain no manual continuation.

Do not archive manual or user-owned discussion threads.

Do not inspect, count, or archive automation threads from other repositories.
This runbook is scoped only to the configured automation cwd above. Threads
from any other cwd are out of scope even when they are visible in thread search
and even when they are also recurring automation runs.

One scheduled automation invocation must drain pages internally. It must not
archive one visible page and rely on a later scheduled invocation to expose and
archive older pages. Within the same run, keep cycling through the currently
visible sidebar page, readback, and archive calls. The primary discovery source
is `list_threads` without a query, filtered by exact cwd and
readback-verified automation provenance. Exact automation id/name searches are
only supplemental fallback discovery; they must not replace the general
visible-page pass because exact search can miss sidebar-visible rows. The
first visible eligible page is mandatory: archive every readback-eligible
thread from that first page, even when it contains only one or two eligible
threads. The two-thread allowance applies only after at least one eligible
visible page has been archived in this invocation, when deciding whether to
start another page-drain pass. After each archive batch, immediately re-list so
older pages can surface in the same run. Stop only when the next fresh visible
page contains two or fewer readback-eligible threads, or when a real tool,
readback, active-work, or safety blocker prevents further progress.

## Thread Tools And Registry Fallback

Use thread-management tools as the first source of truth for thread state when
they are available:

- `list_threads`
- `read_thread`
- `set_thread_archived`

Cron automation sessions may not expose these thread tools. When they are not
available, use only the repository helper below as the fallback source of
truth. Do not write ad hoc SQLite queries or use a helper that scans only one
`state_5.sqlite` location. The fallback helper must scan every supported local
Codex state DB it knows about, currently both
`/Users/eugenepotapenko/.codex/sqlite/state_5.sqlite` and
`/Users/eugenepotapenko/.codex/state_5.sqlite`, because the live sidebar may be
backed by either location during Codex app migrations.

Thread-management calls must be sequential. Do not call `list_threads`,
`read_thread`, or `set_thread_archived` through parallel tool wrappers, and do
not run them in parallel with shell/file reads. Wait for each thread-management
call to return before issuing the next thread-management call. If a
thread-management call appears to hang, continue only through the readback gates
below; do not start duplicate archive calls for the same candidate.

If these tools are not already visible in the active tool list, use tool
discovery first. If discovery cannot expose all three tools, run the local
registry fallback sweep instead of reporting success or guessing.

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
- the latest turn is terminal by one of these readback-verified states:
  - `completed`; or
  - `interrupted` and stale: the thread is not active, running, or pending, the
    visible update or start time is at least 30 minutes old, there is no tool
    call still running, no user message after the root automation prompt, no
    final question waiting for the user, and no active repo claim or blocker
    that the run is still expected to resolve; or
  - stale hanging `inProgress`: the thread is still marked active/in-progress,
    but the latest visible progress is at least 30 minutes old, readback shows
    no running or pending tool call, no user message after the root automation
    prompt, no final question waiting for the user, and either the run has
    already reached cleanup/final-report/current-thread-archive wording or the
    repository has no uncommitted files that can be attributed to that
    automation run; or
  - self-archive hanging `inProgress`: the thread is still marked
    active/in-progress, but readback shows the run has reached the final
    thread-archive request step, no tool call is running or pending, there is
    no user message after the root automation prompt, and there is no unresolved
    user question. This case is eligible without waiting 30 minutes because the
    run has already declared its work complete and is stuck only on archiving
    itself; or
  - housekeeping thread-tool hanging `inProgress`: the thread is this
    housekeeping automation id for this exact cwd, readback shows no running or
    pending tool call, no user message after the root automation prompt, no
    unresolved user question, no repository files attributable to that
    housekeeping run, and the latest visible progress has been waiting on
    thread-tool discovery, `list_threads`, `read_thread`, or
    `set_thread_archived` for at least 2 minutes. This shorter gate applies only
    to this archive-housekeeping automation because its sole job is thread
    cleanup and a hung thread-tool step otherwise leaves cleanup residue;
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

If a candidate is active, running, pending, or otherwise not terminal and does
not pass the stale hanging, self-archive hanging, or housekeeping thread-tool
hanging `inProgress` eligibility gates above, skip it as `active_or_pending`
and keep sweeping other candidates. Active or pending current-repository
automation threads that are still live work are not archive-eligible, but their
presence must not block archiving separate readback-verified completed, stale
hanging, self-archive hanging, or housekeeping thread-tool hanging
automation-run threads in the same visible page.

If archive or readback reports `No Codex thread found` for a visible candidate
id, count it as `orphaned_or_stale` and continue. Do not report it as active
work.

## Page Drain Loop

Run discovery and archiving as an internal loop inside this single automation
invocation.

1. Call `list_threads` without a query using the largest practical `limit`
   supported by the tool. This unfiltered call is mandatory because it mirrors
   the sidebar page and can reveal current-repository automation rows that
   exact text searches miss.
2. Keep only list results whose `cwd` is exactly the configured repository cwd
   or whose cwd is missing/ambiguous and needs readback to decide.
3. Add supplemental candidates from exact installed automation id/name searches
   only after the unfiltered visible-page pass has run. These supplemental
   searches may catch rows absent from the unfiltered page, but they do not
   define the page-stop condition.
4. De-duplicate candidate thread ids across the unfiltered visible page and
   supplemental exact-key results.
5. For each candidate id whose list result reports another cwd, skip it as
   `out_of_scope` without readback unless readback is needed to disambiguate a
   missing cwd.
6. For each in-scope candidate id, call `read_thread` before deciding.
7. Count the readback-eligible candidates from the mandatory unfiltered
   visible-page pass. Supplemental exact-key candidates may be archived in the
   same batch, but they do not reduce or inflate this visible-page count.
8. On the first loop iteration, archive every readback-eligible candidate from
   the visible batch, even when the first visible page contains only one or two
   eligible candidates. If the first visible page contains zero eligible
   candidates, exit the page-drain loop successfully.
9. On later loop iterations, if the current visible page contains two or fewer
   readback-eligible candidates, do not archive that page; exit the page-drain
   loop successfully.
10. On later loop iterations, if the current visible page contains more than
    two readback-eligible candidates, archive every eligible candidate from
    that visible batch.
11. Also archive any supplemental exact-key candidates that pass the hard
    safety gate in this batch, unless doing so would archive one of the small
    residual visible-page candidates that the page-stop rule allowed to remain.
12. Immediately start the next loop iteration from step 1 in this same
    automation invocation so older pages can surface. Do not wait for the next
    scheduled run.

An archive batch means the complete eligible list for that pass, not a single
thread id. Collect the eligible ids first, then call `set_thread_archived`
sequentially for every eligible id in the batch. Do not report success after
archiving only one candidate while other eligible candidates from the same
visible or supplemental batch remain.

Do not stop just because a single list call returned one page, no page, no new
ids, or exactly the default-size result set. Re-run the unfiltered
`list_threads` visible-page pass after each archive batch because archiving one
visible page can expose older unarchived threads. The two-thread allowance is
only the post-first-batch page-stop escape hatch for a small residual visible
page; it is not permission to skip the first eligible page, archive one large
page and leave additional large eligible pages for a future scheduled
invocation, or finish a run without archiving currently visible eligible
threads.

## Local Registry Fallback Sweep

If thread-management tools are unavailable in the cron session, or after a
thread-tool sweep needs full-registry verification, run the local registry
helper from the repository root. This helper scans all supported local Codex
state DBs for the exact configured cwd and installed current-repository
automation ids/names, so it is not limited to the currently visible
`list_threads` page.

Dry-run command:

```sh
python3 scripts/archive_codex_threads.py --target-cwd /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift --json
```

If the dry-run reports `remaining_eligible_count > 0`, run apply:

```sh
python3 scripts/archive_codex_threads.py --target-cwd /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift --apply --json
```

The helper must create a SQLite backup before applying archive updates, update
only rows whose `cwd` is this configured repository and whose automation
provenance matches the installed current-repository subset, and move archived
rollout files from `/Users/eugenepotapenko/.codex/sessions` to
`/Users/eugenepotapenko/.codex/archived_sessions`.

The helper archives the whole eligible registry batch in one apply pass. If the
dry-run or apply report lists `eligible_count = N`, the apply pass must attempt
all N eligible rows, not just the first row. Keep looping dry-run/apply in the
same automation invocation until `remaining_eligible_count = 0`, or until an
apply pass archives zero rows while eligible rows remain.

## Tail Exit Rule

During each loop iteration, calculate:

```text
visible_page_eligible_count
```

This count is the number of readback-verified archive-eligible
current-repository automation-run threads in the mandatory unfiltered
`list_threads` visible page, including completed, stale interrupted, stale
hanging in-progress, and self-archive hanging in-progress runs that pass the
hard safety gate.

Exit successfully only when the first visible page has no eligible candidates:

```text
first_visible_page_eligible_count == 0
```

or when at least one eligible visible page has already been archived in this
invocation and the next fresh visible page satisfies:

```text
visible_page_eligible_count <= 2
```

and the local registry fallback report satisfies:

```text
remaining_eligible_count = 0
```

The two-thread allowance is permission to leave a small residual visible page
unarchived after the mandatory first eligible page has been archived. It is not
permission to skip the first visible page, and it is not permission to skip a
visible page with more than two eligible threads. If more than two eligible
threads are visible after the first archive batch, archive that page and run
another page-drain loop iteration in the same automation invocation.

If `visible_page_eligible_count > 2` and the latest loop iteration archived
zero threads, stop with:

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
- `visible_page_eligible_count`
- `remaining_eligible_tail_count`
- `registry_archived_count`
- `registry_remaining_eligible_count`
- `registry_allowed_active_count`
- `registry_backup_paths`
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
`visible_page_eligible_count` must be `0`, `1`, or `2`; `sweeps` must show
that the internal page-drain loop completed inside this automation invocation.
`registry_remaining_eligible_count` must be `0`. `remaining_eligible_tail_count`
may repeat the visible-page count when the tool does not expose a cursor or
total result count.
