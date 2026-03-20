# Reliability Lab Checklist

This checklist adapts the structure and maturity model of `go-reliability-lab` to the actual shape of this repository.

The goal is not to turn this project into a generic task app. The goal is to turn it into a controlled laboratory for studying:

- offline-first synchronization
- auth/session divergence
- background notification delivery
- multi-device conflict behavior
- system recovery under imperfect network and runtime conditions

## How to use this checklist

- Treat each phase as a milestone.
- Keep the project runnable after each milestone.
- Prefer small, focused commits that introduce one major capability at a time.
- Do not add reliability claims to the README until the related behavior is implemented and testable.

## Current baseline

Already present today:

- [x] Flutter Web PWA with local task CRUD
- [x] SharedPreferences-based local persistence
- [x] Supabase authentication integration
- [x] Per-user database isolation through RLS
- [x] Anonymous-to-authenticated task adoption flow
- [x] Browser push subscription save/remove flow
- [x] Scheduled notification dispatch through Cloudflare Worker
- [x] GitHub Actions deployment for frontend and worker

Not yet present today:

- [ ] Durable sync outbox
- [ ] Idempotent mutation protocol
- [ ] Retry with exponential backoff and jitter
- [ ] Conflict visibility and resolution workflow
- [ ] Structured logging and metrics
- [ ] Scenario-driven failure injection
- [ ] Meaningful test coverage
- [x] Dedicated lab documentation beyond the README

## Phase 1 - Document the system like a lab

Goal: make the architecture and experiment boundaries explicit.

- [x] Add `ARCHITECTURE.md` with the real current topology, not the aspirational one
- [x] Add `EXPERIMENTS.md` listing each failure scenario the lab intends to simulate
- [ ] Add a sync state-machine diagram covering local create, dirty, synced, deleted, conflict, and retry states
- [ ] Add an auth/session state-machine diagram covering anonymous, signed-in, signed-out, expired-session, and startup-recovery paths
- [x] Add a notification flow diagram covering task schedule, pending selection, push dispatch, stale subscription cleanup, and delivery semantics
- [x] Add a local-vs-remote source-of-truth section to clarify ownership of each field
- [ ] Add an environment matrix for local development, GitHub Pages, Supabase, and Cloudflare Worker
- [ ] Add a "known mismatches between README and implementation" section so the repo stays intellectually honest

Exit criteria:

- the repository explains the current system as implemented
- a new contributor can identify where each reliability concern lives

## Phase 2 - Replace debounced sync with a real sync engine

Goal: make offline replay and convergence explicit and testable.

- [ ] Replace the implicit "dirty object" model with an explicit local outbox
- [ ] Persist each local mutation as an operation with its own id
- [ ] Add operation types such as `create_task`, `update_task`, `complete_task`, `delete_task`, `reschedule_task`
- [ ] Add idempotency keys or operation ids that the backend can safely replay
- [ ] Store per-operation status: queued, sending, acknowledged, failed, conflict
- [ ] Preserve full field fidelity in sync payloads, including `description`, `tags`, `completed_at`, and notification-related fields
- [ ] Add exponential backoff with jitter for recoverable failures
- [ ] Distinguish retryable failures from permanent failures
- [ ] Pause and resume the outbox correctly across app restart and browser refresh
- [ ] Surface sync status in the UI so the lab can show pending and failed operations
- [ ] Fix merge correctness so rejected local changes cannot silently override fresher remote state
- [ ] Add deletion tombstones with explicit acknowledgement semantics

Exit criteria:

- sync is operation-based rather than object-diff-based
- replayed operations are safe under reconnect and duplicate send conditions
- users can see when sync is pending, blocked, failed, or conflicted

## Phase 3 - Strengthen the backend contract

Goal: move from direct table mutation toward a backend contract designed for reliability experiments.

- [ ] Decide whether the sync surface should be a Supabase RPC, Edge Function, or dedicated backend service
- [ ] Add server-side idempotency handling for repeated operations
- [ ] Add a `sync_events` or `mutation_log` table for auditability
- [ ] Add a `delivery_attempts` table for push notification dispatch attempts
- [ ] Add indexes for realistic scale paths, especially on `tasks.user_id`, `tasks.updated_at`, `tasks.notify_at`, and subscription lookup fields
- [ ] Record server-side timestamps for accepted operations separately from client timestamps
- [ ] Define conflict policy explicitly: last-write-wins, version mismatch rejection, or merge workflow
- [ ] Add device identity to help study multi-device divergence and session behavior
- [ ] Add a worker heartbeat or last-success marker to detect missed scheduled runs
- [ ] Decide and document notification semantics: at-most-once, at-least-once, or best-effort

Exit criteria:

- the backend has an explicit sync contract
- notification and sync history can be inspected after failures

## Phase 4 - Observability first

Goal: make failures diagnosable instead of anecdotal.

- [ ] Add structured logs for sync attempts in the client
- [ ] Add structured logs for Edge Function subscription save/remove flows
- [ ] Add structured logs for scheduled worker runs and per-notification outcomes
- [ ] Add metrics for:
  - [ ] outbox depth
  - [ ] sync latency
  - [ ] sync failures by reason
  - [ ] conflict count
  - [ ] auth/session recovery count
  - [ ] pending notifications found per worker run
  - [ ] notifications sent
  - [ ] notifications failed
  - [ ] stale subscriptions deleted
- [ ] Add correlation ids from client sync attempt through backend handling where possible
- [ ] Add error tracking for the Flutter app and worker
- [ ] Add a simple in-app debug view showing last sync time, last sync result, pending operations, and last notification activity
- [ ] Add a worker run summary view or log query guide in the docs

Exit criteria:

- any failure scenario leaves behind enough evidence to explain what happened
- the lab can be demonstrated with live runtime signals rather than screenshots alone

## Phase 5 - Make failure simulation first-class

Goal: turn the repo into a real lab instead of an app with failure-themed documentation.

- [ ] Add a dev-only fault injection panel in the client
- [ ] Add toggles to simulate no connectivity, intermittent connectivity, and long sync delays
- [ ] Add a mode to simulate expired auth during outbox replay
- [ ] Add a mode to simulate remote version conflicts
- [ ] Add a mode to simulate duplicate operation delivery
- [ ] Add worker-side simulation for push provider failure and delayed dispatch
- [ ] Add a scenario for stale subscription cleanup
- [ ] Add a scenario for missed cron runs and recovery on next run
- [ ] Add a scenario for multiple browser profiles receiving the same account notification
- [ ] Add a scenario for anonymous tasks being adopted after remote tasks already exist
- [ ] Add a scenario for one device editing while another completes or deletes the same task

Exit criteria:

- every major README scenario can be triggered intentionally
- each scenario has expected behavior and expected observability signals

## Phase 6 - Add real tests

Goal: make the lab trustworthy and regression-resistant.

- [x] Make the current test commands runnable in a clean environment before expanding coverage
- [x] Replace the default Flutter counter test with task-app tests
- [ ] Add unit tests for `TaskModel`
- [ ] Add unit tests for `TaskFilterController`
- [ ] Add unit tests for `TaskSelectionController`
- [ ] Add unit tests for `UserSessionService`
- [ ] Add unit tests for the future outbox/sync engine
- [ ] Add integration tests for offline create -> reconnect -> sync
- [ ] Add integration tests for duplicate replay of the same operation
- [ ] Add integration tests for conflict detection and resolution
- [ ] Add UI tests for anonymous-task adoption/discard flow
- [x] Replace the worker boilerplate test with tests that exercise notification selection and stale subscription cleanup
- [ ] Add tests for Supabase functions if they remain part of the final contract
- [ ] Add CI steps for Flutter tests, worker tests, and schema validation

Exit criteria:

- the repo has automated coverage for its reliability-critical paths
- test failures are meaningful indicators of broken behavior

## Phase 7 - Improve runtime realism

Goal: move from minimal working demo toward production-style engineering conditions.

- [ ] Introduce a stronger local persistence layer than SharedPreferences
- [ ] Add pagination or chunked sync behavior for large task sets
- [ ] Add explicit handling for partial sync success
- [ ] Add rate-limiting strategy for sync bursts after reconnect
- [ ] Add notification retry policy and dead-letter handling for repeated failures
- [ ] Add explicit session invalidation and device/session tracking experiments
- [ ] Add background cleanup policy for old tombstones and stale data
- [ ] Add backup and recovery notes for Supabase state used by experiments
- [ ] Add environment promotion strategy for local, staging, and public demo deployments

Exit criteria:

- the system behaves predictably under larger and less ideal workloads
- experiments reflect more realistic SaaS operating conditions

## Phase 8 - Polish the repository as a public engineering artifact

Goal: make the lab useful to reviewers, collaborators, and future you.

- [ ] Replace generic Android/iOS identifiers and app names
- [ ] Update the README so every claim maps to implemented behavior
- [ ] Add quick-start instructions for the public demo path and the full local path
- [ ] Add a roadmap document with ordered milestones and recommended commit history
- [ ] Add a checklist document that can be used during reviews and releases
- [ ] Add runbooks for common failures such as stuck sync, missed notifications, and auth divergence
- [ ] Add a short incident postmortem template for experiments
- [ ] Add screenshots or recordings of the major experiment flows only after the flows are stable

Exit criteria:

- the project reads like an intentional reliability lab
- reviewers can understand both the current state and the planned evolution

## Recommended immediate priorities

If the goal is to get the highest leverage improvements first, do these next:

- [x] Fix sync merge correctness so fresher remote state cannot be silently overridden locally
- [x] Replace the placeholder tests with one real sync test and one real worker test
- [ ] Add a visible sync/debug panel to the UI
- [ ] Introduce an explicit local outbox structure
- [ ] Add structured logging for sync attempts and worker runs
- [x] Write `ARCHITECTURE.md` and `EXPERIMENTS.md`

## Definition of done for "real reliability lab"

This repository becomes a real reliability lab when all of the following are true:

- failure scenarios are intentional and reproducible
- sync semantics are explicit and testable
- runtime behavior is observable through logs and metrics
- notification delivery behavior is inspectable after the fact
- multi-device and offline divergence can be demonstrated on demand
- regressions in reliability behavior are caught by automated tests

At that point, the repository stops being a reliability-flavored app and becomes a controlled system for studying reliability engineering.