# Project Analysis - SaaS Reliability Lab

## Scope

This analysis reflects the current repository after the shell transformation from a centered task screen to a reliability-lab workspace.

Reviewed in depth:

- root documentation and configuration
- Flutter application code under `flutter-app/lib/`
- web runtime files under `flutter-app/web/`
- Supabase migrations and Edge Functions under `supabase/`
- scheduled notification worker under `notify-worker/`
- test coverage under `flutter-app/test/` and `notify-worker/test/`

Excluded from deep analysis:

- generated Flutter build artifacts
- generated web output such as `web/main.dart.js`
- default platform boilerplate that still has no project-specific reliability behavior

## Executive summary

The repository now has the right visible product shape for a reliability lab, even though its underlying sync contract is still transitional.

What changed materially:

- the app no longer opens into a centered task-list shell
- the active root UI is now `LabShell`
- operator controls moved into a durable left rail
- task work moved into a canonical bounded center workspace with queue and inspector regions
- runtime evidence moved into a durable right rail backed by explicit state

What that means:

- the frontend is now aligned with the stated goal of making reliability behavior inspectable
- the shell is ready to host deeper reliability features without another redesign
- the main missing work is no longer shell ownership, but explicit sync semantics and richer observability

Short version:

The project is now best described as a working reliability-lab prototype with live runtime diagnostics, real backend integration, and a still-incomplete sync engine.

## Current maturity assessment

### Classification

Working reliability-lab prototype with real runtime evidence.

### Why it is more than a toy

- local-first task CRUD works in the browser
- authentication is real and tied to Supabase
- per-user isolation exists through RLS
- browser push registration and scheduled delivery work end to end
- stale push subscriptions are cleaned up automatically
- the UI now exposes sync, auth, push, and local-state evidence directly

### Why it is not yet a full reliability lab

- there is still no explicit outbox
- there is still no user-visible conflict model
- retry and backoff semantics are still absent
- fault injection is not implemented yet
- observability is still mostly in-app rather than end-to-end
- automated coverage is still narrow relative to the reliability surface

## Structural transformation summary

The most important recent change in the repository is structural, not cosmetic.

| Area | Previous shape | Current shape | Why it matters |
| --- | --- | --- | --- |
| Root UI | Centered task list screen | `LabShell` | Reliability behavior now has durable screen real estate |
| Task UI ownership | Mixed with shell controls | `TaskWorkspace` with control deck, task queue, and inspector | Task interactions are now isolated from shell concerns and selected-task actions no longer overload the header |
| Session, filter, and sync controls | Header actions and dialogs | `LabLeftRail` | Durable operator controls no longer crowd the task workspace |
| Runtime visibility | Mostly implicit or log-based | `SyncDebugPanel` + `RuntimeDebugProvider` | Auth, sync, push, and local state are inspectable in-product |
| Legacy entry point | `TaskList` owned the experience | `TaskList` is a wrapper | Structural drift back to the old layout is less likely |

This is the correct direction for the repository.
It turns the UI into a reliability surface instead of a generic productivity shell.

## Current runtime architecture snapshot

```text
LabShell
  -> LabLeftRail
  -> TaskWorkspace
  -> SyncDebugPanel

TaskWorkspace + LabLeftRail
  -> AgendaProvider
  -> TaskLocalSnapshotCoordinator
  -> TaskMutationCoordinator
  -> TaskSyncCoordinator
  -> WorkspaceSessionCoordinator
  -> RuntimeDebugProvider
  -> SharedPreferences task store
  -> TaskSyncService
  -> UserSessionService
  -> web push helper
  -> Supabase Auth / Postgres / Edge Functions
  -> Cloudflare notification worker
```

Important current truth:

The UI is ahead of the sync engine.
The shell already thinks in terms of explicit runtime states, but the underlying sync contract is still a task-level reconciliation pass rather than a durable operation log.

## Repository responsibility map

| Area | Responsibility | Current status |
| --- | --- | --- |
| `lib/screens/lab_shell.dart` | root responsive lab shell | active implementation |
| `lib/widgets/lab/` | operator rail and task workspace | active implementation |
| `lib/widgets/debug/` | diagnostics rail primitives and rendering | active implementation |
| `lib/providers/agenda_provider.dart` | task orchestration | active implementation |
| `lib/providers/runtime_debug_provider.dart` | runtime evidence model | active implementation |
| `lib/services/task_local_snapshot_coordinator.dart` | local snapshot orchestration | active implementation |
| `lib/services/task_mutation_coordinator.dart` | task-list mutation rules | active implementation |
| `lib/services/task_sync_coordinator.dart` | sync gating and post-sync reload orchestration | active implementation |
| `lib/services/workspace_session_coordinator.dart` | startup and auth-session orchestration | active implementation |
| `lib/services/task_sync_service.dart` | current sync pass | transitional, not yet outbox-based |
| `lib/services/user_session_service.dart` | cached identity and auth alignment | active implementation |
| `lib/helpers/web_push_helper.dart` | browser push registration lifecycle | active implementation |
| `supabase/` | schema, RPCs, subscription functions | active implementation |
| `notify-worker/` | scheduled notification dispatch | active implementation |

## Subsystem assessment

### 1. Bootstrap and dependency graph

Primary files:

- `lib/main.dart`
- `lib/theme/lab_theme.dart`

Current state:

- Supabase initialization is straightforward and explicit.
- `RuntimeDebugProvider` is now a first-class dependency.
- `AgendaProvider` is now wired together with explicit coordination seams for local snapshot, task mutation, sync, and session flow.
- The app now launches `LabShell` directly.

Assessment:

The bootstrap layer is now aligned with the lab identity, although the app title and some platform branding are still generic and should be cleaned up later.

### 2. UI shell and interaction model

Primary files:

- `lib/screens/lab_shell.dart`
- `lib/widgets/lab/lab_left_rail.dart`
- `lib/widgets/lab/task_workspace.dart`
- `lib/widgets/debug/sync_debug_panel.dart`

Current state:

- wide screens show all three panes at once
- the center pane is width-constrained on desktop instead of stretching across all remaining space
- the workspace itself is split into queue controls, task queue, and a persistent task inspector
- narrow screens move both rails into drawers
- narrow workspace layouts keep selection visible through an inline inspector above the queue
- the left rail owns durable controls
- the center workspace owns task interactions
- the right rail owns runtime evidence

Assessment:

This is the strongest area of recent progress.
The UI now reinforces the intended mental model of the project: operate, observe, and experiment.
The center pane also behaves more honestly as a desktop surface instead of a stretched mobile-derived list.

Remaining gap:

The shell is ready for fault injection and outbox states, but those behaviors are still placeholders rather than real experiments.

### 3. Runtime diagnostics model

Primary files:

- `lib/providers/runtime_debug_provider.dart`
- `lib/models/runtime_debug_state.dart`
- `lib/models/runtime_event.dart`

Current state:

- connectivity, auth, sync, push, and local task counts live in one UI-facing state model
- sync outcomes now record explicit success, skipped, partial, and failure timestamps and messages
- the event timeline retains recent runtime evidence in memory

Assessment:

This is the key architectural addition that made the shell transformation intellectually honest.
Without this layer, the diagnostics rail would still be decorative.

Remaining gap:

There is still no operation-level evidence because the underlying sync engine does not yet expose operations.

### 4. Sync engine

Primary file:

- `lib/services/task_sync_service.dart`

Current state:

- `TaskSyncCoordinator` now gates sync entry and reloads local state around the sync engine.
- verifies connectivity and authenticated session presence
- replays tombstoned deletions
- reconciles dirty tasks with remote state using timestamps
- fetches the remote canonical set and merges back locally
- publishes coarse runtime outcomes into the diagnostics model

Assessment:

The service is stable enough for the current prototype and already avoids one dangerous failure mode: stale local overwrite of a fresher remote task.

But it is still not a true sync engine in the sense required for deeper reliability experiments.

Missing pieces:

- explicit local outbox
- per-operation ids and statuses
- retry and backoff semantics
- conflict capture and user-facing conflict state
- auditability of partial replay behavior

### 5. Auth and anonymous-work handling

Primary files:

- `lib/services/user_session_service.dart`
- `lib/widgets/bottomsheets/login.dart`
- `lib/widgets/forms/otp_verify_form.dart`
- `lib/widgets/lab/lab_left_rail.dart`
- `lib/widgets/lab/task_workspace.dart`

Current state:

- Supabase auth is treated as the real source of truth
- cached user identity is mirrored locally for convenience only
- anonymous tasks can exist before login
- authenticated startup triggers sync and push registration
- anonymous tasks can be adopted or discarded explicitly
- the operator rail now keeps anonymous-task review visible beyond the login-time prompt

Assessment:

This is one of the most reliability-relevant features in the repository because it models local work created before identity exists.

Remaining gap:

There is still no richer collision or conflict story when anonymous local work overlaps meaningfully with existing remote state.

### 6. Push and scheduled notification path

Primary files:

- `lib/helpers/web_push_helper.dart`
- `web/push.js`
- `web/push-sw.js`
- `supabase/functions/*`
- `notify-worker/src/index.ts`

Current state:

- signed-in browser profiles can register push subscriptions
- browser push registration now runs through a dedicated `push-sw.js` scope instead of depending on the root Flutter app service worker alone
- push permission and subscription state are visible in the diagnostics rail
- subscriptions are saved and removed through backend functions
- the Cloudflare Worker dispatches due notifications every five minutes
- stale subscriptions are deleted when the provider rejects them as gone

Assessment:

This remains one of the strongest end-to-end slices in the project because it exercises client runtime, backend state, and scheduled infrastructure together.

Remaining gap:

There is still no user-facing history of delivery attempts, and the notification timing model is still simpler than what a production SaaS would require.

### 7. Testing and documentation

Current state:

- the Flutter suite includes at least one meaningful sync regression test
- the worker suite includes stale-subscription cleanup coverage
- the root docs now describe the current shell instead of the old task-list shape
- deployment behavior is now documented explicitly, including GitHub Pages, the deploy workflows, and the runtime environment matrix

Assessment:

The repository is moving in the right direction, but documentation quality is currently ahead of test depth.

Remaining gap:

- the new rails and diagnostics model still need targeted widget tests
- the future outbox contract will need much stronger unit and integration coverage

## Current strengths

- the UI now matches the project's stated purpose
- state ownership is clearer than before
- the center workspace now separates browsing from inspection cleanly on desktop
- auth truth, local state, sync, and push are visible in one place
- the repo has a real end-to-end scheduled notification slice
- the shell is structurally ready for future reliability features

## Current gaps versus the target lab

- no explicit outbox or operation semantics
- no conflict workflow
- no fault injection controls yet
- no structured metrics or correlation ids across client and backend
- no experiment harness for repeatable failure scenarios
- no broad coverage for auth churn, reconnect replay, or multi-device behavior

## Recommended next priorities

1. run the Objective 0 foundation pass so provider ownership, sync coordination, persistence boundaries, backend seams, and delivery boundaries are cleaner before outbox work begins
2. define the explicit outbox model and connect it to the placeholder operation states already reserved in the shell
3. decide where conflict visibility belongs between the diagnostics rail and the task workspace
4. add structured logs and metrics that complement, rather than duplicate, the in-app diagnostics panel
5. add targeted widget tests for the operator rail and diagnostics rail
6. introduce fault-injection controls only after the runtime model can represent their effects faithfully

## Final assessment

The repository is no longer blocked on UI direction.
That problem is solved.

The main challenge now is making the system foundation and later semantics worthy of the new shell:

- cleaner architectural seams
- explicit outbox behavior
- visible conflict handling
- stronger observability
- repeatable experiments

If those pieces land cleanly, the project will stop feeling like a task app with reliability ambitions and start behaving like a real reliability lab.
