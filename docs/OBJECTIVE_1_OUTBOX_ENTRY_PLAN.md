# Objective 1 Outbox Entry Plan

## Purpose

This document is the active entry plan for **Objective 1**.

Objective 0 is complete.
The next phase is to make sync semantics explicit without reopening foundation cleanup unless the new seams prove insufficient.

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

## Most relevant open decisions

These are the decisions Objective 1 should answer explicitly:

1. what the long-term task mutation surface should be: direct table access retained temporarily, Supabase RPC, Edge Function, or another backend boundary
2. what local persistence upgrade is needed once the outbox requires stronger durability than the current snapshot store
3. what conflict policy the lab wants to model first: reject, merge, or explicit user resolution
4. what notification and sync guarantee language the lab wants to use once auditability improves

## Recommended first execution slices

1. Define the local outbox model and operation states.
2. Decide where queued, blocked, failed, and conflicted work appears in the shell.
3. Define the sync and auth state-machine language that the product and docs will use.
4. Add the first integration-style verification path for offline create -> reconnect -> sync.

## Verification baseline

Use the existing repo verification commands:

- Flutter app verification: `Push-Location .\flutter-app; flutter test; Pop-Location`
- worker verification: `Push-Location .\notify-worker; yarn test; Pop-Location`

## Related docs

- [`OBJECTIVE_0_FOUNDATION_PLAN.md`](OBJECTIVE_0_FOUNDATION_PLAN.md)
- [`ARCHITECTURE.md`](ARCHITECTURE.md)
- [`TESTING_STRATEGY.md`](TESTING_STRATEGY.md)
- [`../ROADMAP.md`](../ROADMAP.md)