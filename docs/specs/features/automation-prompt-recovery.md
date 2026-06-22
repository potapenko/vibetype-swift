# Automation Prompt Recovery

## Goal

Keep every installed Codex automation for this repository recoverable from
versioned files.

If the local Codex automation registry is lost, a future agent must be able to
recreate the repository automations without relying on chat history or memory.

## Scope

This spec covers automations whose configured cwd exactly matches:

```text
/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift
```

Automations for sibling repositories or other cwd values are out of scope for
this repository's recovery registry.

## Required Repository Records

The repository must keep:

- one per-user inventory under `docs/automation-prompts/users/`;
- one restore-ready prompt snapshot per installed automation under
  `docs/automation-prompts/installed/`;
- the runtime runbooks that short pointer prompts reference under
  `docs/automation-prompts/runbooks/`;
- this spec as the product/workflow contract for the recovery layer.

Each installed automation snapshot must record:

- automation id;
- kind;
- human-readable name;
- installed status;
- schedule or period (`rrule`);
- model and reasoning effort;
- execution environment;
- configured cwd;
- prompt source/runbook path when applicable;
- full installed prompt text;
- source `automation.toml` path and inspection date.

## Recovery Behavior

When asked to recreate an automation, an agent must:

1. Read this spec.
2. Read the matching file in `docs/automation-prompts/installed/`.
3. Use the snapshot's restore fields for schedule, model, reasoning effort,
   execution environment, cwd, status, name, and kind.
4. Use the snapshot's `Installed Prompt` block exactly as the automation
   prompt.
5. Prefer updating an existing matching automation over creating a duplicate.
6. Verify the recreated automation by viewing it after creation/update and
   comparing the restored fields to the snapshot.
7. Commit any snapshot changes if the recreated automation receives a different
   local id or if the prompt/schedule intentionally changes.

## Update Rule

Any intentional automation change must update the git-backed recovery files in
the same repository task:

- `docs/automation-prompts/users/eugenepotapenko.md`;
- the matching `docs/automation-prompts/installed/<automation-id>.md`;
- the referenced runbook when the prompt delegates behavior to a runbook.

Do not treat the local Codex automation registry as the only source of truth.
It is the live installation state; the repository snapshots are the recovery
source.

## Verification

For docs-only recovery registry changes, run:

```sh
git diff --check
```

When the local Codex automation registry still exists, also inspect:

```sh
/Users/eugenepotapenko/.codex/automations/*/automation.toml
```

and compare every exact-cwd automation with the corresponding installed prompt
snapshot before reporting the recovery registry current.

## Non-Goals

- Do not back up automations for other repositories here.
- Do not run or change scheduled automations just to update the registry.
- Do not store secrets in automation prompts or recovery snapshots.
- Do not use chat memory as a recovery source.
