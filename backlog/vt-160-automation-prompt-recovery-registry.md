---
id: VT-160
status: in-progress
priority: P1
lane: automation
dependencies:
allowed_paths:
  - backlog/vt-160-automation-prompt-recovery-registry.md
  - docs/specs/features/automation-prompt-recovery.md
  - docs/automation-prompts/README.md
  - docs/automation-prompts/users/eugenepotapenko.md
  - docs/automation-prompts/installed/**
verification:
  - git diff --check
---

# VT-160 - Automation Prompt Recovery Registry

Status: in-progress
Priority: P1
Lane: automation
Dependencies: none
Expected outputs: automation recovery spec, installed automation inventory,
one prompt snapshot file per current-repository automation
Verification: git diff --check

## Scope

Record every installed Codex automation for the exact VibeType Swift cwd in
git-verifiable repository files so the automations can be verified and
recreated if the local Codex automation registry is lost.

The registry must include each automation's id, name, description, status,
schedule, model, reasoning effort, execution environment, cwd, prompt source,
and full installed prompt.

## Out Of Scope

- changing installed Codex automations
- editing sibling repositories
- backing up automations for other cwd values
- changing Swift product behavior
