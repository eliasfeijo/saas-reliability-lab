# GitHub Automation

This folder holds the repository automation contract for the SaaS Reliability Lab.
It is where deploy and verification behavior becomes concrete through GitHub Actions workflows and the shared composite action used to publish the Flutter web build.

## What lives here

- `workflows\deploy.yaml`: builds and publishes the Flutter web app to GitHub Pages
- `workflows\deploy-notify-worker.yaml`: deploys the Cloudflare notification worker
- `workflows\verify.yaml`: runs repository verification without deploying
- `actions\build-and-deploy-action\action.yaml`: shared composite action for the frontend deploy flow

## How to work with this folder locally

There is no separate runtime to boot from `.github\`.
When you change automation here, validate the underlying projects directly:

- frontend behavior: use the commands in [`..\flutter-app\README.md`](../flutter-app/README.md)
- worker behavior: use the commands in [`..\notify-worker\README.md`](../notify-worker/README.md)
- repository workflow expectations: use [`..\docs\DEPLOYMENT.md`](../docs/DEPLOYMENT.md) and [`..\docs\LOCAL_DEVELOPMENT.md`](../docs/LOCAL_DEVELOPMENT.md)

## Project-specific concerns

- GitHub Pages deploys from `master` to `gh-pages`
- the public frontend base href must remain `/saas-reliability-lab/` unless the Pages path changes
- worker deployment is intentionally independent from frontend deployment
- verification is the place for repository trust; deploy workflows should not be the only automated safety net

## Read this with

- [`..\README.md`](../README.md)
- [`..\docs\DEPLOYMENT.md`](../docs/DEPLOYMENT.md)
- [`..\docs\TESTING_STRATEGY.md`](../docs/TESTING_STRATEGY.md)
