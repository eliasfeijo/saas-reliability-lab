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
| `flutter-app\` | Flutter web app and platform projects |
| `notify-worker\` | Cloudflare Worker for scheduled notifications |
| `supabase\` | Supabase config, functions, migrations, and local backend tooling |
| `docs\` | Architecture, deployment, experiments, and project analysis |
| `.github\` | CI/CD workflows and shared GitHub Action logic |

## Where to start

- Want the big-picture product and architecture overview? Start with `docs\README.md`
- Want the deployment model? Read `docs\DEPLOYMENT.md`
- Want the current system assessment? Read `docs\project_analysis.md`
- Want to explore the app itself? Open `flutter-app\lib\main.dart`

## Working from the repository root

This VS Code workspace stays rooted at the repository top level.
The checked-in launch and task configs point into the nested projects for you.

### Flutter app

- VS Code: use the `Flutter` launch config
- CLI:
  - `Push-Location .\flutter-app; flutter pub get; Pop-Location`
  - `Push-Location .\flutter-app; flutter run --dart-define-from-file env.json -d chrome --web-port 3000; Pop-Location`
  - `Push-Location .\flutter-app; flutter test; Pop-Location`

### Notify worker

- `Push-Location .\notify-worker; yarn install --frozen-lockfile; Pop-Location`
- `Push-Location .\notify-worker; yarn test; Pop-Location`
- `Push-Location .\notify-worker; yarn deploy; Pop-Location`

### Supabase

- `Push-Location .\supabase; yarn install --frozen-lockfile; Pop-Location`
- `Push-Location .\supabase; npx supabase start; Pop-Location`
- `Push-Location .\supabase; npx supabase db reset; Pop-Location`

## Current status

The monorepo refactor is in place and local validation passes.
The deeper docs under `docs\` now match the monorepo layout as well.
