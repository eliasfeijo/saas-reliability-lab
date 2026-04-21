# Fault Injection Plan

## Purpose

This document defines the recommended end-to-end implementation plan for fault injection in the SaaS Reliability Lab.

It is a planning document.
It does not claim that every scenario below is implemented today.

The goal is to turn the current shell and runtime diagnostics into a real experiment harness without pretending the repository already has deeper sync semantics than it actually does.

## Current readiness

The repository is ready to begin the first fault-injection slices now.

Implemented today:

- a stable lab shell with a durable operator rail
- a stable runtime diagnostics surface for connectivity, auth, sync, push, and local task counts
- an explicit local outbox with per-entry queued, sending, acknowledged, failed, conflict, blocked-session, and blocked-review states
- operator-facing connectivity-loss and delayed-sync scenarios, including delay presets tuned for live demonstrations
- first-slice conflict capture and review surfaces in the runtime diagnostics rail

Still missing today:

- retry and backoff behavior
- richer per-scenario fault-injection modes beyond the current connectivity-loss and full-pass delayed-sync slices
- backend idempotency contract for duplicate replay
- a stronger backend-owned mutation boundary for truly server-shaped delay and replay experiments

Practical conclusion:

- the lab can keep implementing fault injection immediately on top of the current outbox replay model
- duplicate-replay and conflict-heavy scenarios are now semantically closer than before, but they should still wait for a clearer backend contract and explicit idempotency story

## Planning principles

This plan follows the repository's current framing:

1. keep the project a reliability lab first
2. inject failures at real seams, not only in the UI
3. leave visible evidence for every injected scenario
4. describe planned behavior as planned behavior, not as implemented behavior
5. prefer a sequence that produces useful educational scenarios early without locking the repo into fake semantics

## Decisions captured for this plan

These decisions reflect the current direction for the project.

### 1. Scenario activation model

Recommended initial model:

- single-active scenario for the first implementation slices

Why:

- it keeps operator behavior easier to understand during demos and videos
- it avoids ambiguous interactions between multiple injected failures before the runtime model can explain them clearly
- it reduces early test complexity

Planned evolution:

- keep the internal model open to future combinable toggles once the runtime evidence can explain stacked failures clearly

### 2. Environment visibility

Scenario controls should be available in every environment the lab runs in today.

That means:

- do not hide them behind `kDebugMode`
- do not hide them behind a compile-time environment flag
- do not treat them as local-only developer controls

Because this repository is a lab, the scenario controls are part of the product surface rather than an internal debugging convenience.

The UI should still make it obvious when a scenario is active so no environment can be mistaken for a natural runtime state.

### 3. First delayed-sync implementation shape

Recommended first implementation:

- delay the whole sync pass, not individual steps

Why this is the best first version:

- it is the easiest behavior to explain in videos and live demos
- it is realistic enough for an early-stage SaaS interpretation of delayed convergence
- it introduces less code and test complexity than per-step delay injection
- it avoids implying that the current sync engine already exposes a richer operation pipeline than it actually does

Planned later evolution:

- once the first version is working and observable, add optional per-step delay injection for more advanced experiments

### 4. First conflict to model after outbox work

Recommended first conflict:

- update/update conflict

Why:

- it is easier to explain than update/delete
- it is easier to visualize in the current task domain
- it is easier to demonstrate educationally because both sides still have a visible record to compare
- it avoids prematurely forcing a deletion-lifecycle decision into the first conflict experience

## Recommended implementation order

The recommended order is:

1. fault-injection foundation slice
2. connectivity loss
3. delayed sync
4. expired auth
5. network drop during partial replay
6. richer delayed-sync modes on the outbox replay path
7. duplicate replay
8. update/update conflict simulation
9. worker-side fault injection

This order is deliberate.
The first five slices fit the current architecture well enough to be implemented honestly.
The sixth slice now reflects the current repository reality: the outbox and first state-machine slice exist, so delayed sync can evolve into transport-shaped and backend-shaped experiments before duplicate replay and deeper conflict simulation.

## Phase 0 - Foundation slice

### Goal

Create the fault-injection infrastructure once so each scenario lands as a small, testable increment.

### Why this should happen first

The operator rail already reserves scenario space, but the repository still lacks a real domain model for injected runtime conditions.

Without a foundation slice, the first scenarios would likely spread ad hoc conditional logic across widgets and services.

### Recommended implementation surfaces

Primary new files in `flutter-app/lib/`:

- `models/fault_injection_scenario.dart`
- `models/fault_injection_state.dart`
- `providers/fault_injection_provider.dart`
- `services/fault_injection_policy.dart`

Primary existing files to evolve:

- `widgets/lab/lab_left_rail.dart`
- `providers/runtime_debug_provider.dart`
- `models/runtime_debug_state.dart`
- `services/task_sync_coordinator.dart`
- `services/task_sync_service.dart`

### Recommended domain model

Add a scenario enum or equivalent named model for:

- `none`
- `connectivityLoss`
- `delayedSync`
- `expiredAuth`
- `partialReplayDrop`
- `duplicateReplay`
- `conflictUpdateUpdate`

The initial public UI should expose only the scenarios that are implemented.

### Recommended state model

The scenario state should at minimum support:

- active scenario
- whether injection is enabled
- delay duration in milliseconds
- delay mode for scenarios that can target more than one seam
- optional trigger step for step-based failures
- whether the next failure is one-shot or persistent
- explanatory label or operator note

### Recommended runtime evidence additions

Extend the runtime evidence model to show:

- active injected scenario
- scenario parameters currently applied
- whether the last skip, partial, or failure result was fault-injected
- an event entry when a scenario becomes active or inactive

The runtime panel should tell the operator that the current state is synthetic, not natural.

### Recommended UI ownership

The operator rail should own:

- scenario selection
- scenario activation and reset
- any low-complexity parameters such as delay duration

The diagnostics rail should own:

- evidence that the scenario was applied
- the resulting sync and auth state changes
- recent event timeline entries tied to the injected condition

### Exit criteria

- the shell has real scenario controls rather than placeholder chips
- sync-side code can consult a single fault-injection policy instead of scattered booleans
- the runtime evidence can distinguish fault-injected behavior from natural behavior

## Phase 1 - Connectivity loss

### Goal

Simulate complete connectivity loss at the sync boundary.

### Why this is the first real scenario

The current sync engine already gates on connectivity before starting work.
That makes connectivity loss the cleanest first scenario because it fits the current architecture without pretending operation-level replay already exists.

### Recommended implementation approach

Introduce a seam above the connectivity check already used by `TaskSyncService`.

When `connectivityLoss` is active:

- the effective connectivity check should return offline
- sync should mark a skipped outcome with visible evidence
- the runtime event timeline should record that the offline state was injected intentionally

### Expected user-visible evidence

- operator rail shows the active scenario
- diagnostics show `Waiting for Network`
- last sync result shows `Skipped`
- timeline shows a connectivity-loss injection event

### Recommended tests

- service-level test for injected offline behavior
- rail widget test for scenario selection and reset
- diagnostics widget test for fault-injected offline evidence
- integration-style test for offline create -> attempted sync -> reconnect -> sync

### Exit criteria

- the app can reliably enter and leave a forced-offline sync state
- the state is clearly visible in the shell
- the experiment is reproducible in local and published environments

## Phase 2 - Delayed sync

### Goal

Simulate a slow sync pass that still eventually converges.

### Recommended first version

Delay the whole sync pass.

Do not begin with per-step delay injection.

Current implementation status:

- delayed sync now supports a setup modal with `500 ms`, `2 s`, `5 s`, and `10 s` presets plus a recommended `5 s` fast path
- `local`, `transport`, and `backend` delayed-sync modes now run on the explicit outbox replay path
- delayed sync now supports `persistent` and `one-shot` behavior plus stage-aware diagnostics that name the active delayed seam
- the current delayed-sync slice remains client-owned inside the sync service rather than being backed by a server-owned mutation contract

Important current boundary:

- the implemented delayed-sync slice is still client-owned on the explicit outbox replay path
- `transport` and `backend` modes are now implemented as honest client-side simulations around named replay seams and acknowledgement timing
- true server-owned execution delay still depends on a future backend mutation boundary rather than more client-only fault-injection work

### Why this is the right first version

- it is simpler to demonstrate and understand
- it stays honest to the current task-based sync model
- it produces an educationally useful scenario without requiring an outbox first
- it models a real SaaS symptom: local actions appear immediate, but convergence to remote truth is slower than the user expects

### Recommended implementation approach

When `delayedSync` is active:

- inject a configurable `Future.delayed` before the sync pass begins or around the full `syncTasks()` run
- keep sync phase visibly in `Syncing` during the delay window
- record the configured delay in runtime evidence

Suggested initial delay presets:

- `500 ms`
- `2 s`
- `5 s`
- `10 s`

### Expected user-visible evidence

- longer `Syncing` phase duration
- meaningful started/completed timestamps
- timeline entry that the sync pass was intentionally delayed

### Recommended tests

- service-level timing-aware test with fake async or controlled clock
- widget test for active delayed-sync scenario visibility
- integration-style test for local mutation + delayed sync + eventual success

### Delayed-sync follow-up after this batch

The next work item after the implemented delayed-sync batch is not another client-only delay mode.

It is the future backend-owned mutation-boundary sketch in `SERVER_OWNED_MUTATION_BOUNDARY_PLAN.md`, which describes how the lab could eventually move from direct client CRUD to a server-owned replay contract.

Important honesty rule:

- backend delay in the current batch is still simulated acknowledgement delay at the client-owned remote seam, not a true server-owned execution delay

## Phase 3 - Expired auth

### Goal

Simulate session unavailability around sync.

### Why it fits before outbox work

The current coordinator and sync service already distinguish authenticated from unauthenticated behavior.
That makes expired-auth simulation possible without requiring operation replay semantics.

### Recommended first version

Start with session invalid before sync begins.

Do not start with mid-replay session expiry.

### Recommended implementation approach

Add a session-check seam so the effective sync path can behave as if the session no longer exists.

When `expiredAuth` is active:

- sync should be blocked as if no authenticated session were available
- runtime diagnostics should distinguish natural no-session state from injected no-session state

### Expected user-visible evidence

- diagnostics show `Waiting for Session`
- last result shows `Skipped`
- timeline includes an auth-fault injection event

### Recommended tests

- coordinator gating test for injected no-session state
- sync-service test with injected session unavailability
- widget tests for operator and diagnostics surfaces

### Planned later evolution

After the first version is stable, allow the scenario to expire auth after an early sync step so the lab can demonstrate a mid-flight transition later.

## Phase 4 - Network drop during partial replay

### Goal

Simulate a sync pass that begins, reaches a named internal step, and then loses connectivity.

### Why this should come after the simpler scenarios

This scenario is still compatible with the current architecture, but it requires explicit step naming inside the sync engine.
That makes it more complex than connectivity loss, delayed sync, and expired auth.

### Recommended implementation approach

Instrument the current sync engine with named step boundaries, such as:

- before delete replay
- after delete replay
- before dirty-task fetch
- after dirty-task fetch
- before remote merge fetch
- after remote merge fetch

Then allow a fault-injection policy to force connectivity loss at one named step.

### Expected user-visible evidence

- sync result becomes `Partial` or `Failed`, depending on the chosen handling
- timeline identifies the step where the drop occurred
- diagnostics preserve the final visible outcome instead of leaving only console noise

### Recommended tests

- service tests for step-triggered failure behavior
- integration-style test for partial replay interruption

### Important constraint

This still does not make the current sync engine a true operation-replay model.
It is a controlled task-based failure scenario and should be described that way.

## Phase 5 - Current prerequisites before deeper scenarios

The repository now has the first Objective 1 slice in place.
Before the lab implements duplicate replay and deeper conflict simulation, it should finish the next realism steps that make those scenarios honest end to end.

Recommended minimum follow-through from the current state:

1. extend delayed sync beyond the current full-pass local hold
2. define the backend idempotency contract for duplicate replay
3. decide how stronger retry and backoff behavior should appear in the shell and diagnostics
4. keep the sync state-machine docs aligned with the implemented client replay path
5. broaden integration-style coverage for offline create -> reconnect -> sync and richer replay failure scenarios

Without those slices, duplicate replay and deeper conflict simulation would still be more theatrical than educational.

## Phase 6 - Duplicate replay

### Goal

Demonstrate how the system behaves when the same logical operation is delivered more than once.

### Hard prerequisite

Do not implement this scenario until the lab has:

- operation ids or idempotency keys
- explicit outbox records
- a backend-side contract that can deduplicate or otherwise explain repeated delivery

### Recommended implementation direction

When the prerequisites exist:

- inject a duplicate send of the same operation id
- expose whether the backend deduplicated, rejected, or incorrectly re-applied it
- show that evidence in the runtime diagnostics and any future operation-state surface

## Phase 7 - First conflict simulation

### Goal

Demonstrate an update/update conflict after the outbox exists.

### Why update/update first

It is the simplest conflict to explain and observe in the current task domain.
Both sides still have visible values, so the educational story stays clear.

### Hard prerequisite

Do not implement this scenario until the lab has:

- explicit operation state
- a documented conflict policy
- visible ownership for conflict evidence in the shell
- a backend or protocol rule for conflict capture

### Recommended implementation direction

Inject divergence so the local update is no longer reconcilable as a simple stale-local replacement case.

The first conflict slice should prioritize:

- clear capture of the conflict
- clear evidence of local and remote versions
- educational clarity over a fully featured resolution workflow

## Phase 8 - Worker-side fault injection

After the sync-side scenarios are established, extend the same experiment philosophy to the notify worker.

Recommended order:

1. delayed dispatch
2. provider failure
3. missed cron run
4. recovery on the next run
5. multi-subscription fan-out edge cases

This phase should follow the same rule as the client-side work:

- inject failures at real seams
- leave visible or queryable evidence behind
- do not describe worker auditability as solved until the relevant history exists

## Cross-cutting implementation guidance

### Architecture guidance

- keep fault-injection logic out of UI widgets except for control rendering
- inject failures through explicit policy objects or wrappers around real seams
- keep `TaskSyncCoordinator` responsible for orchestration and gating
- keep `TaskSyncService` or wrapped remote boundaries responsible for simulated transport and replay conditions

### Runtime evidence guidance

Every scenario should publish:

- scenario activation event
- scenario reset event
- scenario-specific message when it affects sync or auth behavior
- explicit final outcome in the diagnostics model

### UX guidance

- always show when a scenario is active
- make reset obvious and cheap
- keep the first version simple enough for live demos
- avoid making operators infer whether the system is naturally unhealthy or intentionally injected

### Documentation guidance

As each slice lands, update:

- `docs/ARCHITECTURE.md`
- `docs/EXPERIMENTS.md`
- `docs/TESTING_STRATEGY.md`
- `docs/README.md`

Update `docs/LOCAL_DEVELOPMENT.md` only if the manual workflow changes.

## Verification expectations

For each implementation slice, use the current repository commands:

- Flutter app verification: `Push-Location .\flutter-app; flutter test; Pop-Location`
- worker verification when applicable: `Push-Location .\notify-worker; yarn test; Pop-Location`

Minimum expected coverage per scenario slice:

- service or orchestration tests for injected behavior
- widget tests for the operator rail and diagnostics evidence where relevant
- integration-style coverage for multi-step scenarios when practical

## What can start immediately

The repository can start implementation now for:

- the fault-injection foundation slice
- connectivity loss
- delayed sync
- expired auth
- network drop during partial replay

## What should wait

The repository should wait for Objective 1 follow-through before implementing:

- duplicate replay
- update/update conflict simulation

In practical terms today, that means waiting for the next realism steps above rather than waiting for the initial outbox slice itself.

## Recommended next execution backlog

If the goal is to keep moving with the highest leverage and lowest semantic risk from the current repository state, the recommended next execution backlog is:

1. extend the delayed-sync state model with mode, target seam, and one-shot versus persistent behavior
2. refactor the sync service to expose named replay seams and a wrapped remote boundary for delay injection
3. implement transport-shaped delay at outbound replay seams on the outbox path
4. implement backend-shaped acknowledgement delay before entries transition from `sending` to `acknowledged`
5. extend the operator rail with mode, target, duration, and one-shot controls while keeping the current `5 s` local default
6. extend runtime diagnostics and workspace sync indicators with stage-aware delay evidence
7. add focused tests for local, transport, and backend delay placement plus the richer operator and diagnostics surfaces
8. document the shipped behavior honestly once the code lands

That sequence keeps the lab aligned with the current outbox replay model while making delayed sync a much stronger educational experiment.
