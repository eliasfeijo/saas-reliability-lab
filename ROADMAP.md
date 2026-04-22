# Roadmap - SaaS Reliability Lab

## Purpose

This document recommends a short-to-long-term implementation direction for the repository based on:

- the current implemented behavior
- the existing documentation
- the current workflow and test surface

It is intentionally a planning document, not a promise of already-committed scope.
Where the repository does not yet document a firm product or architecture decision, this roadmap calls that out explicitly instead of assuming it.

## Current baseline

What the repository already implements today:

- a Flutter web-first lab shell with three durable surfaces:
  - Operator Rail
  - Task Workspace
  - Runtime Diagnostics
- local-first task creation and editing with SharedPreferences persistence
- Supabase auth and per-user task sync
- runtime evidence for connectivity, auth, sync, push, and local task counts
- browser push subscription save and removal flows
- scheduled notification dispatch through an independently deployable Cloudflare Worker
- separate repository verification and deployment workflows

What is still explicitly missing across the current docs and source:

- durable outbox semantics
- per-operation retry, acknowledgement, and failure state
- explicit conflict capture and resolution
- broader structured logging and metrics
- fault-injection controls
- deeper automated coverage for reliability-critical paths
- CI/CD gating that prevents deploy workflows from racing repository verification

## Planning principles

This roadmap follows the repo's current documented framing:

1. **Stay a reliability lab first.** The task domain should keep serving observability and experimentation, not expand into generic productivity scope.
2. **Make system behavior explicit before making it broader.** Outbox, conflict, retry, and audit semantics are a higher-value next step than new UI churn.
3. **Prefer implemented evidence over aspirational claims.** New docs, tests, and UI states should describe only what is actually wired.
4. **Preserve deploy-surface independence where it already exists.** Frontend and notify worker should remain independently deployable unless that contract is intentionally changed.
5. **Treat verification as a trust boundary.** The repo should keep strengthening `verify.yaml` rather than relying on deployment success as proof of correctness.

## Short term

### Objective 0: completed foundation cleanup before deeper reliability semantics

Completed now:

- the visible lab shell stayed stable while the app moved onto clearer interaction, mutation, task-list state, sync-flow, and sync-entry seams
- backend and scheduled-delivery boundaries are now documented explicitly enough for the next phase
- Objective 0 now closes as a historical record and handoff in [`docs/archive/OBJECTIVE_0_FOUNDATION_PLAN.md`](docs/archive/OBJECTIVE_0_FOUNDATION_PLAN.md)

What this means:

- Objective 1 is now the next active implementation focus
- Objective 0 should only be reopened if later changes regress the completed foundation seams

Recommended focus:

- review the current architecture as a transitional baseline rather than a structure to preserve wholesale
- refactor the codebase toward a cleaner and more explicit system boundary between UI shell, local state, sync orchestration, backend contract, and scheduled delivery
- remove or reduce structural debt that would make later outbox, conflict, observability, and experiment work harder to implement cleanly
- redesign weak seams that are already documented as limiting the lab, especially where the current architecture mixes convenience, prototype shortcuts, and future-facing placeholders

High-value areas to address before outbox work:

- clarify service and provider ownership so UI-facing state, orchestration, and persistence responsibilities are less entangled
- reduce dependence on task-shaped sync assumptions that leak into parts of the app expected to evolve toward operation-based behavior
- identify which current abstractions are worth preserving and which should be replaced before they become harder migration constraints
- tighten the documented system model around current flaws in local persistence, sync auditability, conflict handling, and backend boundaries
- remove misleading or overly transitional structure where it creates false confidence about the current architecture

Why this comes first:

- the shell direction is strong, but the underlying architecture is still transitional
- the repo already documents important design gaps beyond outbox semantics
- a foundation pass can add substantial value by making the next objectives cleaner, safer, and more coherent
- this project benefits more from a deliberate architecture reset now than from layering explicit outbox behavior on top of weak seams

Concrete outcomes to target:

- a clearer target architecture for the Flutter app, backend surface, and notify worker
- a documented list of current design flaws and which ones should be refactored immediately versus deferred
- a cleaner dependency and responsibility map for providers, services, repositories, and backend integration points
- a more stable base for later outbox, conflict, observability, and fault-injection work
- reduced structural coupling between prototype-era assumptions and the next reliability-lab phases

The completed Objective 0 execution record and the active Objective 1 plan now live in [`docs/archive/OBJECTIVE_0_FOUNDATION_PLAN.md`](docs/archive/OBJECTIVE_0_FOUNDATION_PLAN.md) and [`docs/phases/OBJECTIVE_1_OUTBOX.md`](docs/phases/OBJECTIVE_1_OUTBOX.md).

### Objective 1: make sync semantics explicit

This is now the next active objective.

Recommended focus:

- define the local outbox model
- define operation types and per-operation states
- map those states onto the shell surfaces that already reserve room for them
- document the sync and auth state machines that the current docs still call out as missing

Why this follows Objective 0:

- the biggest remaining gap after foundation cleanup is semantic, not visual
- future experiments, testing, and observability all depend on a real operation model
- the outbox should land on top of a cleaner architecture instead of becoming the mechanism that freezes transitional design debt

Concrete outcomes to target:

- explicit local mutation records instead of only dirty-task replay
- operation states such as queued, sending, acknowledged, failed, and conflict
- a documented ownership model for where pending, blocked, failed, and conflicted work appears in the UI
- diagrams that explain current and target sync behavior honestly

### Objective 2: strengthen observability around current behavior

Recommended focus:

- add structured logs for sync attempts, edge-function subscription flows, and worker runs
- define the minimum useful audit surfaces for sync and delivery outcomes
- keep the in-app diagnostics rail as the user-visible evidence layer, not the only evidence layer

Concrete outcomes to target:

- clearer sync and worker run summaries
- enough backend-side evidence to explain a failed or partial scenario after the fact
- a documented path toward correlation across client, backend, and worker events

### Objective 3: close the highest-value test gaps around existing surfaces

Recommended focus:

- targeted widget coverage for `LabLeftRail`
- targeted widget coverage for `SyncDebugPanel`
- integration coverage for offline create -> reconnect -> sync
- auth/session divergence coverage
- broader worker cases beyond the current success and stale-subscription cleanup paths

Why now:

- current docs are ahead of current verification depth
- these tests protect the reliability-lab identity that the repo already exposes

## Medium term

### Objective 4: replace transitional sync with a real reliability contract

Recommended focus:

- implement the durable outbox end to end
- add idempotency keys or operation identifiers
- define retryable versus terminal failures
- preserve richer task field fidelity through the sync path
- make partial replay and blocked replay inspectable

Concrete outcomes to target:

- resume-safe replay after refresh or restart
- operation-safe duplicate handling
- user-visible blocked, failed, and conflicted work
- a sync path suitable for repeatable experiments instead of best-effort inference

### Objective 5: strengthen the backend for auditability and experimentation

Recommended focus:

- choose and document the long-term sync surface:
  - Supabase RPC
  - Edge Function
  - separate backend service
- add audit tables such as sync events or mutation logs
- add delivery-attempt history for notifications
- add device identity where multi-device experiments require it
- define notification semantics explicitly instead of leaving them implied

This phase needs explicit decisions before implementation:

- what the backend sync boundary should be
- whether conflicts are rejected, merged, or resolved through a user workflow
- what notification guarantee the lab is trying to model:
  - best-effort
  - at-least-once
  - at-most-once

Those decisions are not documented as settled today, so they should be made deliberately before deeper backend work lands.

### Objective 6: improve CI/CD trust without collapsing deploy independence

Recommended focus:

- keep `verify.yaml` as the trust workflow
- stop deploy workflows from racing verification on the same commit
- prefer pull-request and branch-protection gating over direct-push assumptions for `master`

Recommended target shape:

- verification runs first
- frontend deploy waits on relevant verification
- worker deploy waits on relevant verification
- frontend and worker remain logically separate deploy surfaces

## Long term

### Objective 7: turn the repo into a controlled experiment harness

Recommended focus:

- add fault-injection controls to the operator rail
- make failure scenarios intentionally triggerable
- define expected evidence for each scenario in both UI and backend signals
- reduce the manual-only experiment surface over time

Concrete scenarios already suggested by the docs:

- duplicate replay after reconnect
- auth expiry during replay
- update/delete race across devices
- concurrent edit conflict across devices
- partial replay followed by connectivity loss
- stale subscription cleanup and re-registration
- missed cron runs and recovery

### Objective 8: improve runtime realism

Recommended focus:

- move beyond SharedPreferences when the outbox and local inspection model need stronger persistence
- add more realistic partial-sync, reconnect-burst, and notification-failure behavior
- improve deployed-environment promotion discipline once the repo grows beyond a single public demo model

This should happen after the semantic model is strong enough to observe those conditions honestly.

### Objective 9: polish the repository as a public engineering artifact

Recommended focus:

- add operator runbooks for common failures
- keep README and deep docs aligned to implemented reality
- improve the quick-start path for reviewers and contributors
- add public-facing assets only after the core scenarios are stable and reproducible

## Recommended sequence

If the goal is the highest-leverage path from the current state, the recommended order is:

1. refactor and simplify the system foundation around a clearer target architecture
2. define the outbox model and operation states
3. document sync and auth state machines
4. add structured logging and audit-oriented evidence
5. expand tests around the current shell and runtime surfaces
6. implement the backend contract needed for idempotency, conflict handling, and delivery history
7. gate deploys behind verification while preserving frontend/worker independence
8. add fault injection and broader experiment scenarios
9. improve runtime realism and public-artifact polish

## Clear near-term objectives

The clearest next objectives, based on the repo's current state, are:

| Priority | Objective                                                           | Why it matters now                                                                                                                   |
| -------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| 0        | Refactor the system foundation toward a cleaner target architecture | The current shell is ahead of the underlying structure, and fixing major seams first will raise the quality of every later objective |
| 1        | Define the sync outbox model                                        | It unlocks explicit replay, retries, conflicts, and better diagnostics                                                               |
| 2        | Decide shell ownership for outbox and conflict states               | The UI has placeholders, but not yet a committed interaction model                                                                   |
| 3        | Add structured sync and worker observability                        | The lab needs evidence beyond transient in-app state                                                                                 |
| 4        | Expand high-value tests                                             | The current shell and diagnostics need stronger regression protection                                                                |
| 5        | Tighten CI/CD trust                                                 | The repo documents that deploys currently race verification                                                                          |

## Explicit non-goals for now

This roadmap does **not** recommend prioritizing:

- broad task-product feature expansion unrelated to reliability behavior
- another major shell redesign before outbox work
- coupling worker deployment to every frontend change
- claiming multi-device conflict behavior before the backend and UI contracts exist

## Decision points that should be made explicitly

These are the main choices the current repository documents as open or still transitional:

1. **Sync contract surface:** should long-term mutation replay go through RPCs, Edge Functions, or another backend boundary?
2. **Conflict policy:** should conflicts be rejected, merged automatically, or surfaced for explicit user resolution?
3. **Notification semantics:** is the lab modeling best-effort, at-least-once, or at-most-once delivery?
4. **Persistence evolution:** when should SharedPreferences give way to a stronger local storage model for outbox durability and inspection?
5. **Deployment trust model:** when should the repo move from parallel post-push deploys to verified-then-deploy orchestration?

Those decisions do not all need to be made immediately, but the medium-term work should not silently assume answers that the repo has not yet committed to.
