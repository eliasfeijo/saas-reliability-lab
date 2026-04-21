# Delayed Sync Execution Plan

## Purpose

This document started as the execution-ready batch plan for delayed-sync fault injection.
It now records the implemented batch plus the remaining follow-up boundary work.

It assumes the repository already has the first Objective 1 outbox slice in production.
It does not describe Objective 1 as future work.

The goal of this batch is to evolve delayed sync from a single client-owned pre-replay hold into a clearer experiment surface with operator-selectable local, transport-shaped, and backend-shaped delay simulation.

## Implemented state

Implemented today:

- the Flutter client already replays an explicit local outbox with `queued`, `sending`, `acknowledged`, `failed`, `conflict`, `blockedNoSession`, and `blockedAnonymousReview` states
- runtime diagnostics already expose outbox counts, conflict evidence, recent acknowledgements, and sync outcome history
- fault injection now supports delayed sync with `500 ms`, `2 s`, `5 s`, and `10 s` presets, operator-selectable `local`, `transport`, and `backend` modes, and `persistent` or `one-shot` behavior
- the operator rail now opens a delayed-sync setup modal with a recommended `local` + `5 s` + `persistent` fast path and exposes the active configuration after activation
- the sync runtime now applies stage-aware delay injection at explicit outbox replay seams such as full-pass hold, outbound update, and acknowledgement hold, and keeps `Syncing` visibly active during the hold
- the runtime diagnostics rail and event timeline now expose the active delay mode, target seam, behavior, and injected delay label for the current delayed-sync slice
- the sync runtime now refreshes replay input after a delayed full-pass hold before any remote work starts, and preserves newer local mutations staged during an in-flight pass as queued follow-up work with explicit event-timeline evidence

Current implementation boundary:

- the shipped delayed-sync slice is still client-owned inside `TaskSyncService` and the current replay seam hooks
- the `transport` and `backend` modes are honest client-side simulations on the explicit outbox replay path, not a true server-owned execution contract
- a future server-owned mutation boundary is still required before the repository can claim real backend execution delay or backend-owned replay semantics

## Recommended mitigation for concurrent local mutations

Given the current repository state, the recommended mitigation is:

1. if the delay happens before remote replay starts, reload the latest local task-plus-outbox state and use that refreshed input for the same pass
2. if a newer local mutation lands after replay is already in flight, preserve that newer intent locally as queued outbox work instead of trying to fold it into the active pass
3. write an explicit event-timeline record when either handling path occurs so operators can see that replay input was refreshed or deferred rather than assuming the runtime ignored the change
4. surface a follow-up sync notice when preserved queued work remains so the operator can intentionally run the next pass

Why this is the right mitigation now:

- it preserves the repo's local-first interaction contract instead of freezing local edits while replay is running
- it avoids pretending that the current client-owned replay seam can safely absorb newer writes into an already-running remote operation
- it matches the current Objective 1 boundary: explicit local outbox evidence first, stronger server-owned mutation execution later

What this mitigation does not claim yet:

- it does not provide a true backend-owned mutation queue
- it does not guarantee that a later local mutation will be replayed in the same pass once remote work has already started
- it still relies on a follow-up replay pass, which is an honest limitation until the repository adopts a stronger server-owned mutation boundary or a dedicated pending-resync handoff

## Desired state

This batch should turn delayed sync into a structured experiment with three operator-selectable modes:

1. `local`: hold the replay pass before any remote work begins
2. `transport`: delay the outbound remote call path around replay operations so entries remain visibly `sending` longer
3. `backend`: simulate slow acknowledgement after a remote call succeeds but before the outbox entry transitions to `acknowledged`

The operator should be able to:

- choose the delay mode
- choose a duration preset
- optionally choose whether the delay is one-shot or persistent for the active pass
- see explicit evidence for which seam is currently paused and which task or outbox entry is affected when practical

The outbox replay path is the primary target for this batch.
The older legacy sync path should not drive the design.

## Batch decisions

These decisions are the recommended contract for this batch.

### 1. Keep single-active scenario behavior

Do not turn this batch into combinable multi-scenario fault injection.

Why:

- the current operator experience is built around one active scenario
- the diagnostics model is not yet designed to explain stacked failures cleanly
- the repo will get more educational value from better per-scenario evidence before adding scenario composition

### 2. Keep the current default delayed-sync behavior

When the operator activates delayed sync, default to:

- mode: `local`
- preset: `5 s`
- behavior: persistent within the current pass unless a one-shot option is explicitly selected

Why:

- this preserves the current live-demo cadence
- it avoids turning the new batch into a breaking change for existing walkthroughs

### 3. Define backend delay honestly

For this batch, backend delay should mean simulated acknowledgement delay at the client-owned remote seam.

It should not be documented as true server-side execution delay unless the repository also introduces a new backend-owned mutation boundary later.

Why:

- the current app still performs direct CRUD from the client to Supabase
- a fake `Future.delayed` after a successful remote call can still teach the right operator-visible lesson without pretending the backend contract changed

### 4. Use the outbox replay path as the primary implementation surface

The richer delayed-sync modes should be defined against explicit replayable outbox entries and their state transitions.

That is now the implemented contract. The repository no longer preserves a legacy task-shaped replay fallback for delayed-sync behavior.

### 5. Include the approved improvements in this batch

This batch should include:

- a one-shot versus persistent toggle
- stage-aware diagnostics that name the delayed seam rather than only showing a generic sync hold
- a narrow target selector for transport and backend modes so the operator can focus the experiment on a specific replay stage
- richer event payload metrics such as delay mode, target stage, and affected task or entry when available

## Constraints and risks

### 1. Direct client CRUD still limits how far backend simulation can go

The repository does not yet have a backend-owned replay API for task mutations.
That means this batch can simulate backend acknowledgement delay honestly at the client seam, but it cannot claim that the actual backend execution path is delayed.

### 2. Runtime evidence needs to become more structured

The current runtime debug state stores fault-injection evidence mostly as label, message, and instruction text.
That is enough for the current first slice, but not enough for:

- delay mode
- targeted replay stage
- active entry or task identity
- one-shot versus persistent behavior
- precise remaining hold state

### 3. The replay code is still client-owned

`TaskSyncService` now applies all delayed-sync modes on the coordinated outbox replay path.

The remaining limitation is not a legacy fallback path. It is the lack of a server-owned mutation boundary.

### 4. UI complexity needs to stay operator-friendly

The operator rail should remain understandable during demos.
If mode, target, one-shot, and duration controls are all added at once, the wording and defaults need to stay disciplined so the control surface still reads like a lab instrument rather than a debug dump.

## Recommended implementation surfaces

Primary existing files to evolve in `flutter-app/lib/`:

- `models/fault_injection_state.dart`
- `models/fault_injection_scenario.dart`
- `providers/fault_injection_provider.dart`
- `services/fault_injection_policy.dart`
- `services/task_sync_service.dart`
- `models/runtime_debug_state.dart`
- `providers/runtime_debug_provider.dart`
- `widgets/lab/lab_left_rail.dart`
- `widgets/debug/sync_debug_panel.dart`
- `widgets/lab/task_workspace.dart`

Likely tests to extend in `flutter-app/test/`:

- `fault_injection_provider_test.dart`
- `sync_logic_test.dart`
- `sync_debug_panel_test.dart`
- `lab_left_rail_test.dart`

## Recommended domain additions

### Delayed-sync mode

Add a dedicated delayed-sync mode model with these values:

- `local`
- `transport`
- `backend`

### Delayed-sync target

Add a narrow target model for replay-stage selection rather than a freeform string.

Recommended first targets:

- `fullPass`
- `fetchById`
- `insert`
- `update`
- `delete`
- `fetchAllMerge`
- `acknowledgement`

Mapping guidance:

- `local` mode should always support `fullPass`
- `transport` mode should target outbound read and mutation seams
- `backend` mode should target acknowledgement-oriented seams after remote success and before local acknowledgement is recorded

### Delivery behavior

Add a behavioral option for:

- `persistent`
- `oneShot`

The first implementation can keep `persistent` as the default so existing demos stay stable.

## Runtime evidence contract

The runtime model should grow beyond a generic active label and support at least:

- active scenario label
- delay mode
- delay preset and duration label
- active target seam
- whether the scenario is one-shot or persistent
- whether a hold is currently active
- the currently delayed task id or outbox entry id when relevant
- the last injected stage that affected replay

The event timeline should record:

- scenario activation
- mode or preset changes
- the specific replay seam where a delay was applied
- the task or outbox entry affected when available
- replay-input refresh when a full-pass hold ends with newer local state than the pass started with
- preserved queued follow-up work when newer local mutations land after replay is already in flight
- scenario reset

## Step-by-step plan

### 1. Extend the delayed-sync state model

Refactor the delayed-sync branch of fault-injection state so it can carry:

- mode
- target seam
- duration
- one-shot versus persistent behavior
- operator-oriented summary text derived from those fields

Keep the current `5 s` local hold as the default activation behavior.

### 2. Extend the policy layer

Teach `FaultInjectionPolicy` to answer more than one pre-replay duration.

It should expose structured decisions such as:

- whether local hold is active
- whether a transport delay applies at a specific replay seam
- whether backend acknowledgement delay applies after remote success
- whether the delay should consume itself after one use

### 3. Name the replay seams explicitly

Refactor `TaskSyncService` to define named internal replay seams for delay injection.

The first useful set is:

- before replay pass starts
- before remote fetch by id
- before remote insert
- before remote update
- before remote delete
- after remote mutation succeeds but before acknowledgement is recorded
- before final remote fetch-all merge

This naming should stay implementation-owned and testable rather than being hidden in widget copy.

### 4. Wrap the remote boundary for transport delay

This is implemented today through named replay-seam delay hooks inside `TaskSyncService` around `TaskRemoteDataSource` usage. The next refinement would be extracting those hooks into a dedicated seam wrapper only if the replay surface broadens enough to justify it.

### 5. Add acknowledgement-stage delay for backend simulation

Extend the outbox replay loop so a successful remote operation can remain visibly in `sending` while the runtime simulates delayed acknowledgement.

Only after that synthetic hold ends should the entry move to `acknowledged` and the success evidence settle.

### 6. Remaining follow-up

The remaining follow-up after this batch is not legacy compatibility work. It is the future backend-owned mutation-boundary design captured in `SERVER_OWNED_MUTATION_BOUNDARY_PLAN.md`.

The richer experiment contract should belong to the coordinated outbox replay path.

### 7. Expand runtime diagnostics state and events

Update runtime state and provider surfaces so the diagnostics rail can show:

- current delay mode
- current target seam
- whether the runtime is in a pre-replay hold, transport hold, or acknowledgement hold
- the current affected task or entry where practical
- richer event payload metrics tied to the delay application

### 8. Update the operator rail controls

Extend delayed-sync controls in the operator rail to include:

- mode selector
- target selector where relevant
- duration presets
- one-shot versus persistent toggle
- concise operator copy describing what each mode means in the lab

The UI should prefer clarity and defaults over configurability for its own sake.

### 9. Update the workspace and diagnostics surfaces

The workspace sync indicator and diagnostics rail should stop describing every delayed-sync case as one generic hold.

They should instead indicate whether the runtime is:

- waiting before replay starts
- delaying an outbound transport step
- delaying acknowledgement after remote success

### 10. Add focused automated coverage

Minimum expected test additions for this batch:

- provider tests for delayed-sync mode defaults, retuning, and one-shot behavior
- sync-service tests proving local, transport, and backend delay placement on the outbox replay path
- diagnostics widget tests for mode, target, and stage-aware evidence rendering
- operator-rail widget tests for selecting mode, target, duration, and one-shot behavior

### 11. Update planning and reference docs

When implementation lands, align the docs to the shipped behavior in:

- `docs/ARCHITECTURE.md`
- `docs/EXPERIMENTS.md`
- `docs/TESTING_STRATEGY.md`
- `docs/README.md`
- `docs/FAULT_INJECTION_PLAN.md`

## Verification expectations

Use the existing repository command for the Flutter surface:

- `Push-Location .\flutter-app; flutter test; Pop-Location`

This batch should add enough coverage to prove that the delay is being applied at the intended seam, not merely that some wait occurred somewhere during sync.

## Documentation follow-through

This execution plan is intentionally narrower than the full fault-injection roadmap in `FAULT_INJECTION_PLAN.md`.

Use this document when the goal is to execute the next delayed-sync slice specifically.
Use `FAULT_INJECTION_PLAN.md` for the broader scenario roadmap across connectivity loss, expired auth, partial replay drop, duplicate replay, conflict simulation, and worker-side fault injection.
