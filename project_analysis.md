# Project Analysis - SaaS Reliability Lab

## Scope

This report is based on the project-specific source, configuration, workflow, and test files currently in the repository.

Reviewed in depth:

- Top-level docs and config: `README.md`, `pubspec.yaml`, `analysis_options.yaml`, `devtools_options.yaml`, `env.example.json`, `env.json`, `.gitignore`
- Flutter app code under `lib/`
- Web runtime files under `web/`
- Supabase schema and Edge Functions under `@backend/supabase/`
- Scheduled notification worker under `@backend/agenda-notify-worker/`
- Deployment workflows under `.github/`
- Utility scripts under `scripts/`
- Existing test files under `test/` and `@backend/agenda-notify-worker/test/`
- Representative platform and local-dev config files under `android/`, `ios/`, `macos/`, `linux/`, `windows/`, and `.vscode/`

Excluded from deep analysis:

- Generated Flutter build output under `build/`
- Generated web artifacts under `web/main.dart.js`, `web/flutter_service_worker.js`, and similar generated files
- Standard Flutter platform boilerplate that does not currently contain project-specific reliability logic

## Executive Summary

The repository is a working Flutter Web PWA that demonstrates one meaningful reliability slice end to end:

- local-first task creation and mutation
- authenticated synchronization to Supabase
- browser push subscription registration per signed-in device/profile
- scheduled push delivery through a Cloudflare Worker
- automatic cleanup of stale push subscriptions

At the same time, the codebase is still closer to a strong prototype than to a full reliability laboratory.

What exists today:

- a usable local task app with optional authentication
- a basic sync loop that can push local changes and reconcile with remote state
- a real notification path from task schedule to browser notification
- deployment automation for the frontend and scheduled worker

What is still missing for a true reliability lab:

- a durable sync engine with explicit operation semantics
- real retry and backoff behavior
- observability, metrics, traces, and run diagnostics
- deterministic conflict handling and conflict visibility
- repeatable failure injection scenarios
- automated tests for sync, auth divergence, notification delivery, and multi-device behavior

Short version: the repository already demonstrates the product shape of a reliability lab, but not yet the instrumentation, repeatability, and experiment harnesses that would make it a real engineering laboratory.

## Current Maturity Assessment

### Current classification

Working prototype with real backend integration.

### Why it is more than a toy

- The app persists local state across sessions.
- The app authenticates against a real auth provider.
- The database schema includes per-user isolation through RLS.
- Web push works through registered subscriptions rather than local fake notifications.
- A scheduled worker dispatches reminders independently of the client session.

### Why it is not yet a full reliability lab

- There is no explicit experiment framework.
- There are no metrics or structured runtime signals.
- The sync model is not durable enough to study failure recovery rigorously.
- Most failure scenarios described in the README are not yet encoded as automated or reproducible exercises.
- The existing tests are mostly boilerplate placeholders.

## Architecture Snapshot

### Runtime topology

```text
Flutter Web client
  -> SharedPreferences local cache
  -> AgendaProvider state orchestration
  -> TaskSyncService sync pass
  -> Supabase Auth + Postgres + Edge Functions
  -> Cloudflare scheduled worker
  -> Web Push delivery to browser service worker
```

### Main architectural choice

The current system is a direct client-to-platform architecture:

- the Flutter app talks directly to Supabase tables and functions
- Supabase provides auth, database access, and Edge Functions
- a separate Cloudflare Worker handles scheduled notification dispatch

This keeps the system small and deployable, but it also means there is no explicit application backend layer where reliability policies, instrumentation, or experiment toggles can be centralized.

## Repository Responsibility Map

| Area | Responsibility | Notes |
| --- | --- | --- |
| `lib/` | Flutter application logic | Main product behavior lives here |
| `web/` | PWA shell and browser push integration | Critical for service worker and push registration |
| `@backend/supabase/migrations/` | Database schema and RPC functions | Defines current backend contract |
| `@backend/supabase/functions/` | Subscription management and on-demand push dispatch | Real push-related server logic |
| `@backend/agenda-notify-worker/` | Scheduled notification delivery | Most reliability-specific backend component today |
| `.github/` | Frontend and worker deployment automation | Production-style deployment steps exist |
| `scripts/` | Build-time service worker merge | Important for Flutter web push support |
| `test/` and `@backend/agenda-notify-worker/test/` | Tests | Mostly placeholder coverage |
| Platform folders | Default Flutter multi-platform scaffolding | Minimal project-specific customization so far |

## Feature Breakdown

## 1. Application bootstrap and dependency graph

Primary files:

- `lib/main.dart`
- `lib/keys.dart`
- `lib/helpers/app_mode_helper.dart`

What it does:

- Initializes Flutter bindings.
- Exposes release-mode information to JavaScript through `isReleaseMode`.
- Initializes Supabase using `--dart-define` variables.
- Builds a single `AgendaProvider` with:
  - `TasksSharedPreferencesRepository`
  - `TaskSyncService`
  - `UserSessionService`
- Launches the `TaskList` screen as the root UI.

Assessment:

- Clean and small bootstrap.
- Dependency wiring is simple and understandable.
- There is no environment abstraction layer beyond Dart defines.
- Theme and app naming are still generic and closer to a default Flutter app than a reliability-lab artifact.

## 2. Task domain model

Primary file:

- `lib/models/task.dart`

Implemented domain fields:

- identity: `id`
- schedule: `beginsAt`, `estimatedDuration`, computed `endsAt`
- content: `title`, `description`
- completion: `isCompleted`, `completedAt`
- metadata: `priority`, `tags`
- sync metadata: `syncStatus`, `lastModifiedAt`
- cloud metadata: `createdAt`, `updatedAt`, `userId`

Derived behavior:

- `isToday`
- `isUpcoming`
- `isOverdue`
- `isInProgress`
- `status`
- time deltas for start, end, and overdue duration

Mutation helpers:

- `dirty()`
- `markAsDeleted()`
- `toggleCompletion()`
- `markAsCompleted()`
- `markAsPending()`
- `addTag()` / `removeTag()`
- `reschedule()`
- `updateDuration()`

Current technical limits:

- `description` exists in the model but is not exposed by the current form UI.
- `tags` exist in the model but are not surfaced in the current UI.
- `toCloudJson()` omits `completed_at`, `tags`, `sync_status`, and `user_id`.
- Notification timing is not a first-class model field in the client; `notify_at` is always derived from `beginsAt` during cloud sync.

Implication:

The model already hints at a richer product than the current UI and sync layer actually support. The data shape is ahead of the feature-complete implementation.

## 3. Local-first persistence

Primary file:

- `lib/repositories/tasks_repository.dart`

What is implemented:

- Uses `SharedPreferencesWithCache`.
- Stores all tasks under a single `tasks` key.
- Serializes each task as a JSON string.
- Supports load, save, and clear.

Strengths:

- Very simple.
- Good enough for a browser demo and small offline cache.
- Makes anonymous local usage possible before login.

Limitations:

- There is no real local database.
- There is no query model, index, or outbox table.
- There is no persisted operation log.
- SharedPreferences is not a strong long-term foundation for studying queue semantics, replay, corruption recovery, or large offline datasets.

Assessment:

This is acceptable for the current prototype stage, but a real reliability lab should eventually move to a more explicit local storage engine such as IndexedDB-backed persistence, Drift, Isar, or another storage layer that supports separate entities, sync state, and event history.

## 4. Provider orchestration and local app state

Primary file:

- `lib/providers/agenda_provider.dart`

What it manages:

- in-memory task collection
- selected task state
- active filter and search state
- current user id mirror
- loading state

Exposed feature set:

- load tasks from local repository
- create, update, delete, and toggle task completion
- filter and search tasks
- select and clear selected task
- bulk helpers such as `markAllAsCompleted()` and `clearCompletedTasks()`
- load, save, and clear user session state
- full-task sync on login
- migration of anonymous tasks to the authenticated user

Important behavior:

- All newly created or modified tasks are marked dirty locally before sync.
- Deletions are soft deletions locally through `SyncStatus.deleted` until sync removes them remotely.
- Sync is triggered automatically after writes when a user is logged in.

Observations:

- The provider is the real application coordinator.
- The public API is larger than the current UI uses. Some bulk operations are present in code but not surfaced in the interface.
- Anonymous-mode handling is explicit, which is good for the reliability-lab story.

## 5. Sync pipeline

Primary files:

- `lib/services/task_sync_service.dart`
- `lib/controllers/debounce_controller.dart`

Current sync algorithm:

1. Check network availability using `connectivity_plus`.
2. Require both `currentUser` and `currentSession`.
3. Delete locally tombstoned tasks from the remote table.
4. For dirty tasks:
   - insert if the remote row does not exist
   - update only if local `lastModifiedAt` is newer than remote `updated_at`
5. Save the updated local list.
6. Fetch all remote tasks ordered by `start_date`.
7. Remove local tasks that disappeared remotely.
8. Merge remote tasks and local tasks by id.
9. Persist the merged result locally.

What is implemented well:

- Connectivity check prevents obviously pointless sync attempts.
- Tombstones are used instead of immediately deleting local records.
- Client-generated UUIDs help avoid naive duplicate inserts for the same logical task.
- There is at least one attempt at conflict awareness using timestamps.

What is not implemented despite the README narrative:

- no explicit retry policy
- no exponential backoff
- no jitter
- no sync attempt history
- no per-operation acknowledgements
- no durable queue semantics
- no conflict surfacing to the user
- no transactional or batch sync contract

Recent stabilization:

The sync service now keeps the remote copy whenever the local task is not provably newer, and a Flutter regression test covers that behavior.

Remaining sync risks:

- there is still no explicit conflict state exposed to the user
- there is still no durable outbox or operation log
- there is still no retry or backoff policy

Conclusion:

The code currently behaves more like a debounced reconciliation pass than a real sync queue.

## 6. Session handling and authentication

Primary files:

- `lib/services/user_session_service.dart`
- `lib/widgets/bottomsheets/login.dart`
- `lib/widgets/forms/otp_verify_form.dart`
- `lib/screens/task_list.dart`

Current behavior:

- Supabase remains the source of truth for auth state.
- `userId` is mirrored into SharedPreferences as a convenience cache.
- Stale cached `userId` is cleared when there is no live Supabase user.
- Login uses email and password.
- Sign-up triggers a follow-up OTP verification flow.
- `TaskList` subscribes to auth state changes and reacts to signed-in and signed-out events.

Signed-in path:

- save current user id locally
- sync all tasks
- register web push subscription
- prompt about anonymous tasks if any exist

Signed-out path:

- clear selection and search state
- clear cached user id
- clear all local tasks
- unregister push subscription best-effort

Good decisions:

- Session truth is derived from Supabase state rather than a local `userId` flag.
- Startup sync is explicitly triggered when a stored session already exists.
- Logout cleanup treats push unregistration as bounded best-effort rather than blocking forever.

Open issue:

The local Supabase config sets `enable_confirmations = false`, while the sign-up UI assumes a confirmation step with OTP verification. That means local auth behavior and intended production auth behavior may diverge depending on how the remote Supabase project is configured.

## 7. Anonymous mode and account adoption

Primary files:

- `lib/providers/agenda_provider.dart`
- `lib/screens/task_list.dart`

Current behavior:

- Users can create and manage tasks without logging in.
- Anonymous tasks have `userId == null`.
- After login, the app first runs a full sync and push registration.
- If anonymous tasks are still present, the user sees a dialog:
  - `Keep`: assign current `userId`, mark tasks dirty, then sync
  - `Discard`: remove anonymous tasks from local storage

Why this matters:

This is one of the clearest reliability-lab-relevant features in the app. It reflects a real-world SaaS issue: local work created before identity is established.

What is still missing:

- explicit collision strategy if local anonymous content and remote content meaningfully overlap
- audit trail of what got adopted versus discarded
- richer user-facing messaging about merge consequences

## 8. Task list UI and interaction model

Primary files:

- `lib/screens/task_list.dart`
- `lib/widgets/forms/task_form.dart`
- `lib/widgets/tiles/task_tile.dart`
- `lib/widgets/common/transition_switcher.dart`
- `lib/controllers/task_filter_controller.dart`
- `lib/controllers/task_selection_controller.dart`

Implemented UI features:

- task list rendering
- create task dialog
- edit selected task dialog
- delete selected task dialog
- completion toggle
- search bar
- task filters:
  - all
  - completed
  - pending
  - today
  - upcoming
  - overdue
- single-task selection banner with edit/delete/close actions
- periodic rebuild every 5 seconds so time-based task status remains visually current

Task form currently supports:

- title
- start date and time
- duration
- priority

Not currently exposed in the UI:

- description editing
- tag editing
- custom notification time
- bulk actions from the visible UI
- sync/debug status visibility

Assessment:

The UI is serviceable for demonstrating local scheduling behavior, but it does not yet expose the system internals required for a reliability lab. There is no debug panel, sync status pane, or experiment control surface.

## 9. Web push registration and browser integration

Primary files:

- `lib/helpers/web_push_helper.dart`
- `web/push.js`
- `web/push-sw.js`
- `scripts/merge_sw.sh`
- `scripts/merge_sw.bat`

What is implemented:

- permission priming before login on web
- service worker registration with release vs debug path handling
- bounded waits for service worker activation and subscription creation
- browser push subscription creation using the VAPID public key
- save and delete subscription through Supabase Edge Functions
- browser-side service worker that shows notifications using the app icon assets

Important engineering detail:

For release builds, custom push service worker code is merged into Flutter's generated `flutter_service_worker.js` after `flutter build web`. This is necessary because Flutter web owns the default service worker output.

Strengths:

- The project has a real service-worker-aware web push path.
- Registration and cleanup use timeouts, which prevents some stuck logout and startup flows.
- Multiple browser profiles can subscribe independently for the same account.

Limitations:

- This is web-only push. Mobile and desktop native notification integrations are not yet implemented.
- There is no subscription freshness or renewal strategy.
- There is no UI to show subscription state, last registration time, or delivery diagnostics.

## 10. Supabase schema and security model

Primary files:

- `@backend/supabase/migrations/20250627011416_init_agenda_schema.sql`
- `@backend/supabase/migrations/20250627024942_get_pending_notification_function.sql`
- `@backend/supabase/migrations/20250627044501_set_user_id_trigger.sql`
- `@backend/supabase/migrations/20250709024010_get_my_pending_notifications_function.sql`

Current database objects:

### `tasks`

Columns include:

- `id`
- `user_id`
- `title`
- `description`
- `start_date`
- `due_date`
- `completed`
- `notify_at`
- `notification_sent`
- `priority`
- `created_at`
- `updated_at`

### `push_subscriptions`

Columns include:

- `id`
- `user_id`
- `endpoint`
- `p256dh`
- `auth`
- `created_at`

Security model:

- RLS is enabled on both tables.
- Authenticated users can access only rows matching `auth.uid() = user_id`.
- A trigger assigns `user_id` automatically on insert to `tasks`.
- Push subscriptions enforce uniqueness on `(user_id, endpoint)`.

RPC functions:

- `get_pending_notifications(now)` returns all pending task/subscription pairs for the scheduled worker.
- `get_my_pending_notifications(now)` returns only pending notifications for the current authenticated user.

Assessment:

- The schema is small and coherent.
- Security boundaries are straightforward.
- There are no explicit indexes for large-scale scheduling or sync workloads yet.
- There is no sync audit table, operation log, or delivery-attempt history.

## 11. Notification delivery pipeline

Primary files:

- `@backend/supabase/functions/save_subscription/index.ts`
- `@backend/supabase/functions/delete_subscription/index.ts`
- `@backend/supabase/functions/send-push-notifications/index.ts`
- `@backend/agenda-notify-worker/src/index.ts`

### Save subscription

Behavior:

- accepts POST only
- authenticates the user through the bearer token
- upserts `(user_id, endpoint)` into `push_subscriptions`

Assessment:

- This is a proper idempotent registration path.

### Delete subscription

Behavior:

- accepts POST only
- deletes the subscription by `user_id` and `endpoint`

Assessment:

- Suitable for logout cleanup.
- Best effort is appropriate here.

### On-demand push dispatch function

Behavior:

- calls `get_my_pending_notifications(now)`
- sends push messages using VAPID keys
- sets `notification_sent = true` on successful provider request
- deletes stale subscriptions when the provider returns `404` or `410`

Important note:

The app contains `PushNotificationService`, but there are no call sites in the Flutter UI. That means the on-demand dispatch function exists, but scheduled delivery is the actual live path right now.

### Scheduled Cloudflare worker

Behavior:

- runs every 5 minutes via cron
- calls `get_pending_notifications(now)` using the service role
- sends push payloads directly to endpoints
- marks tasks as `notification_sent = true`
- deletes stale subscriptions on `404` or `410`

Current semantics:

- The system is effectively at-most-once after provider acceptance.
- There is no confirmation that the client displayed or received the notification beyond the push provider response.

Important constraint:

`notify_at` is always set from `beginsAt` in client sync, so scheduled notifications currently mean "notify at task start time" rather than a user-configurable reminder policy.

## 12. CI/CD and developer workflow

Primary files:

- `.github/workflows/deploy.yaml`
- `.github/actions/build-and-deploy-action/action.yaml`
- `.github/workflows/deploy-notify-worker.yaml`
- `.vscode/launch.json`
- `@backend/.env.example`

Frontend deployment:

- Triggered on pushes to `master`.
- Builds Flutter web with `--pwa-strategy=offline-first`.
- Injects Supabase and VAPID config via secrets.
- Merges push service worker logic into the generated Flutter service worker.
- Force-pushes build output to `gh-pages`.

Worker deployment:

- Triggered on pushes affecting `@backend/agenda-notify-worker/**` or the workflow file.
- Uses Node 20 and Wrangler to deploy the worker.

Local development:

- `.vscode/launch.json` launches Chrome on port 3000 with `--dart-define-from-file env.json`.
- Root `.gitignore` excludes `env.json`.
- Backend `.env.example` documents required keys.

Assessment:

- Deployment automation is one of the strongest parts of the repository.
- The project already behaves like something that is meant to be publicly runnable.

## 13. Testing and quality gates

Primary files:

- `test/widget_test.dart`
- `@backend/agenda-notify-worker/test/index.spec.ts`
- `analysis_options.yaml`
- `@backend/agenda-notify-worker/vitest.config.mts`

Current state:

- Dart linting uses the default `flutter_lints` set with almost no project-specific rules.
- The Flutter test suite now includes a real sync regression test that verifies stale local state does not overwrite a fresher remote task.
- The worker test suite now includes a real notification-path test that verifies stale subscription cleanup after a `410 Gone` push response.
- `flutter test` passes from the repository root.
- `yarn test` passes in `@backend/agenda-notify-worker` after pinning `vitest` to `3.2.0` and running the worker tests in plain node-mode `vitest run`.

What this means:

- The repository now has meaningful but still narrow regression protection.
- Important failure-prone systems that still need broader coverage include:
  - sync behavior
  - multi-device merge behavior
  - auth/session divergence during replay
  - logout cleanup and subscription removal
  - notification dispatch beyond the stale-subscription path

Assessment:

Coverage is now pointed at real reliability behavior, but it is still far from enough for a full lab.

## 14. Platform support and packaging status

Representative files reviewed:

- `android/build.gradle.kts`
- `android/app/build.gradle.kts`
- `android/settings.gradle.kts`
- `ios/Runner/Info.plist`
- `macos/Runner/Info.plist`
- `linux/CMakeLists.txt`
- `windows/CMakeLists.txt`

Current state:

- The project still carries standard Flutter multi-platform scaffolding.
- Android app id is still `com.example.todo_flutter`.
- iOS display name is still `Todo Flutter`.
- There is no mobile-specific notification or auth customization.
- The lab is effectively a Flutter Web PWA first, with other targets not yet productized.

Assessment:

That is completely reasonable for the current scope, but the repository should describe itself as web-first until those targets are intentionally supported.

## Implemented vs README Claims

| README claim | Actual status | Notes |
| --- | --- | --- |
| Offline-first local state | Implemented | SharedPreferences-backed local task state works |
| Sync queue | Partially implemented | Debounced sync pass exists, but not a durable queue |
| Retry / backoff | Mostly missing | Connectivity check exists, but no exponential backoff or retry policy |
| Idempotent operations | Partial | Subscription upsert is idempotent; task sync is not a complete idempotent protocol |
| Conflict handling | Partial | Timestamp-based remote-wins safety exists, but conflicts are still silent and not user-visible |
| Background jobs and notifications | Implemented | Scheduled worker and push delivery are real |
| Auth session persistence | Implemented | Supabase session plus cached user id mirror |
| Multi-device reliability experiments | Conceptual only | There is no dedicated test harness or visibility for this yet |
| Failure-mode laboratory | Not yet | The repo describes the vision, but lacks explicit experiments and instrumentation |

## Major Risks and Gaps

### 1. No explicit conflict state or durable outbox

Severity: high

Why it matters:

- The most dangerous stale-local-overwrites-remote bug is fixed, but the system still lacks explicit operation semantics and visible conflict handling.

### 2. No real operation queue or idempotency contract

Severity: critical

Why it matters:

- The README frames the project around replayed actions, retries, and delayed writes, but the current code does not model operations as first-class units.

### 3. No observability

Severity: high

Why it matters:

- A reliability lab without logs, metrics, traces, or experiment telemetry cannot teach or demonstrate reliability engineering effectively.

### 4. Test coverage is still narrow

Severity: high

Why it matters:

- The repository now has one real Flutter sync regression test and one real worker notification test, but most reliability-critical paths remain untested.

### 5. SharedPreferences is too weak for long-term lab goals

Severity: medium

Why it matters:

- It limits the ability to study durable local queues, corruption handling, migrations, and offline history.

### 6. UI and sync fidelity do not match the data model

Severity: medium

Why it matters:

- Fields such as `description`, `tags`, and `completed_at` are not consistently represented across UI and cloud sync.

### 7. Notification semantics are minimal

Severity: medium

Why it matters:

- There is no retry policy, delivery-attempt history, or user-level acknowledgement state.

### 8. Platform packaging remains generic

Severity: low

Why it matters:

- This does not block the lab vision, but it signals the project is still in prototype packaging mode.

## What the Project Already Demonstrates Well

- The tension between anonymous local usage and authenticated ownership.
- The challenge of syncing locally edited state to a shared backend.
- The need to treat browser push subscriptions as per-device/per-profile state.
- The fact that scheduled work and notification delivery belong on trusted backend infrastructure.
- The importance of cleanup paths, especially for stale subscriptions and logout flows.

## What the Project Needs to Become a Real Reliability Lab

- explicit architecture and experiment documents beyond the README
- a real sync engine with outbox semantics and idempotent operations
- observability-first instrumentation
- repeatable failure injection scenarios
- automated sync and notification tests
- richer state introspection in the UI for demo and debugging
- a commit-level or phase-level development roadmap similar in spirit to `go-reliability-lab`

## Final Assessment

The repository already contains the core scenario that makes the concept compelling:

- a user can work locally
- state can later sync into a shared backend
- notifications can be delivered out of band through a scheduled worker

That is enough to prove the project direction is valid.

However, the current implementation is still a reliability-themed application, not yet a reliability laboratory.

The next stage should not be "add more product features." It should be:

- make sync semantics explicit
- instrument the system
- add reproducible failure scenarios
- test the failure scenarios automatically

That is the path that turns this repository from an interesting SaaS demo into a serious engineering artifact.