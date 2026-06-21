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

Shared tooling guidance:

- `../agent-tooling.md`

Every scheduled automation runbook must follow the hard final resource cleanup
and MCP/thread lifecycle rules in `../agent-tooling.md`: keep MCP use
task-specific, terminate or close every resource clearly started by the current
run, report any residual resource that cannot be terminated, and request
archive of the current automation thread before the final response when the
thread-management tool is available.

Per-user inventories:

- `users/eugenepotapenko.md`
