# Objective 1 - Explicit Outbox

Status: active phase plan

## Purpose

This document is the single active planning surface for Objective 1.

Objective 0 is complete.
The next phase is to replace transitional task-shaped sync behavior with an explicit outbox contract without destabilizing the lab shell.

This document consolidates the former Objective 1 entry plan and execution plan into one place so the active phase has a single reference.

## Starting point

Implemented now:

- `AgendaProvider` remains the single widget-facing task facade
- `TaskWorkspaceInteractionController` owns interaction and view-state rules
- `TaskMutationCoordinator` owns task mutation rules
- `TaskListStateCoordinator` owns provider-facing snapshot persistence and task-count publication
- `TaskSyncFlowCoordinator` owns provider-facing sync sequencing for persisted mutations and anonymous-task review flows
- `TaskSyncCoordinator` owns sync-entry checks and post-sync reload behavior
- `TaskSyncGateway` is the app-facing sync contract, with `TaskSyncService` as the current transitional implementation
- the client already exposes runtime evidence through the lab shell and replays an explicit local outbox on the current direct-CRUD boundary

Historical context for the finished foundation work now lives in [`../archive/OBJECTIVE_0_FOUNDATION_PLAN.md`](../archive/OBJECTIVE_0_FOUNDATION_PLAN.md).

## Goal

Turn the current sync semantics into an explicit outbox-oriented contract that is visible, testable, and honest about its current limits.

## Fixed planning decisions

These decisions are the current planning contract for Objective 1:

1. Keep direct `tasks` table CRUD temporarily as the backend mutation boundary.
2. Keep SharedPreferences as the transitional local persistence layer for this slice.
3. Use a generic first operation model of `upsert` and `delete`.
4. Compact local edits to the latest effective operation per task before replay.
5. Replay operations FIFO by the earliest surviving operation timestamp.
6. Capture conflicts explicitly and block replay for those entries until the operator resolves them.
7. Keep `Runtime Diagnostics` as the primary home for outbox evidence and `TaskWorkspace` as the secondary home for task-scoped indicators.
8. Preserve the anonymous keep-or-discard review gate, but represent anonymous work as blocked outbox entries.
9. Continue clearing the local workspace boundary on explicit sign-out so user-bound tasks do not leak across sessions on a shared device.

## Current implementation boundary

Objective 1 already has a meaningful first slice in place, but the repository is still operating within these limits:

- the replay model is client-owned, not server-owned
- direct client CRUD still limits how far delay, idempotency, and backend-shaped replay can go honestly
- SharedPreferences remains a transitional durability layer
- acknowledgement evidence is retained locally as bounded history rather than as a stronger backend audit trail

## Target behavior for this phase

After Objective 1 is complete, the repository should have:

1. immediate local projection updates for task mutations
2. an explicit outbox entry set updated alongside the visible task projection
3. outbox-driven replay instead of task-diff heuristics
4. user-visible blocked, queued, sending, acknowledged, failed, and conflict states
5. a clear anonymous review gate on blocked outbox work
6. focused verification around migration, replay ordering, conflict handling, and reconnect behavior

## Execution slices

### 1. Solidify the outbox model

- keep `upsert` and `delete` as the first operation verbs
- preserve per-entry state such as queued, sending, acknowledged, failed, blocked, and conflict
- keep compaction rules explicit and documented

### 2. Make replay authoritative

- drive replay from outbox entries rather than task-diff inference
- keep FIFO ordering by earliest surviving operation timestamp
- treat conflict as an explicit state, not a hidden overwrite decision

### 3. Keep the UI honest

- expose outbox evidence primarily in `Runtime Diagnostics`
- keep task-scoped failure or conflict visibility in `TaskWorkspace`
- avoid another shell redesign while these semantics land

### 4. Expand focused verification

- migration and initialization coverage
- replay ordering coverage
- blocked-session and anonymous-review coverage
- conflict detection and conflict-action coverage
- offline create -> reconnect -> sync coverage

## Verification baseline

Use the existing repository validation commands:

- Flutter app verification: `Push-Location .\flutter-app; flutter test; Pop-Location`
- worker verification: `Push-Location .\notify-worker; yarn test; Pop-Location`

## Related docs

- [`../archive/OBJECTIVE_0_FOUNDATION_PLAN.md`](../archive/OBJECTIVE_0_FOUNDATION_PLAN.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../TESTING_STRATEGY.md`](../TESTING_STRATEGY.md)
- [`../guides/FAULT_INJECTION.md`](../guides/FAULT_INJECTION.md)
- [`../../ROADMAP.md`](../../ROADMAP.md)