# AI workflow for local Copilot sessions

This repository is intended to work well with **local GitHub Copilot CLI** and **Copilot Chat in VS Code**.

## What local Copilot will actually load

When you work in this repository locally, Copilot can use:

- `AGENTS.md` at the repo root
- `.github/copilot-instructions.md`
- `.github/instructions/**/*.instructions.md`
- `.github/agents/*.agent.md`
- `.github/skills/*/SKILL.md`
- `.github/prompts/*.prompt.md` in VS Code chat

This repository does **not** currently check in a `copilot-setup-steps.yml` file.
That is intentional because the primary workflow here is local Copilot CLI and VS Code chat, not GitHub-hosted Copilot cloud agent.

## Workspace-root assumption

Local AI-assisted work in this repository assumes the **repository root is the active workspace root**.

- start Copilot CLI from the repo root
- open the repo root as the VS Code workspace
- reference files relative to the repo root in both CLI and VS Code chat
- prefer `@docs\...`, `@flutter-app\...`, `@notify-worker\...`, and similar repo-relative paths instead of prefixed workspace names

## Recommended local loop

Use this repository as a low-friction loop:

`plan -> implement -> verify -> update docs -> commit -> ci gate -> deploy`

### Suggested CLI and VS Code flow

1. Start in the repo root with `copilot`
2. Use **Shift+Tab** to enter plan mode when the task needs investigation before edits
3. Use `@path\to\file` to pull the most relevant docs or code into the prompt, always relative to the repository root
4. Use `/agent` to switch to a repo agent when you want a specialized planning, orchestration, implementation, verification, docs, or review pass
5. Use `/skills reload` once after new repo skills are added or changed in the current session
6. Use `/skills list` to see repo skills and invoke them when relevant
7. Use the repo skills as slash-invokable prompts:
   - `/repo-plan-task`
   - `/repo-task-loop`
   - `/repo-review-ready`
   - `/repo-verification`
   - `/docs-followthrough`
8. Use `/instructions` if you want to inspect which instruction files are active
9. Use `/resume` or `copilot --continue` to continue the same workflow with preserved context

### VS Code prompt files

VS Code supports **prompt files** in `.github/prompts/*.prompt.md`.
Copilot CLI does **not**.

Use prompt files in VS Code when you want reusable prompt templates for common tasks in this repo.
According to the official docs, prompt files are triggered manually by:

- referencing them directly in chat
- or using the prompt file picker

When using VS Code chat locally, assume the open workspace is the repository root.
That means prompt references and attached file context should use repo-relative paths such as `docs\ARCHITECTURE.md` or `flutter-app\lib\main.dart`.

This repo now includes:

- `repo-plan-task.prompt.md`
- `repo-task-loop.prompt.md`
- `repo-review-ready.prompt.md`
- `repo-commit-discipline.prompt.md`

## Default expectations

- Read the relevant docs before changing code or automation
- Keep code, docs, and workflow changes aligned
- Use the existing repo validation commands rather than inventing new tooling
- Treat `verify.yaml` as the repository trust workflow
- Prefer pull-request and CI-gated delivery over direct-push assumptions for `master`

## Core validation commands

- Flutter tests: `Push-Location .\flutter-app; flutter test; Pop-Location`
- worker tests: `Push-Location .\notify-worker; yarn test; Pop-Location`

## Prompt recipes

## Slash-invokable workflow prompts

Use these directly in Copilot CLI after running `/skills reload` if needed.
If your current CLI build does not accept the bare slash form, use the equivalent prompt form such as:

`Use the /repo-task-loop skill to fix the deployment docs and workflow behavior for the notify worker.`

### `/repo-plan-task`

Use when you want a **plan only**:

`/repo-plan-task Add a durable outbox model for sync replay and identify all docs, tests, and workflow changes needed.`

### `/repo-task-loop`

Use when you want the agent to **plan first, then decide whether to implement immediately or stop for review**:

`/repo-task-loop Fix the deployment docs and workflow behavior for the notify worker.`

Expected behavior:

- starts with a plan
- continues into implementation when the task is clear and bounded
- stops after planning and asks for review when the task is ambiguous or risky

### `/repo-review-ready`

Use when implementation is mostly done and you want a **merge-readiness pass**:

`/repo-review-ready Review the current diff for commit scope, docs alignment, CI gate expectations, and deploy implications.`

## VS Code prompt-file equivalents

Use these in VS Code chat via prompt files:

- `.github/prompts/repo-plan-task.prompt.md`
- `.github/prompts/repo-task-loop.prompt.md`
- `.github/prompts/repo-review-ready.prompt.md`
- `.github/prompts/repo-commit-discipline.prompt.md`

Use prompt files when you want reusable **manual prompt templates** in VS Code.
Use skills when you want the closest CLI equivalent.

### Plan

`Read @docs/ARCHITECTURE.md, @docs/LOCAL_DEVELOPMENT.md, and the relevant feature files, then produce a step-by-step implementation plan before making changes.`

### Implement

`Implement this as a complete vertical slice. Update any affected docs and keep the reliability-lab framing intact.`

### Verify

`Use the verifier agent and validate the existing repo commands relevant to the files changed. Summarize failures precisely.`

### Docs follow-through

`Update the relevant docs so they describe the implemented behavior honestly, not the planned behavior.`

### Commit and CI readiness

`Review the diff for commit readiness, suggest a Conventional Commit message, and identify what CI gate should pass before merge.`

## Hooks

Copilot CLI supports repository hooks under `.github/hooks/`, but this repository does **not** enable any by default yet.

That is intentional:

- hooks affect every local session
- bad hook design can add friction to the exact workflow we are trying to optimize
- any future hooks should be limited to lightweight guardrails or logging, not noisy automation
