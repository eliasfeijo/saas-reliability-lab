# Objective 1 Outbox Entry Plan

## Purpose

This document is the active entry plan for **Objective 1**.

Objective 0 is complete.
The next phase is to make sync semantics explicit without reopening foundation cleanup unless the new seams prove insufficient.

The execution-ready follow-through for this phase now lives in [`OBJECTIVE_1_OUTBOX_EXECUTION_PLAN.md`](OBJECTIVE_1_OUTBOX_EXECUTION_PLAN.md).

## Starting point inherited from Objective 0

Implemented now:

- `AgendaProvider` remains the single widget-facing task facade
- `TaskWorkspaceInteractionController` owns interaction and view-state rules
- `TaskMutationCoordinator` owns task mutation rules
- `TaskListStateCoordinator` owns provider-facing snapshot persistence and task-count publication
- `TaskSyncFlowCoordinator` owns provider-facing sync sequencing for persisted mutations and anonymous-task keep/discard flows
- `TaskSyncCoordinator` owns sync-entry checks and post-sync reload behavior
- `TaskSyncGateway` is the app-facing sync contract, with `TaskSyncService` as the current transitional implementation
- backend and worker docs now distinguish direct task CRUD, subscription Edge Functions, and worker-facing RPC behavior clearly

## Goal

Turn the current task-shaped sync behavior into an explicit outbox-oriented contract without destabilizing the visible lab shell.

## Entry conditions

Objective 1 should start from these assumptions:

- the current shell stays visually stable unless an outbox or conflict state needs deliberate new UI ownership
- new semantics should land on the completed Objective 0 seams rather than bypass them
- the long-term backend mutation surface is still an open decision and must be documented deliberately when chosen

## Decisions now fixed for the first execution slice

The following decisions are now fixed for the first Objective 1 slice and should be treated as the planning contract for implementation:

1. keep direct `tasks` table CRUD temporarily as the backend mutation boundary
2. keep SharedPreferences as the transitional local persistence layer for this first slice
3. use a generic first operation model of `upsert` and `delete`
4. compact local edits to the latest effective operation per task before replay
5. replay operations FIFO by the earliest surviving operation timestamp
6. capture conflicts explicitly and block replay for those entries until the operator resolves them
7. make `Runtime Diagnostics` the primary home for outbox evidence and `TaskWorkspace` the secondary home for task-scoped indicators
8. preserve the existing anonymous keep-or-discard review gate, but represent anonymous work as blocked outbox entries immediately
9. keep missing-session replay blocking for interrupted sync paths, but continue clearing the local workspace on explicit sign-out so user-bound tasks do not leak across sessions

The detailed rationale, implementation sequence, file map, and verification plan now live in [`OBJECTIVE_1_OUTBOX_EXECUTION_PLAN.md`](OBJECTIVE_1_OUTBOX_EXECUTION_PLAN.md).

## Recommended first execution slices

1. Add explicit outbox models, storage, and migration from the current dirty-task semantics.
2. Refactor local mutation flow so each task change updates both the visible projection and the outbox.
3. Replace task-shaped replay with FIFO outbox replay and explicit blocked, failed, acknowledged, and conflict states.
4. Turn the diagnostics placeholders into real outbox evidence and add task-scoped conflict or failure visibility in the workspace.
5. Add the first outbox-focused verification path, starting with migration, replay ordering, conflict handling, and offline create -> reconnect -> sync.

## Why Objective 1 matters for delayed-sync realism

The current delayed-sync scenario is intentionally a first-slice demonstration.
It delays the sync pass before remote replay begins, which is viewer-friendly and honest to the current task-based engine, but it does not yet simulate a true transport or backend slowdown.

Objective 1 is the architectural step that changes that.

Once the outbox exists, the lab can delay real operation states such as:

- queued operations waiting to leave the client
- sending operations whose backend acknowledgement is late
- partially acknowledged batches where one operation completes and another remains pending

That evolution matters because it lets the lab show a more realistic SaaS symptom: the local mutation is already durable in the client, but remote truth is still behind because transport or backend work has not finished yet.

## Verification baseline

Use the existing repo verification commands:

- Flutter app verification: `Push-Location .\flutter-app; flutter test; Pop-Location`
- worker verification: `Push-Location .\notify-worker; yarn test; Pop-Location`

## Related docs

- [`OBJECTIVE_0_FOUNDATION_PLAN.md`](OBJECTIVE_0_FOUNDATION_PLAN.md)
- [`OBJECTIVE_1_OUTBOX_EXECUTION_PLAN.md`](OBJECTIVE_1_OUTBOX_EXECUTION_PLAN.md)
- [`ARCHITECTURE.md`](ARCHITECTURE.md)
- [`TESTING_STRATEGY.md`](TESTING_STRATEGY.md)
- [`../ROADMAP.md`](../ROADMAP.md)
