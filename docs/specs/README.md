# Feature Specs

This directory is the product behavior layer for HoldType Swift.

It captures expected user-visible behavior for complex features before or
alongside implementation.

Specs are lightweight and product-oriented. They define what the system must do,
not how it is implemented.

Verification artifacts are separate. They provide evidence but do not replace
the product contract.

## Project Context

HoldType Swift is a new Swift project for a small native macOS menu bar
dictation utility. The MVP records microphone input, sends audio to the OpenAI
transcription API, and inserts returned text into the active app.

The macOS product remains shipped behavior that must not regress. The current
iOS scope is the compact V1.1 product contract in
[`features/ios-v1-release.md`](features/ios-v1-release.md), implemented in the
order defined by `docs/ios-v1-development-plan.md`. Keyboard-originated
dictation is governed by
[`features/ios-keyboard-handoff-and-delivery.md`](features/ios-keyboard-handoff-and-delivery.md)
and executed through `docs/ios-keyboard-dictation-mvp-plan.md`. That narrow
handoff contract supersedes older clauses that forbid opening HoldType, require
a manually prepared keyboard session, or treat every extension recreation as
automatic-delivery failure. The former P0-P8 portability roadmap and detailed
accepted/failed History transaction specs are historical evidence, not active
implementation queues. Physical-device gates still control claims that cannot
be proven in the simulator.

Early specs were seeded from the repository description and
`docs/openwhispr_swiftui_codex_tz.md`. The current checkout now contains real
macOS implementation code, so use `docs/specs/brownfield-discovery.md` and
targeted source search to verify current ownership before edits.

## What Lives Here

- product goals for complex features
- scope and non-goals
- user-visible behavior
- invariants that must not regress
- important thresholds and state or data implications
- failure policy and edge cases
- unknowns requiring product confirmation
- optional links to representative verification coverage

## What Does Not Live Here

- agent workflow and operational rules
  - keep those in `AGENTS.md` and `BACKLOG_DEVELOPMENT.md`
- step-by-step test procedures
  - keep those in test files or QA artifacts
- styling system rules
  - keep those in styling docs when they exist
- Swift engineering rules
  - keep those in `SWIFT.md`
- deep implementation notes that are only useful at code level
  - keep those near the source

## How To Use This Directory

1. Read `docs/specs/index.md` to pick the smallest relevant feature spec.
2. Check whether the feature already has a spec.
3. If yes, update it before or alongside the code change.
4. If not, create a new spec using the template.
5. Keep the spec short and product-level.
6. Use existing behavior, tests, and documentation as evidence, but write the
   contract in clear product language.

Do not read every feature spec by default. Read only the index and the spec
that governs the current behavior.

## Scope Rule

Create or update a spec when a task:

- introduces a new feature
- changes observable behavior
- introduces or modifies route, state, persistence, permission, or data
  contracts
- affects multi-step user flows
- changes microphone capture, transcription, status, editing, or text handoff
- changes privacy, consent, microphone access, local storage, or remote-service
  use
- introduces behavior that could be misunderstood later

Skip new specs for:

- pure refactors
- formatting-only changes
- comments-only edits
- behavior-neutral internal cleanups

## Structure

```text
docs/specs/
  README.md
  index.md
  brownfield-discovery.md
  backlog.md
  templates/
    feature-spec.md
  features/
    <feature-name>.md
```

## Spec Philosophy

- Specs are contracts, not implementation notes.
- Specs should be short but precise.
- Specs should be updated together with behavior changes.
- Specs should reflect what users experience, not internal structure.

## Relationship With Other Layers

- `AGENTS.md` defines workflow and rules for agents.
- `BACKLOG_DEVELOPMENT.md` defines queue selection, claim, and checkpoint
  behavior.
- `SWIFT.md` defines Swift, SwiftUI, AppKit interop, and engineering rules.
- `docs/specs/` defines product behavior.
- `references/` stores imported reference material and audit notes.
- tests or QA artifacts define verification and evidence.

These layers must stay separate.

## Goal

Make product behavior explicit before code begins.
