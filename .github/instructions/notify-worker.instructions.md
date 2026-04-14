---
applyTo: "notify-worker/**/*.ts,notify-worker/package.json,notify-worker/wrangler.jsonc"
---

Treat `notify-worker\` as an independently deployable scheduled delivery surface.

- Preserve its operational independence from the frontend deploy path unless the task explicitly changes that contract.
- Keep notification dispatch, stale-subscription cleanup, and Supabase integration behavior explicit.
- Do not assume frontend-only changes should affect worker deployment behavior.
- If runtime or deploy behavior changes, update the relevant docs in `docs\DEPLOYMENT.md`, `docs\TESTING_STRATEGY.md`, or `notify-worker\README.md`.
- Validate with the existing worker test command unless the task is documentation-only.
