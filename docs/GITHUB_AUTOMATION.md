# GitHub Automation

This document describes the repository automation contract implemented under `.github\` for the SaaS Reliability Lab.
It is where deploy and verification behavior becomes concrete through GitHub Actions workflows and the shared composite action used to publish the Flutter web build.

## What lives under `.github\`

- `workflows\deploy.yaml`: builds and publishes the Flutter web app to GitHub Pages
- `workflows\deploy-notify-worker.yaml`: deploys the Cloudflare notification worker
- `workflows\verify.yaml`: runs repository verification without deploying
- `instructions\`: path-specific instructions used by local Copilot CLI and VS Code chat
- `agents\`: repository custom agents for workflow orchestration, planning, implementation, verification, docs, and review work
- `skills\`: reusable Copilot skills for repeatable repo workflows and slash-invokable prompt patterns
- `prompts\`: VS Code prompt files for reusable IDE prompt templates
- `actions\build-and-deploy-action\action.yaml`: shared composite action for the frontend deploy flow
- `copilot-instructions.md`: repository-specific guidance for Copilot and other agents working in this repo

## How to work with this surface locally

There is no separate runtime to boot from `.github\`.
When you change automation here, validate the underlying projects directly:

- frontend behavior: use the commands in [`..\flutter-app\README.md`](../flutter-app/README.md)
- worker behavior: use the commands in [`..\notify-worker\README.md`](../notify-worker/README.md)
- repository workflow expectations: use [`DEPLOYMENT.md`](DEPLOYMENT.md), [`LOCAL_DEVELOPMENT.md`](LOCAL_DEVELOPMENT.md), and [`AI_ASSISTED_DEVELOPMENT.md`](AI_ASSISTED_DEVELOPMENT.md)

For local Copilot CLI and VS Code chat, assume the repository root is the active workspace root.
That keeps `.github\` instructions, agents, skills, and prompt files addressable through the same repo-relative paths used everywhere else in this monorepo.

## Project-specific concerns

- GitHub Pages deploys from `master` to `gh-pages`
- the public frontend base href must remain `/saas-reliability-lab/` unless the Pages path changes
- worker deployment is intentionally independent from frontend deployment
- verification is the place for repository trust; deploy workflows should not be the only automated safety net
- AI-assisted development is an explicit repository workflow, not an ad hoc convenience layer
- the main local Copilot DX surface is instructions, agents, skills, and VS Code prompt files checked into the repo
- the repo does not currently define a Copilot cloud-agent setup workflow because hosted Copilot is not part of the active development path
- commit discipline is part of the local AI workflow: prefer atomic Conventional Commits and do not mix unrelated repo areas in one commit without a strong reason

## Read this with

- [`..\README.md`](../README.md)
- [`AI_ASSISTED_DEVELOPMENT.md`](AI_ASSISTED_DEVELOPMENT.md)
- [`DEPLOYMENT.md`](DEPLOYMENT.md)
- [`TESTING_STRATEGY.md`](TESTING_STRATEGY.md)
