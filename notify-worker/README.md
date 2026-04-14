# Notify Worker

This project is the scheduled notification delivery runtime for the SaaS Reliability Lab.
It runs separately from the Flutter app, polls for pending reminders, sends browser push payloads, marks successful sends, and cleans up stale subscriptions when the push provider reports that an endpoint is gone.

## What lives here

- `src\index.ts`: worker entry point for both HTTP-triggered and cron-triggered runs
- `test\dispatch.spec.ts`: successful and empty-run dispatch behavior
- `test\cleanup.spec.ts`: stale-subscription cleanup behavior
- `wrangler.jsonc`: Cloudflare Worker config and cron schedule

## Local development

From the repository root:

- install dependencies: `Push-Location .\notify-worker; yarn install --frozen-lockfile; Pop-Location`
- start local worker dev mode: `Push-Location .\notify-worker; yarn dev; Pop-Location`
- run tests: `Push-Location .\notify-worker; yarn test; Pop-Location`
- regenerate Wrangler types after binding changes: `Push-Location .\notify-worker; yarn cf-typegen; Pop-Location`

From inside `notify-worker\`:

- `yarn install --frozen-lockfile`
- `yarn dev`
- `yarn test`
- `yarn cf-typegen`

## Runtime expectations

The worker expects these environment values in Cloudflare:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE`
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`

The current cron schedule in `wrangler.jsonc` is `*/5 * * * *`.

## Project-specific concerns

- this worker is operationally separate from the frontend and should stay deployable on its own
- it uses a Supabase RPC to fetch pending notifications, so schema changes can break delivery behavior
- stale push endpoints are treated as a cleanup signal rather than a retry-only failure
- production deploys run through GitHub Actions and Wrangler, not through the Flutter deployment path

## Related docs

- [`..\README.md`](../README.md)
- [`..\docs\DEPLOYMENT.md`](../docs/DEPLOYMENT.md)
- [`..\docs\LOCAL_DEVELOPMENT.md`](../docs/LOCAL_DEVELOPMENT.md)
- [`..\docs\TESTING_STRATEGY.md`](../docs/TESTING_STRATEGY.md)
