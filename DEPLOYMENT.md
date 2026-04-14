# Deployment and CI

## Purpose

This document describes the deployment contract that currently exists in the repository.
It focuses on the implemented GitHub Actions workflows, GitHub Pages integration, Cloudflare Worker deployment, and the environment values each runtime expects.

The goal is operational clarity.
This repository is a reliability lab, so deployment behavior needs to be explicit rather than hidden inside workflow files.

## Workflow inventory

### 1. Frontend deploy

Primary files:

- `.github/workflows/deploy.yaml`
- `.github/actions/build-and-deploy-action/action.yaml`

Trigger:

- every push to `master`

What it does:

- checks out the repository
- installs Flutter `3.41.5` on `stable`
- builds Flutter web in release mode
- uses `--pwa-strategy=offline-first`
- uses the GitHub Pages base href `/saas-reliability-lab/`
- injects client-facing runtime values through `--dart-define`
- merges `web/push-sw.js` into `build/web/flutter_service_worker.js`
- keeps the standalone `build/web/push-sw.js` asset for the dedicated push-worker scope
- force-pushes the contents of `build/web` to `gh-pages`

Operational expectations:

- GitHub Pages must publish from the `gh-pages` branch
- the deployed site root must remain `/saas-reliability-lab/`
- the release artifact must include both `flutter_service_worker.js` and `push-sw.js`

### 2. Scheduled notify worker deploy

Primary files:

- `.github/workflows/deploy-notify-worker.yaml`
- `@backend/agenda-notify-worker/wrangler.jsonc`

Trigger:

- push to `master` when files under `@backend/agenda-notify-worker/**` change
- push to `master` when `.github/workflows/deploy-notify-worker.yaml` changes
- manual `workflow_dispatch`

What it does:

- checks out the repository
- installs Node.js `20`
- enables Corepack
- installs the worker dependencies with Yarn
- deploys the worker through Wrangler

Operational expectations:

- the worker cron remains `*/5 * * * *`
- the worker deployment is independent from the frontend deployment
- frontend-only pushes do not redeploy the worker

## GitHub Pages integration

### Branch and publish model

- source branch: `master`
- deploy branch: `gh-pages`
- publish path: repository root on `gh-pages`
- public URL: `https://eliasfeijo.github.io/saas-reliability-lab/`

The frontend workflow does not use Pages artifacts or the dedicated `actions/deploy-pages` flow.
It builds the app and force-pushes the generated web output directly to `gh-pages`.

That means:

- `gh-pages` is treated as generated output only
- manual edits on `gh-pages` are expected to be overwritten
- the workflow is the source of truth for deploy behavior

### Base href contract

The app is built with:

- `--base-href /saas-reliability-lab/`

This is required because the app is served from a project subpath instead of the site root.

The following runtime paths depend on that base href being correct:

- `flutter_bootstrap.js`
- `flutter_service_worker.js`
- `push-sw.js`
- web icons and manifest paths

If the GitHub Pages repository name or publish path changes, the base href must change with it.

### Service worker model in production

The current production build intentionally publishes two service-worker-related assets:

- `flutter_service_worker.js`
- `push-sw.js`

They serve different purposes.

`flutter_service_worker.js`:

- is the Flutter web release service worker
- is built with `--pwa-strategy=offline-first`
- also receives the merged push handler content from `web/push-sw.js`

`push-sw.js`:

- is published as a standalone asset
- is registered by `web/push.js` under the dedicated scope `/saas-reliability-lab/push/`
- isolates browser push registration from the main Flutter app service worker lifecycle

This split matters because the lab now uses a dedicated push-worker scope for browser push subscriptions instead of relying on the root Flutter service worker registration.

## Required secrets

### Frontend workflow secrets

Used by `.github/workflows/deploy.yaml`:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `VAPID_PUBLIC_KEY`

These values are injected into the compiled Flutter web app through `--dart-define`.
They are client-visible by design and must not contain server-only secrets.

### Worker workflow secrets

Used by `.github/workflows/deploy-notify-worker.yaml` and the deployed worker environment:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

The worker itself also expects runtime secrets or environment variables for:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE`
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`

Those are configured in Cloudflare, not in the frontend deploy workflow.

## Environment matrix

| Environment | Frontend host | Frontend config source | Push worker path | Backend target | Worker runtime |
| --- | --- | --- | --- | --- | --- |
| Local Flutter web run | `http://localhost:<port>/` | `env.json` via `--dart-define-from-file` | `/push-sw.js` with local base href | Supabase project from `env.json` | remote Cloudflare worker unless separately run locally |
| GitHub Pages production | `https://eliasfeijo.github.io/saas-reliability-lab/` | GitHub Actions secrets via `--dart-define` | `/saas-reliability-lab/push-sw.js` under `/saas-reliability-lab/push/` scope | production Supabase project from GitHub secrets | deployed Cloudflare worker |
| Worker deploy pipeline | n/a | Wrangler and Cloudflare environment | n/a | production Supabase project | Cloudflare cron every 5 minutes |

## Failure modes worth knowing

### 1. Wrong base href

Symptoms:

- broken asset loads on GitHub Pages
- service worker registration against the wrong path
- 404s for `push-sw.js`, icons, or manifest resources

### 2. Wrong PWA strategy

Symptoms:

- release `flutter_service_worker.js` behaves like a self-unregistering no-op
- push registration can stall waiting for service worker activation

### 3. Missing standalone `push-sw.js`

Symptoms:

- browser push registration fails with `404` fetching `push-sw.js`
- dedicated push-worker scope never activates

### 4. Wrong GitHub Pages source branch

Symptoms:

- successful Actions run but no visible production update
- stale `gh-pages` output still served publicly

## Recommended operator checks after deploy changes

When changing deployment or push runtime behavior, verify all of the following against the public site:

1. `flutter_bootstrap.js` references the expected service worker version.
2. `flutter_service_worker.js` is an offline-first worker rather than a self-unregistering no-op.
3. `push-sw.js` is reachable at the GitHub Pages base href.
4. a signed-in browser profile can create and save a push subscription.
5. a due task still reaches the Cloudflare worker delivery path.

## Related files

- `README.md`
- `ARCHITECTURE.md`
- `.github/workflows/deploy.yaml`
- `.github/workflows/deploy-notify-worker.yaml`
- `.github/actions/build-and-deploy-action/action.yaml`
- `web/push.js`
- `web/push-sw.js`
- `@backend/agenda-notify-worker/wrangler.jsonc`