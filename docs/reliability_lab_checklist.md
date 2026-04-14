# Reliability Lab Checklist

This checklist tracks the work required to turn the current prototype into a stronger and more honest reliability lab.

The repository has already crossed one major threshold:
the UI is no longer a generic task shell.
It is now a lab-style workspace with durable operator controls and durable runtime evidence.

## How to use this checklist

- treat each phase as a milestone, not a wish list
- keep the repository runnable after each milestone
- prefer small, focused commits with one clear capability per unit
- do not claim reliability behavior in docs until the related path is implemented and observable

## Current baseline

Already present today:

- [x] Flutter Web PWA with local task CRUD
- [x] SharedPreferences-based local persistence
- [x] Supabase authentication integration
- [x] Per-user database isolation through RLS
- [x] Anonymous-to-authenticated task adoption and discard flow
- [x] Desktop-first `TaskWorkspace` with bounded canvas, queue controls, task queue, and task inspector
- [x] Browser push subscription save and remove flow
- [x] Scheduled notification dispatch through Cloudflare Worker
- [x] Reliability-lab shell with operator rail, task workspace, and diagnostics rail
- [x] Runtime diagnostics provider and event timeline for sync, auth, push, and local-state visibility
- [x] Dedicated architecture, experiments, analysis, and checklist documentation aligned with the lab shell

Not yet present today:

- [ ] Durable sync outbox
- [ ] Idempotent mutation protocol
- [ ] Retry with exponential backoff and jitter
- [ ] Conflict visibility and resolution workflow
- [ ] Structured logging and metrics across client and backend
- [ ] Scenario-driven fault injection
- [ ] Strong automated coverage for reliability-critical paths

## Phase 1 - Document the system honestly

Goal: make the implemented structure, ownership, and current limitations explicit.

- [x] Align `README.md` with the lab-shell transformation
- [x] Align `docs/ARCHITECTURE.md` with `LabShell`, `TaskWorkspace`, `LabLeftRail`, and `SyncDebugPanel`
- [x] Align `docs/project_analysis.md` with the current implementation rather than the pre-shell app
- [x] Align `docs/EXPERIMENTS.md` with the current operator and diagnostics surfaces
- [ ] Add a sync state-machine diagram covering local create, dirty, synced, deleted, conflict, and retry states
- [ ] Add an auth/session state-machine diagram covering anonymous, signed-in, signed-out, expired-session, and startup-recovery paths
- [x] Add an environment matrix for local development, GitHub Pages, Supabase, and Cloudflare Worker
- [ ] Add an explicit "known mismatches between implementation and aspiration" section for the future outbox phase

Exit criteria:

- the repository explains the system as it actually exists today
- a contributor can see what is implemented versus merely planned

## Phase 2 - Stabilize the lab shell as the permanent UI foundation

Goal: make the current shell the permanent home of reliability interactions.

- [x] Replace the centered task-screen ownership model with `LabShell`
- [x] Keep `TaskWorkspace` as the canonical center pane
- [x] Constrain the center workspace on large screens instead of stretching it edge to edge
- [x] Turn `TaskWorkspace` into a bounded master/detail surface with queue and inspector regions
- [x] Move durable auth, filter, and session controls into the operator rail
- [x] Add a diagnostics rail backed by explicit runtime state
- [x] Reserve diagnostics slots for future queued, failed, and conflict operation states
- [ ] Define the exact shell ownership for explicit outbox, retry, and conflict resolution views
- [ ] Add real operator-rail controls for future fault injection instead of placeholders

Exit criteria:

- the shell no longer needs another structural redesign before outbox work begins
- every major reliability surface has an obvious home in the UI

## Phase 3 - Replace task-based sync with a real outbox

Goal: make offline replay and convergence explicit, durable, and testable.

- [ ] Replace the implicit dirty-object model with an explicit local outbox
- [ ] Persist each local mutation as its own operation
- [ ] Add operation types such as `create_task`, `update_task`, `complete_task`, `delete_task`, and `reschedule_task`
- [ ] Add per-operation state such as queued, sending, acknowledged, failed, and conflict
- [ ] Add idempotency keys or operation ids that the backend can replay safely
- [ ] Preserve full field fidelity in sync payloads, including `description`, `tags`, and completion metadata
- [ ] Add retry and backoff behavior for recoverable failures
- [ ] Distinguish retryable failures from permanent failures
- [ ] Resume the outbox correctly across refresh and restart
- [ ] Connect the outbox state to the placeholders already reserved in the diagnostics rail

Exit criteria:

- sync is operation-based rather than task-diff-based
- replayed operations are safe under reconnect and duplicate delivery
- users can see pending, blocked, failed, and conflicted work directly in the shell

## Phase 4 - Strengthen the backend contract

Goal: move from direct table mutation toward a backend contract designed for reliability experiments.

- [ ] Decide whether the sync surface should be a Supabase RPC, Edge Function, or dedicated backend service
- [ ] Add server-side idempotency handling for repeated operations
- [ ] Add a `sync_events` or `mutation_log` table for auditability
- [ ] Add a `delivery_attempts` table for notification dispatch attempts
- [ ] Record server-side timestamps for accepted operations separately from client timestamps
- [ ] Define conflict policy explicitly: reject, last-write-wins, or merge workflow
- [ ] Add device identity for multi-device divergence experiments
- [ ] Add worker heartbeat or last-success markers for scheduled-run visibility
- [ ] Decide and document notification semantics: at-most-once, at-least-once, or best-effort

Exit criteria:

- the backend exposes an explicit sync contract
- sync and notification history can be inspected after failures

## Phase 5 - Observability first

Goal: make failures diagnosable instead of anecdotal.

- [x] Add an in-app runtime diagnostics surface for current sync, auth, push, and local-state evidence
- [ ] Add structured logs for sync attempts in the client
- [ ] Add structured logs for Edge Function subscription save and remove flows
- [ ] Add structured logs for scheduled worker runs and per-notification outcomes
- [ ] Add metrics for outbox depth, sync latency, failure reasons, conflict count, auth recovery count, notifications sent, notifications failed, and stale subscriptions deleted
- [ ] Add correlation ids across client, backend, and worker flows where possible
- [ ] Add error tracking for the Flutter app and worker
- [ ] Add a worker run summary view or documented log-query workflow

Exit criteria:

- every failure scenario leaves behind enough evidence to explain what happened
- the lab can be demonstrated through live signals rather than screenshots or console output alone

## Phase 6 - Make failure simulation first-class

Goal: turn the repo into a real lab instead of an app with reliability-themed documentation.

- [ ] Add a dev-only fault injection panel in the operator rail
- [ ] Add toggles for no connectivity, intermittent connectivity, and long sync delays
- [ ] Add a mode to simulate expired auth during replay
- [ ] Add a mode to simulate remote version conflicts
- [ ] Add a mode to simulate duplicate operation delivery
- [ ] Add worker-side simulation for push provider failure and delayed dispatch
- [ ] Add a scenario for stale subscription cleanup and re-registration
- [ ] Add a scenario for missed cron runs and recovery on the next run
- [ ] Add a scenario for multiple browser profiles receiving the same notification
- [ ] Add a scenario for anonymous tasks being adopted after remote tasks already exist

Exit criteria:

- major reliability scenarios can be triggered intentionally
- each scenario has defined expected behavior and expected evidence

## Phase 7 - Add real tests

Goal: make the lab trustworthy and regression-resistant.

- [x] Make the current test commands runnable in a clean environment
- [x] Replace the default Flutter counter test with repository-specific coverage
- [x] Add at least one real sync regression test
- [x] Add at least one real worker regression test
- [x] Add regression coverage for anonymous create -> delete cleanup across the workspace and operator rail
- [ ] Add unit tests for `TaskModel`
- [ ] Add unit tests for `UserSessionService`
- [ ] Add targeted widget tests for `TaskWorkspace` desktop and narrow inspector layouts
- [ ] Add targeted widget tests for `LabLeftRail`
- [ ] Add targeted widget tests for `SyncDebugPanel`
- [ ] Add integration tests for offline create -> reconnect -> sync
- [ ] Add integration tests for duplicate replay of the same operation
- [ ] Add integration tests for conflict detection and resolution
- [ ] Add tests for auth/session divergence handling
- [ ] Add CI steps for Flutter tests, worker tests, and schema validation

Exit criteria:

- the repo has automated coverage for reliability-critical paths
- test failures become meaningful indicators of broken reliability behavior

## Phase 8 - Improve runtime realism

Goal: move from a minimal working demo toward production-style operating conditions.

- [ ] Introduce a stronger local persistence layer than SharedPreferences
- [ ] Add pagination or chunked sync behavior for large task sets
- [ ] Add explicit handling for partial sync success beyond a summary state
- [ ] Add rate-limiting strategy for sync bursts after reconnect
- [ ] Add notification retry policy and dead-letter handling
- [ ] Add explicit session invalidation and device-tracking experiments
- [ ] Add background cleanup policy for old tombstones and stale local data
- [ ] Add environment promotion guidance for local, staging, and public demo deployments

Exit criteria:

- the system behaves predictably under larger and less ideal workloads
- experiments reflect more realistic SaaS operating conditions

## Phase 9 - Polish the repository as a public engineering artifact

Goal: make the lab useful to reviewers, collaborators, and future maintainers.

- [ ] Replace generic app names and remaining default identifiers
- [ ] Keep the README aligned with implemented behavior only
- [ ] Add quick-start instructions for public demo and full local setup paths
- [ ] Add runbooks for common failures such as stuck sync, missed notifications, and auth divergence
- [ ] Add a short incident-postmortem template for experiments
- [ ] Add screenshots or recordings only after the major experiment flows are stable

Exit criteria:

- the project reads like an intentional reliability lab
- reviewers can understand both the current state and the planned evolution quickly

## Recommended immediate priorities

If the goal is maximum leverage from the current state, do these next:

- [ ] define the explicit outbox model and map it onto the reserved shell states
- [ ] decide how conflicts will be surfaced between the diagnostics rail and the task workspace
- [ ] add structured sync and worker logging that complements the in-app diagnostics panel
- [ ] add targeted widget tests for the operator and diagnostics rails
- [ ] add the missing sync and auth state-machine diagrams

## Definition of done for a real reliability lab

This repository becomes a real reliability lab when all of the following are true:

- failure scenarios are intentional and reproducible
- sync semantics are explicit and testable
- runtime behavior is observable in both the UI and backend signals
- notification delivery behavior is inspectable after the fact
- multi-device and offline divergence can be demonstrated on demand
- regressions in reliability behavior are caught by automated tests

At that point, the repository stops being a reliability-aware prototype and becomes a controlled system for studying reliability engineering directly.
