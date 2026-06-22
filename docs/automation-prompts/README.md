---
kind: automation-project-index
automationLayer: per-user-automation-registry
status: active
---

# Automation Prompts

This folder records installed Codex automations that run against this VibeType
Swift checkout.

Repository cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`

Runtime runbooks:

- `runbooks/archive-completed-automation-threads.md`
- `runbooks/vibetype-swift-backlog-archiver.md`
- `runbooks/vibetype-swift-backlog-groomer.md`
- `runbooks/vibetype-swift-blocker-resolver.md`
- `runbooks/vibetype-swift-implementer.md`
- `runbooks/vibetype-swift-tooling-unblocker.md`

Restore-ready installed prompt snapshots:

- `installed/README.md`
- `installed/vibetype-swift-archive-completed-automation-threads.md`
- `installed/vibetype-swift-backlog-archiver.md`
- `installed/vibetype-swift-backlog-groomer.md`
- `installed/vibetype-swift-blocker-resolver.md`
- `installed/vibetype-swift-implementer.md`
- `installed/vibetype-swift-tooling-unblocker.md`

Shared tooling guidance:

- `../agent-tooling.md`

Recovery spec:

- `../specs/features/automation-prompt-recovery.md`

Only the implementer and archive-housekeeping automations may run
`python3 scripts/automation_resource_cleanup.py`. Information-gathering,
backlog-grooming, blocker-resolution, tooling-unblocker, and backlog-archiver
automations must not call that script because broad current-user `killall`
cleanup can conflict with other concurrent work. Every automation should still
keep MCP use task-specific, terminate or close resources clearly started by the
current run, report residual run-owned resources, and request archive of the
current automation thread before the final response when the thread-management
tool is available.

Per-user inventories:

- `users/eugenepotapenko.md`
