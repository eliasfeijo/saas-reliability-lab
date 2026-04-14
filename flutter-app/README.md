# Flutter App

This is the web-first client for the SaaS Reliability Lab.
It is the part of the repository where local-first task state, auth transitions, sync behavior, push registration, and runtime diagnostics become visible in the UI.

## What lives here

- `lib\main.dart`: app entry point and provider wiring
- `lib\screens\lab_shell.dart`: the current lab-style shell
- `test\`: Flutter test coverage for sync logic, provider behavior, and responsive workspace behavior
- `web\`: browser assets, manifest, and push-service-worker files
- `env.example.json`: template for local runtime values

## Local development

From the repository root:

- install Flutter packages: `Push-Location .\flutter-app; flutter pub get; Pop-Location`
- run the web app locally: `Push-Location .\flutter-app; flutter run --dart-define-from-file env.json -d chrome --web-port 3000; Pop-Location`
- run all Flutter tests: `Push-Location .\flutter-app; flutter test; Pop-Location`
- run the responsive suite only: `Push-Location .\flutter-app; flutter test test\task_workspace_responsive_test.dart; Pop-Location`

From inside `flutter-app\`:

- `flutter pub get`
- `flutter run --dart-define-from-file env.json -d chrome --web-port 3000`
- `flutter test`

## Local runtime config

Create `env.json` from `env.example.json` and provide:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `VAPID_PUBLIC_KEY`
- `EMAIL_REDIRECT_URL`

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at startup, and the browser push flow depends on the public VAPID key being present.

## Project-specific concerns

- this project is intentionally web-first even though Flutter platform folders still exist
- the UI is organized around a lab shell, not a centered todo screen
- local persistence uses SharedPreferences, so local state behavior is part of the product contract
- push behavior depends on both `web\push.js` and the dedicated `web\push-sw.js` asset
- the current sync engine is still task-based rather than operation-based, so UI expectations should stay aligned with the existing docs

## Related docs

- [`..\README.md`](../README.md)
- [`..\docs\README.md`](../docs/README.md)
- [`..\docs\LOCAL_DEVELOPMENT.md`](../docs/LOCAL_DEVELOPMENT.md)
- [`..\docs\ARCHITECTURE.md`](../docs/ARCHITECTURE.md)
- [`..\docs\TESTING_STRATEGY.md`](../docs/TESTING_STRATEGY.md)
