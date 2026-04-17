# Supabase Backend Surface

This folder holds the backend contract for the SaaS Reliability Lab.
It contains the local Supabase project, schema evolution history, and edge functions that support browser push subscription management and notification-related behavior.

## What lives here

- `config.toml`: local Supabase project configuration
- `migrations\`: schema history and RPC definitions used by the app and worker
- `functions\save_subscription\`: saves or updates browser push subscriptions for the signed-in user
- `functions\delete_subscription\`: removes a saved browser push subscription
- `functions\send-push-notifications\`: edge-function notification dispatch path
- `api.http`: lightweight request snippets for manual auth and REST checks

## Local development

From the repository root:

- install supporting packages: `Push-Location .\supabase; yarn install --frozen-lockfile; Pop-Location`
- start the local Supabase stack: `Push-Location .\supabase; npx supabase start; Pop-Location`
- reset the local database from migrations: `Push-Location .\supabase; npx supabase db reset; Pop-Location`

From inside `supabase\`:

- `yarn install --frozen-lockfile`
- `npx supabase start`
- `npx supabase db reset`

## Local prerequisites

- Supabase CLI
- Docker Desktop or another compatible local container runtime for `supabase start`
- Node.js with Yarn or Corepack for the package-managed tooling in this folder

## Project-specific concerns

- the local auth site URL is configured for `http://127.0.0.1:3000`, which should stay aligned with local Flutter web runs
- this folder defines database behavior relied on by both `flutter-app\` and `notify-worker\`
- the worker depends on RPC-backed pending-notification queries, so migration changes should be reviewed with delivery behavior in mind
- edge functions here are part of the backend surface, but the scheduled production notification path currently runs from the Cloudflare worker project

## Current contract boundaries

Implemented now:

- the Flutter app still syncs task mutations by talking directly to the `tasks` table through the Supabase client
- browser push subscription save and delete flows go through the `save_subscription` and `delete_subscription` Edge Functions
- the Cloudflare worker fetches due reminders through the `get_pending_notifications` RPC and then updates `tasks.notification_sent`

What this means right now:

- the repository does not yet have one backend-owned mutation gateway for all task sync behavior
- task sync and push-subscription management already use different backend paths on purpose
- schema changes to `tasks`, `push_subscriptions`, or the pending-notification RPC can affect the frontend and worker differently

Still transitional:

- the long-term task sync surface is still open between direct table access, RPC, Edge Function, or another backend boundary
- audit-oriented history for sync and delivery outcomes is not implemented yet

## Related docs

- [`..\README.md`](../README.md)
- [`..\docs\ARCHITECTURE.md`](../docs/ARCHITECTURE.md)
- [`..\docs\DEPLOYMENT.md`](../docs/DEPLOYMENT.md)
- [`..\docs\LOCAL_DEVELOPMENT.md`](../docs/LOCAL_DEVELOPMENT.md)
