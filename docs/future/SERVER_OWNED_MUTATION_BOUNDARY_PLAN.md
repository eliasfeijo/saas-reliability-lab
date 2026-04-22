# Server-Owned Mutation Boundary Plan

## Purpose

This document sketches the future-state plan for moving task mutation replay from direct client CRUD to a server-owned mutation boundary.

It is a forward-looking architecture sketch, not an implementation claim.

## Why this matters now

The repository now has:

- an explicit client-side outbox
- conflict capture and review on the client
- client-owned delayed-sync modes for local, transport, and backend-shaped acknowledgement experiments

That is enough to teach reliable client-side replay behavior.
It is not enough to claim true server-owned mutation execution, true backend delay simulation, or backend-owned idempotency.

## Current limitation

Today the task mutation contract is still:

1. the Flutter client replays outbox entries directly against the `tasks` table through the Supabase client
2. replay ordering, acknowledgement timing, and retry decisions are all client-owned
3. backend delay experiments are therefore only honest as client-owned acknowledgement delay, not as true backend execution delay

This is acceptable for the current reliability-lab phase, but it limits the next set of experiments.

## Desired future contract

The long-term target is a server-owned mutation gateway with these properties:

1. the client submits a mutation envelope rather than directly mutating `tasks`
2. the backend owns idempotency, mutation ordering rules, and acknowledgement semantics
3. the backend returns a mutation receipt that the client can reconcile against its outbox entry
4. delayed, duplicate, partial, and conflict scenarios can be modeled at a true backend contract boundary instead of only inside the client runtime

## Recommended mutation envelope

The first backend-owned contract should stay narrow.

Suggested envelope fields:

- mutation id
- task id
- operation type such as `upsert` or `delete`
- actor user id
- client timestamp and queued timestamp
- base remote version or updated-at marker when available
- task payload for `upsert`

The key requirement is that the backend can answer whether the mutation is:

- newly accepted
- already applied
- rejected as invalid
- blocked by a newer remote version

## Recommended backend responsibilities

The first server-owned mutation boundary should own:

1. idempotency keyed by mutation id
2. validation that the authenticated actor is allowed to mutate the task
3. optimistic concurrency checks against the supplied base version
4. mutation result receipts that the client can map back to an outbox entry

It should not try to solve every future workflow at once.

## Recommended implementation shape

The smallest honest first version is:

1. add a backend mutation endpoint using RPC or an Edge Function
2. keep the client outbox and client replay coordinator in place
3. replace direct table CRUD in the replay path with mutation-envelope submission
4. teach the client to acknowledge entries from backend receipts rather than from direct CRUD completion

This keeps the current client-side state-machine investment while moving the execution authority to the backend.

## Reliability-lab gains from this boundary

This boundary would make the following experiments more honest:

1. true backend execution delay rather than client-only acknowledgement delay
2. duplicate replay with backend idempotency evidence
3. partial replay where the backend accepts some mutations and rejects others with structured receipts
4. conflict scenarios that distinguish backend rejection from client-local inference

## Suggested rollout phases

### Phase 1

Introduce the mutation envelope and backend receipt contract for `upsert` and `delete`.

### Phase 2

Move duplicate replay and deeper conflict experiments onto that backend-owned contract.

### Phase 3

Consider whether replay batching, stronger local durability, or worker-assisted recovery flows are needed after the backend contract is proven.

## Non-goals for the first server-owned slice

- replacing the client outbox entirely
- introducing a full event-sourcing model
- redesigning the task domain around backend jobs before the mutation gateway is proven

## Verification expectations when this work starts

When this future slice begins, the repo should add:

1. backend contract tests for mutation receipts and idempotency
2. Flutter replay tests against the new receipt semantics
3. docs updates in `ARCHITECTURE.md`, `TESTING_STRATEGY.md`, and `guides/FAULT_INJECTION.md` that clearly separate implemented backend ownership from planned work
