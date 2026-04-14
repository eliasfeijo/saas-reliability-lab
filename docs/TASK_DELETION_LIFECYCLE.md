# Task Deletion Lifecycle

## Purpose

This document explains the deletion semantics that are implemented today, why the anonymous-mode counter bug happened, and the recommended path toward a future archive or trash model.

## Problem that was fixed

Anonymous local tasks were previously handled with the same `SyncStatus.deleted` tombstone that authenticated cloud-backed tasks use for remote deletion replay.

That created a mismatch:

- anonymous tasks have no remote row to delete
- the tombstone stayed in local storage anyway
- some user-facing counters and review surfaces read the raw stored list rather than the active task set

The result was stale UI state after deleting an anonymous task:

- the queue could already be empty
- `Pending` could still show `1`
- `Task Scope` could still show `Total 1`
- `Anonymous Task Review` could still show `1`

## Implemented model

The app now uses two different deletion paths because the persistence guarantees are different.

### 1. Anonymous local-only task delete

Behavior now:

- remove the task from local storage immediately
- remove it from the queue immediately
- remove it from all active counters immediately
- do not create a tombstone because there is no remote row to reconcile

Why:

- there is nothing to replay against Supabase
- keeping a tombstone only creates stale local state and misleading review counts

### 2. Authenticated account task delete

Behavior now:

- mark the task as `SyncStatus.deleted`
- hide it from queue views and user-facing counts immediately
- keep the tombstone locally until sync confirms the remote delete
- let `TaskSyncService` replay the delete against Supabase

Why:

- authenticated tasks can already exist remotely
- the client still needs a durable local signal that a remote delete must be sent

## Active-state rule

All user-facing queue, scope, and anonymous-review surfaces now operate on active tasks only.

In practice that means:

- deleted tombstones are excluded from `tasks`
- deleted tombstones are excluded from `filteredTasks`
- deleted tombstones are excluded from total, pending, completed, today, and overdue counts
- deleted tombstones are excluded from anonymous-review counts

## Upgrade cleanup rule

Older builds may already have persisted anonymous deleted tombstones locally.

To clean that up safely, the local snapshot load path now prunes any task that is both:

- anonymous (`userId == null`)
- marked `SyncStatus.deleted`

This makes the fix self-healing after upgrade instead of only correcting newly deleted tasks.

## Recommended future direction: archive first, hard delete second

An archive or trash flow is still a good product direction, but it should not be implemented as a client-only patch on top of the current sync contract.

### Recommendation

Do not ship archive semantics until the backend and sync model can preserve them explicitly.

### Why not now

The current system still has these constraints:

- the Supabase `tasks` table has no archive lifecycle field
- the sync contract is task reconciliation, not an explicit operation outbox
- a local-only archive state would drift from remote truth and could resurrect tasks unexpectedly on the next merge

### Safe archive design to implement later

When the project moves to the outbox phase, the safer design is:

1. add an explicit lifecycle field locally and remotely, such as `active`, `archived`, and `pending_delete`
2. treat `Archive` as a reversible lifecycle change that syncs across devices
3. treat `Delete permanently` as a second explicit action from the archived or trash surface
4. replay lifecycle changes through a durable outbox instead of overloading task snapshots and tombstones
5. add restore and permanent-delete controls to the operator shell or a dedicated archived-task view

That model matches the user expectation behind a Windows-style trash flow without creating hidden divergence between local and remote state.

## Regression coverage added with this change

The codebase now covers this lifecycle with:

- provider-level tests for anonymous hard delete, legacy tombstone pruning, and authenticated tombstone visibility
- an integration-style UI flow test that exercises anonymous create -> delete and verifies the workspace and operator-rail counters return to zero
