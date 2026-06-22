---
id: VT-160
status: done
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

Status: done
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

## Completion Notes

- Added `docs/specs/features/automation-prompt-recovery.md`.
- Added restore-ready prompt snapshots under
  `docs/automation-prompts/installed/` for all six installed automations whose
  cwd exactly matches this repository.
- Updated the per-user automation inventory to point at the prompt snapshots
  and reflect the current installed schedules.
- Updated `docs/automation-prompts/README.md` to make the recovery layer
  discoverable.

## Verification

Passed:

```sh
python3 - <<'PY'
from pathlib import Path
import re
import tomli
repo = Path('/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift')
base = Path('/Users/eugenepotapenko/.codex/automations')
target = '/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift'
errors = []
count = 0
for toml_path in sorted(base.glob('*/automation.toml')):
    data = tomli.loads(toml_path.read_text())
    if target not in data.get('cwds', []):
        continue
    count += 1
    md_path = repo / 'docs/automation-prompts/installed' / f"{data['id']}.md"
    text = md_path.read_text()
    block = re.search(r'## Installed Prompt\n\n```text\n(.*)\n```\n\Z', text, re.S)
    assert block and block.group(1) == data.get('prompt', '')
assert count == 6
PY
git diff --check
```
