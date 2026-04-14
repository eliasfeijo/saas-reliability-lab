# AI-Assisted Development Workflow

## Purpose

This document defines the intended long-term human-and-agent workflow for the SaaS Reliability Lab.

It should be treated as a permanent operating model for the repository, not as a temporary experiment.
The goal is to keep the engineering loop fast, explicit, and low-friction while still preserving trust in the codebase.

## Operating model

The repository should be worked as a **human-directed, agent-executed loop**:

- humans set product direction, scope, priorities, and approval boundaries
- AI agents perform the investigation, implementation, verification, documentation follow-through, and routine repository operations
- the loop should continue end to end whenever possible instead of stopping after the first code change

The target is minimal manual glue between phases:

`plan -> implement -> verify -> update docs -> commit -> ci gate -> deploy`

## Default lifecycle loop

### 1. Plan

Every meaningful task should begin with enough repository context to avoid blind edits.

In practice that means:

- read the relevant docs before changing code or automation
- identify which surfaces are affected: `flutter-app\`, `notify-worker\`, `supabase\`, `docs\`, or `.github\`
- make the implemented state, desired state, and constraints explicit
- ask for human clarification only when the choice materially affects product behavior or architecture

For multi-step or multi-file work, the active plan should be tracked in the agent session so the task can survive handoffs cleanly.

### 2. Implement

Implementation should favor one coherent vertical slice over fragmented edits.

That means:

- carry the change through all affected surfaces
- keep frontend, worker, backend, docs, and automation aligned
- prefer finishing the full loop for the requested task instead of handing back a partial patch
- preserve the current reliability-lab framing rather than treating the repository as a generic CRUD app

### 3. Verify

Repository trust should come from executable verification, not only from code inspection.

Current repo-level verification commands:

- Flutter tests: `Push-Location .\flutter-app; flutter test; Pop-Location`
- worker tests: `Push-Location .\notify-worker; yarn test; Pop-Location`

When work is narrower, targeted verification is still acceptable, but the default standard is to leave the repository in a state that the existing verification workflow can trust.

### 4. Update docs

Documentation is part of the delivery, not a later cleanup pass.

If a change affects behavior, ownership, workflow, deployment, testing, or operator expectations, update the relevant docs in the same change.

Common documentation touchpoints:

- `docs\ARCHITECTURE.md` for implemented ownership and topology
- `docs\DEPLOYMENT.md` for CI/CD, workflow, and environment behavior
- `docs\LOCAL_DEVELOPMENT.md` for developer commands and day-to-day execution
- `docs\TESTING_STRATEGY.md` for verification contract and test inventory
- `docs\GITHUB_AUTOMATION.md` for repository automation structure

### 5. Commit

Commits should represent one coherent change and should be easy for both humans and agents to reason about later.

Repository expectation:

- use Conventional Commit style messages
- keep commit scope aligned with the delivered capability or doc/config change
- keep commits atomic by default: one coherent unit of work per commit
- do not batch unrelated work into one commit just because it is available locally
- in this monorepo, prefer a repo-area scope when it improves clarity, such as `flutter-app`, `notify-worker`, `docs`, or `github`
- do not split one logical workflow change into confusing partial commits unless there is a strong review reason

### 6. CI gate

The intended trust model is:

- changes land through pull requests
- repository verification is the gate for merge trust
- direct pushes to `master` should be avoided

Today the deploy workflows can still race verification after merge.
That is documented in `docs\DEPLOYMENT.md` as the current transitional state, not the ideal long-term model.

### 7. Deploy

Current deploy behavior:

- frontend deploy triggers from pushes to `master`
- worker deploy triggers independently when worker-related paths change on `master`
- verification is a separate workflow

Recommended direction:

- short term: protect `master` so bad changes are stopped before merge
- medium term: gate deploy on successful verification of the same commit
- long term: move to explicit environment promotion

## Human and agent responsibilities

| Concern | Human responsibility | Agent responsibility |
| --- | --- | --- |
| Product direction | choose goals, scope, tradeoffs, and acceptance boundaries | translate goals into concrete changes and surface meaningful risks |
| Architecture decisions | approve major model or lifecycle shifts | investigate current constraints, propose repo-aligned implementations, and apply approved direction |
| Implementation | approve or redirect when needed | perform end-to-end code, docs, and automation changes |
| Verification | define required confidence level | run the relevant existing commands and leave the repo in a verifiable state |
| Documentation | decide audience and emphasis when needed | keep docs aligned with the implemented behavior in the same change |
| Secrets and environment governance | manage secrets, environment settings, branch protection, and deployment approvals | never hardcode secrets and document required environment configuration clearly |

## Repo-specific execution map

| Area | Read first | Typical validation | Notes |
| --- | --- | --- | --- |
| `flutter-app\` | `docs\ARCHITECTURE.md`, `docs\TESTING_STRATEGY.md`, `flutter-app\README.md` | `Push-Location .\flutter-app; flutter test; Pop-Location` | treat the app as a reliability-lab shell, not as a generic todo UI |
| `notify-worker\` | `docs\DEPLOYMENT.md`, `docs\TESTING_STRATEGY.md`, `notify-worker\README.md` | `Push-Location .\notify-worker; yarn test; Pop-Location` | preserve worker independence from frontend deploys |
| `supabase\` | `docs\ARCHITECTURE.md`, `docs\DEPLOYMENT.md`, `supabase\README.md` | validate only with existing repo tooling | backend changes must stay aligned with worker and sync behavior |
| `.github\` | `docs\GITHUB_AUTOMATION.md`, `docs\DEPLOYMENT.md`, this document | run the repo commands affected by the automation change | workflow behavior must stay explicit in docs |
| `docs\` | `docs\README.md` and the behavior-specific doc being changed | documentation review plus any behavior validation tied to the change | docs should describe implemented behavior honestly |

## Minimal-friction rules

The AI-assisted loop should optimize for continuity:

- do not stop after implementation if verification and docs are still clearly required
- do not update workflow behavior without updating the docs that explain it
- do not describe planned behavior as implemented behavior
- do not leave human operators to manually bridge obvious gaps between phases
- do keep the repository easy for the next agent session to resume without rediscovering everything

## Local Copilot CLI and VS Code workflow

For day-to-day work in this repository, the primary AI-assisted DX surface is **local Copilot CLI** and **Copilot Chat in VS Code**.

The local workflow assumes the **repository root is the active workspace root** in both tools.
Start Copilot CLI from the repo root and open the repo root as the VS Code workspace so instructions, agents, skills, prompt files, and repo-relative file references all resolve the same way.

These local sessions can use the following checked-in repository scaffolding:

- `AGENTS.md`
- `.github\copilot-instructions.md`
- `.github\instructions\**\*.instructions.md`
- `.github\agents\*.agent.md`
- `.github\skills\*\SKILL.md`
- `.github\prompts\*.prompt.md` in VS Code chat

Practical local commands and controls:

- start a session with `copilot`
- use **Shift+Tab** for plan mode
- use `/agent` to select a repo custom agent
- use `/skills list` and `/skills reload` for repo skills
- use `/instructions` to inspect active instruction files
- use `/resume` or `copilot --continue` to continue the same workflow with preserved context
- use `@relative\path` to bring files directly into prompt context from the repository root

### How to enable and use the repo agents and prompts in this local CLI

1. Start `copilot` from the repository root.
2. Trust the folder when Copilot asks.
3. Run `/instructions` if you want to confirm the repo instructions are active.
4. Run `/agent` to verify the repo agents are visible:
   - `workflow-lead`
   - `planner`
   - `implementer`
   - `verifier`
   - `docs-writer`
   - `reviewer`
5. Run `/skills reload` in the current session if you recently pulled or edited the skill files.
6. Run `/skills list` to confirm the repo skills are available:
   - `repo-plan-task`
   - `repo-task-loop`
   - `repo-review-ready`
   - `repo-commit-discipline`
   - `repo-verification`
   - `docs-followthrough`

If agents do not appear in the current session, start a new session from the repo root.
Skills can be reloaded in-session with `/skills reload`.
If your current CLI build does not accept the bare slash form for a skill, use the explicit prompt form instead, for example:

`Use the /repo-task-loop skill to fix the deployment docs and workflow behavior for the notify worker.`

In local VS Code chat, keep the same repo-root assumption.
Attach or reference files with repo-relative paths such as `docs\LOCAL_DEVELOPMENT.md`, `flutter-app\lib\main.dart`, or `docs\GITHUB_AUTOMATION.md`.

### Suggested phase-to-tool mapping

| Phase | Best local Copilot surface |
| --- | --- |
| Plan | plan mode, `planner` agent, `/repo-plan-task`, `@docs\...` context |
| Orchestrate | `workflow-lead` agent or `/repo-task-loop` |
| Implement | main agent or `implementer` agent |
| Verify | `repo-verification` skill and `verifier` agent |
| Update docs | `docs-followthrough` skill and `docs-writer` agent |
| Review / Commit | `reviewer` agent or `/repo-review-ready` plus repo instructions |
| CI gate | main agent plus `docs\DEPLOYMENT.md` and `.github\workflows\verify.yaml` |
| Deploy | main agent plus `docs\DEPLOYMENT.md` and workflow files |

### Recommended custom prompt workflow

For this repository, the most useful short-term workflow is:

1. `/repo-plan-task <task>` when you want a planning-only pass
2. `/repo-task-loop <task>` when you want the agent to plan first and then decide whether to implement immediately or stop for review
3. `/repo-review-ready` when the change is mostly done and you want a merge-readiness pass
4. `/repo-commit-discipline` when the work is ready but the diff still needs to be split into clean commit units

That gives you a practical local workflow without introducing hooks or heavy automation too early.

### Prompt recipes for the lifecycle loop

Slash-invokable repo prompts:

- `/repo-plan-task Add a visible outbox state to the diagnostics rail and identify the code, docs, and tests that would need to change.`
- `/repo-task-loop Refine the GitHub Actions verification and deployment docs to match the current workflow behavior.`
- `/repo-review-ready Review the current diff for commit scope, Conventional Commit wording, CI gate expectations, and deploy implications.`
- `/repo-commit-discipline Review the current diff, split unrelated work apart, and suggest Conventional Commit messages for each commitable unit.`

Equivalent explicit prompt form:

- `Use the /repo-task-loop skill to refine the GitHub Actions verification and deployment docs to match the current workflow behavior.`

Plan:

- `Read @docs/ARCHITECTURE.md, @docs/LOCAL_DEVELOPMENT.md, and the relevant files, then produce an implementation plan before coding.`

Implement:

- `Use the implementer agent and carry this through code, docs, and workflow follow-through as one coherent change.`

Verify:

- `Use the /repo-verification skill and validate the existing repo commands relevant to the changed files.`

Docs:

- `Use the /docs-followthrough skill and update the docs that now need to match the implemented behavior.`

Commit readiness:

- `Review the diff for commit readiness, suggest a Conventional Commit message, and tell me what CI gate should pass before merge.`

Commit discipline:

- `Use the /repo-commit-discipline skill to split the current work into clean commit units and suggest repo-scoped Conventional Commit messages where helpful.`

## Copilot and agent scaffolding in this repo

The repository should keep its AI-specific operating surface explicit:

- `AGENTS.md`: root local workflow guidance for Copilot CLI and VS Code chat
- `.github\copilot-instructions.md`: repository instructions for Copilot and other agents
- `.github\instructions\`: path-specific local instructions
- `.github\agents\`: custom agents for orchestration, plan, implement, verify, docs, and review phases
- `.github\skills\`: reusable task-specific skills and slash-invokable workflow prompts
- `.github\prompts\`: VS Code prompt files for reusable IDE prompt templates
- `docs\AI_ASSISTED_DEVELOPMENT.md`: the human-readable workflow contract for AI-assisted engineering

## Optional cloud-agent setup

This repository does **not** currently ship a `copilot-setup-steps.yml` file.

Reason:

- the primary AI-assisted DX for this project is local Copilot CLI and Copilot Chat in VS Code
- there is no active requirement today for GitHub-hosted Copilot cloud-agent runs
- a checked-in cloud-agent setup file would add maintenance surface without improving the local workflow

If hosted Copilot cloud-agent usage becomes part of the real workflow later, a setup file can be added at that point.
Its role would be limited to hosted environment bootstrap such as toolchain preinstalls, runner selection, services, caches, or other setup needs.
It would still be separate from repository verification and would not replace `verify.yaml`.

## Hooks and guardrails

Copilot CLI also supports repository hooks under `.github\hooks\`.

This repository does **not** enable any hooks by default yet.
That is intentional:

- hooks affect every local session
- poorly designed hooks would add friction to the workflow
- the first hooks, if added later, should be lightweight guardrails or logging hooks rather than aggressive blockers

## Growth path

As the repository grows, this local AI surface can expand with:

- more granular instruction files if different subsystems need distinct guidance
- additional custom agents for narrower specialties
- more repo skills for repeatable workflows
- carefully scoped hooks for observability or guardrails
- reusable workflow orchestration once CI/CD becomes more environment-driven
- cloud-agent environment setup if hosted Copilot usage becomes a real project need
