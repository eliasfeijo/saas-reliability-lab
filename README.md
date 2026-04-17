# SaaS Reliability Lab

**A small, inspectable SaaS built to show what happens when real-world product reliability gets messy.**

This project uses a simple task domain to make reliability behavior easy to see:

- a user creates work locally
- signs in later
- goes offline and comes back
- sync succeeds, stalls, or partially fails
- push reminders are scheduled and delivered separately from the app

The point is not "yet another todo app."
The point is to make the hidden operational problems of an early-stage SaaS visible in the product itself.

## Why this exists

Many startup products feel stable in happy-path demos, then get strange in production:

- local state and cloud state drift apart
- auth sessions expire at inconvenient times
- background jobs keep running even when the client is gone
- notifications fire late, twice, or not at all
- nobody can quickly explain what happened

This repository is a compact reliability lab for exploring those situations before they become expensive customer problems.

## Who this is for

### Founders and early-stage teams

If you are building a product with a small team, this repo is meant to be a practical reminder that reliability is not only about scale.
It is also about state, recovery, observability, and trust.

### Technical reviewers

If you found this from GitHub, a blog post, or a hiring review, the project is intentionally small enough to inspect end to end:

- Flutter web client
- Supabase backend surface
- scheduled notification worker
- visible runtime diagnostics in the UI

## What the product demonstrates today

- local-first task creation and editing
- anonymous-to-authenticated task adoption or discard
- per-user sync with Supabase
- runtime diagnostics for auth, sync, connectivity, push, and local task state
- browser push subscription management
- scheduled reminder dispatch through a Cloudflare Worker

## Why the task domain is intentionally small

The app uses tasks because they are familiar.
That keeps the user's mental model simple, so the interesting part becomes the system behavior:

- what breaks
- what recovers
- what stays visible
- what remains ambiguous

## Repository layout

This repo now uses a monorepo-style structure:

| Path | Purpose |
| --- | --- |
| [`flutter-app\`](flutter-app/README.md) | Flutter web app and platform projects |
| [`notify-worker\`](notify-worker/README.md) | Cloudflare Worker for scheduled notifications |
| [`supabase\`](supabase/README.md) | Supabase config, functions, migrations, and local backend tooling |
| [`docs\`](docs/README.md) | Architecture, local development, deployment, experiments, and project analysis |
| [`.github\`](.github) | GitHub Actions, instructions, agents, skills, and prompt scaffolding; see [`docs/GITHUB_AUTOMATION.md`](docs/GITHUB_AUTOMATION.md) for the overview |

## Documentation Summary

| Document | What it covers |
| --- | --- |
| [`docs/README.md`](docs/README.md) | Big-picture product framing, current UI shape, system model, and the repository guide. |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Implemented topology, state ownership, and the current evolution path. |
| [`docs/OBJECTIVE_0_FOUNDATION_PLAN.md`](docs/OBJECTIVE_0_FOUNDATION_PLAN.md) | Completed Objective 0 execution record and handoff for the finished foundation cleanup. |
| [`docs/OBJECTIVE_1_OUTBOX_ENTRY_PLAN.md`](docs/OBJECTIVE_1_OUTBOX_ENTRY_PLAN.md) | Active Objective 1 entry plan for the next outbox-focused phase. |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | GitHub Actions workflows, GitHub Pages, Cloudflare Worker deployment, and environment expectations. |
| [`docs/GITHUB_AUTOMATION.md`](docs/GITHUB_AUTOMATION.md) | Repository automation structure, workflow surfaces under `.github\`, and local guidance for automation changes. |
| [`docs/LOCAL_DEVELOPMENT.md`](docs/LOCAL_DEVELOPMENT.md) | Repository-root workflow, local run commands, and the day-to-day setup for working on the app locally. |
| [`docs/AI_ASSISTED_DEVELOPMENT.md`](docs/AI_ASSISTED_DEVELOPMENT.md) | The intended human-and-agent development loop, Copilot workflow, and low-friction delivery model for this repo. |
| [`docs/TESTING_STRATEGY.md`](docs/TESTING_STRATEGY.md) | Repo-wide testing contract, current test inventory, and the planned structure for reliability-focused automation. |
| [`docs/EXPERIMENTS.md`](docs/EXPERIMENTS.md) | Runnable and planned reliability scenarios, expected behavior, and visible evidence. |
| [`ROADMAP.md`](ROADMAP.md) | Recommended short-, medium-, and long-term implementation direction grounded in the current repository state. |
| [`docs/project_analysis.md`](docs/project_analysis.md) | Current system assessment, structural strengths, and the main gaps still left to close. |
| [`docs/TASK_DELETION_LIFECYCLE.md`](docs/TASK_DELETION_LIFECYCLE.md) | Current deletion semantics, the anonymous-task bug rationale, and the recommended future archive path. |
| [`docs/reliability_lab_checklist.md`](docs/reliability_lab_checklist.md) | Milestones for turning the current prototype into a stronger reliability lab. |

To jump straight into the client, start with [`flutter-app/lib/main.dart`](flutter-app/lib/main.dart).

The main subproject directories also have their own `README.md` files with local workflow notes and project-specific guidance.

## Current status

The monorepo refactor is in place and local validation passes.
The deeper docs under `docs\` now match the monorepo layout as well.
