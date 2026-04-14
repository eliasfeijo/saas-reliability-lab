# Copilot instructions for SaaS Reliability Lab

## Project framing

- Treat this repository as a **reliability lab with a task domain**, not as a generic todo application.
- Prefer implemented behavior over aspiration. If something is only planned, describe it as planned.
- Keep changes aligned with the current system model: Flutter web client, Supabase backend surface, and an independently deployable Cloudflare notify worker.

## Default workflow

- Work through the full loop whenever feasible: **plan -> implement -> verify -> update docs -> commit -> CI gate -> deploy readiness**.
- For multi-file or multi-phase work, keep a clear task plan so another agent can continue without rediscovery.
- Read the relevant docs before changing behavior or automation.
- Ask for clarification only when the choice materially affects product behavior, architecture, or release risk.

## Verification expectations

- Use the existing repository validation commands rather than inventing new tooling.
- Repo-root verification commands:
  - `Push-Location .\flutter-app; flutter test; Pop-Location`
  - `Push-Location .\notify-worker; yarn test; Pop-Location`
- If a change affects GitHub Actions, deployment, or repository workflow, keep the docs aligned with the implemented workflow behavior.

## Documentation expectations

- Documentation changes are part of the deliverable when behavior, workflow, testing, or deployment changes.
- Update the relevant docs in the same change:
  - `docs\ARCHITECTURE.md`
  - `docs\DEPLOYMENT.md`
  - `docs\LOCAL_DEVELOPMENT.md`
  - `docs\TESTING_STRATEGY.md`
  - `.github\README.md`
- Keep the root and `docs\README.md` indexes discoverable when new long-form docs are added.

## CI/CD expectations

- Treat `verify.yaml` as the repository trust workflow.
- Preserve the intentional independence of the frontend and worker deploy surfaces unless the task explicitly changes that contract.
- Avoid direct-push assumptions for `master`; prefer a PR + CI-gated workflow model in recommendations and docs.

## Change discipline

- Keep changes surgical but complete.
- Reuse existing patterns and commands already documented in the repo.
- Do not claim a workflow or architecture is in place unless the repository actually contains the supporting files and wiring.
- Use Conventional Commit style when creating commit messages.

## Environment notes

- The checked-in developer docs use Windows-style repo-root commands for local human workflow.
- Local Copilot CLI and VS Code chat sessions should assume the repository root is the active workspace root and should reference files with repo-relative paths.
- The GitHub Actions verification and deploy workflows currently run on Ubuntu.
- If the repository ever adds a Copilot cloud-agent setup file later, prefer matching the existing CI toolchain unless there is a strong repository-specific reason to diverge.
