# Local Development

## Purpose

This guide is for running and validating the repository locally from the workspace root.
It keeps the day-to-day developer workflow out of the main `README.md` while still making the repo easy to boot up.

## Working from the repository root

This VS Code workspace stays rooted at the repository top level.
The checked-in launch and task configs point into the nested projects for you.

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
