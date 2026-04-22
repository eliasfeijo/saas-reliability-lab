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
- explicit local outbox replay with visible queued, blocked, failed, conflict, and acknowledgement evidence
- first-slice conflict resolution by keeping remote state or re-queuing the local intent
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

| Path                                        | Purpose                                                                                                  |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| [`flutter-app\`](flutter-app/README.md)     | Flutter web app and platform projects                                                                    |
| [`notify-worker\`](notify-worker/README.md) | Cloudflare Worker for scheduled notifications                                                            |
| [`supabase\`](supabase/README.md)           | Supabase config, functions, migrations, and local backend tooling                                        |
| [`docs\`](docs/README.md)                   | Audience-facing architecture, deployment, testing, roadmap, and guide material, plus the full docs index |
| [`.github\`](.github)                       | GitHub Actions, instructions, agents, skills, and prompt scaffolding                                     |

## Documentation Summary

This list stays intentionally narrow.
It highlights the docs most useful to founders, CTOs, and engineers evaluating the repository from GitHub.
The full internal docs tree, including phase plans, future ideas, and historical records, lives in [`docs/README.md`](docs/README.md).

| Document                                                                           | What it covers                                                                                                    |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| [`docs/README.md`](docs/README.md)                                                 | The main docs index for deeper reading across reference docs and guides.                                          |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)                                     | Implemented topology, state ownership, and the current evolution path.                                            |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)                                         | GitHub Actions workflows, GitHub Pages, Cloudflare Worker deployment, and environment expectations.               |
| [`docs/TESTING_STRATEGY.md`](docs/TESTING_STRATEGY.md)                             | Repo-wide testing contract, current test inventory, and the planned structure for reliability-focused automation. |
| [`docs/guides/STATE_MODELS.md`](docs/guides/STATE_MODELS.md)                       | Dedicated outbox, sync-run, and auth/session state-machine reference plus the current documented gaps.            |
| [`ROADMAP.md`](ROADMAP.md)                                                         | Recommended short-, medium-, and long-term implementation direction grounded in the current repository state.     |
| [`docs/guides/FAULT_INJECTION.md`](docs/guides/FAULT_INJECTION.md)                 | Implemented and planned fault-injection behavior, including delayed-sync guidance.                                |
| [`docs/guides/RESPONSIVE_DESIGN.md`](docs/guides/RESPONSIVE_DESIGN.md)             | Consolidated shell and task-workspace responsive contract.                                                        |
| [`docs/guides/EXPERIMENTS.md`](docs/guides/EXPERIMENTS.md)                         | Runnable and planned reliability scenarios, expected behavior, and visible evidence.                              |
| [`docs/guides/TASK_DELETION_LIFECYCLE.md`](docs/guides/TASK_DELETION_LIFECYCLE.md) | Current deletion semantics, the anonymous-task bug rationale, and the recommended future archive path.            |

To jump straight into the client, start with [`flutter-app/lib/main.dart`](flutter-app/lib/main.dart).

The main subproject directories also have their own `README.md` files with local workflow notes and project-specific guidance.

## Current status

The repository now presents the reliability-lab shape directly from the root README.
The deeper documentation under `docs\` is organized by purpose, with the audience-facing reference and guide material surfaced first and the internal phase, future, and archive docs kept behind the main docs index.
