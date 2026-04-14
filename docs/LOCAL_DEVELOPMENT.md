# Local Development

## Purpose

This guide is for running and validating the repository locally from the workspace root.
It keeps the day-to-day developer workflow out of the main `README.md` while still making the repo easy to boot up.

## Working from the repository root

This VS Code workspace stays rooted at the repository top level.
The checked-in launch and task configs point into the nested projects for you.

For folder-specific setup and caveats, each immediate top-level project directory now has its own README:

- [`..\flutter-app\README.md`](../flutter-app/README.md)
- [`..\notify-worker\README.md`](../notify-worker/README.md)
- [`..\supabase\README.md`](../supabase/README.md)
- [`..\.github\README.md`](../.github/README.md)

## Local prerequisites

- Flutter SDK for the web app workflow
- Node.js with Yarn or Corepack for `notify-worker\` and `supabase\`
- Supabase CLI for local backend commands
- A `flutter-app\env.json` file for local Flutter web runs

## Flutter app

- VS Code: use the `Flutter` launch config
- CLI:
  - `Push-Location .\flutter-app; flutter pub get; Pop-Location`
  - `Push-Location .\flutter-app; flutter run --dart-define-from-file env.json -d chrome --web-port 3000; Pop-Location`
  - `Push-Location .\flutter-app; flutter test; Pop-Location`
  - `Push-Location .\flutter-app; flutter test test\task_workspace_responsive_test.dart; Pop-Location`

### Responsive UI verification

Current responsive widget coverage lives in `flutter-app\test\task_workspace_responsive_test.dart`.

Use that targeted command when working on:

- shell breakpoints
- workspace split vs compact behavior
- dense-height behavior
- attached details and batch-panel behavior

See `LAB_SHELL_RESPONSIVE_SPEC.md` for the shell-wide responsive contract and the required resize-in-place automation strategy.

### Repository testing strategy

See `TESTING_STRATEGY.md` for:

- the current suite inventory
- the intended test taxonomy for this reliability lab
- the planned refactor direction for Flutter and worker suites
- the direction for a dedicated CI verification workflow

## Notify worker

- `Push-Location .\notify-worker; yarn install --frozen-lockfile; Pop-Location`
- `Push-Location .\notify-worker; yarn test; Pop-Location`
- `Push-Location .\notify-worker; yarn deploy; Pop-Location`

## Supabase

- `Push-Location .\supabase; yarn install --frozen-lockfile; Pop-Location`
- `Push-Location .\supabase; npx supabase start; Pop-Location`
- `Push-Location .\supabase; npx supabase db reset; Pop-Location`

## Related docs

- [`DEPLOYMENT.md`](DEPLOYMENT.md) for the deployed environment model and CI/CD contract
- [`ARCHITECTURE.md`](ARCHITECTURE.md) for system ownership and runtime topology
- [`TESTING_STRATEGY.md`](TESTING_STRATEGY.md) for the repository-wide testing contract
