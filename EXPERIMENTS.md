# Experiments - SaaS Reliability Lab

## Purpose

This document defines the reliability scenarios the lab is intended to demonstrate.

The experiments are split into two groups:

- scenarios that can already be exercised meaningfully with the current codebase
- scenarios that are part of the target lab roadmap but still require more infrastructure, observability, or sync semantics

Each experiment is written as an engineering exercise, not a product feature.

## Experiment Format

Each experiment should eventually have:

- objective
- setup
- action
- expected behavior
- expected evidence
- current gaps

The "expected evidence" section is important. A reliability experiment is only complete when the system leaves behind enough information to explain what happened.

## Currently Runnable Experiments

## 1. Anonymous local work before login

### Objective

Verify that a user can create tasks locally without authentication and later decide whether to keep or discard that local work after signing in.

### Setup

- open the app with no active session
- create one or more tasks locally

### Action

- sign in

### Expected behavior

- the app restores the authenticated user id
- the app runs a full sync pass for the authenticated account
- if local anonymous tasks still exist, the app shows a decision dialog
- choosing `Keep` assigns the current user id to those tasks and syncs them
- choosing `Discard` removes them from local storage

### Current evidence

- visible dialog in the UI
- resulting task state in the list after the choice

### Current gaps

- no audit trail of which anonymous tasks were adopted
- no explicit conflict handling if remote tasks already represent similar work

## 2. Remote-wins on stale local state

### Objective

Verify that a stale local dirty task does not overwrite a fresher remote version.

### Setup

- create a task with the same id locally and remotely
- ensure the remote copy is newer than the local `lastModifiedAt`

### Action

- run the sync path

### Expected behavior

- the local stale copy is replaced by the remote canonical copy
- the stale local copy is not pushed back over the fresher remote state

### Current evidence

- automated Flutter regression test in `test/widget_test.dart`
- debug log line: `Remote task <id> is newer or equal. Keeping remote version.`

### Current gaps

- no explicit `conflict` state is shown in the UI
- the user is not told that a local edit was discarded in favor of remote state

## 3. Scheduled notification dispatch

### Objective

Verify that due tasks can be dispatched by backend infrastructure without requiring an active client session.

### Setup

- sign in in a browser that supports web push
- register a subscription for the current profile
- create a task whose `notify_at` will become due

### Action

- wait for the scheduled worker run

### Expected behavior

- the worker fetches due notifications
- a push request is sent to the provider
- the task is marked with `notification_sent = true` if the provider accepts it
- the browser service worker shows the notification

### Current evidence

- notification arrives in the subscribed browser profile
- worker logs show pending count and send outcome

### Current gaps

- no delivery-attempt history table
- no UI for last notification attempt or delivery status
- current cadence is cron-based and coarse at 5 minutes

## 4. Stale subscription cleanup

### Objective

Verify that dead push subscriptions are removed when the provider reports them as gone.

### Setup

- use a push subscription that has become invalid or simulate a `404` or `410` response in tests

### Action

- run the scheduled worker or on-demand sender against that subscription

### Expected behavior

- push send fails
- the worker deletes the stale subscription from persistence
- the send run reports one failed send and one stale subscription deletion

### Current evidence

- automated worker test in `@backend/agenda-notify-worker/test/index.spec.ts`
- worker logs show failed push and stale-subscription cleanup count

### Current gaps

- no separate metric or dashboard for churn in subscriptions
- no user-facing prompt to re-register after cleanup

## 5. Per-profile notification fan-out

### Objective

Verify that multiple active browser profiles for the same account can each receive the same due notification.

### Setup

- sign in as the same user in two or more browser profiles
- allow push permission in each profile

### Action

- create a due task for that account

### Expected behavior

- each still-valid subscription for that user receives a push attempt
- multiple profiles can receive the same reminder

### Current evidence

- observable in the live browser behavior
- reflected implicitly by multiple `push_subscriptions` rows

### Current gaps

- no admin/debug view listing active subscriptions per account

## Planned Experiments That Need More Infrastructure

## 6. Duplicate operation replay after reconnect

### Goal

Study whether repeated delivery of the same local mutation creates duplicate or inconsistent remote state.

### Why it matters

This is one of the central SaaS reliability concerns described in the README.

### What is still needed

- durable outbox
- idempotency keys or operation ids
- server-side idempotency handling

## 7. Auth expiry during sync replay

### Goal

Study how queued local work behaves when the user session expires during replay.

### What should be answered

- are operations retried later?
- does the UI surface blocked sync clearly?
- what happens to push subscription management during auth churn?

### What is still needed

- explicit outbox state
- auth-expired sync state
- better UI/debug evidence

## 8. Update/delete race across devices

### Goal

Study what happens when one device deletes a task while another device updates it.

### What is still needed

- explicit conflict state
- either versioning or richer reconciliation rules
- deterministic experiment setup tools

## 9. Concurrent edit conflict across devices

### Goal

Study whether concurrent edits converge correctly and visibly.

### Current limitation

The app currently has only a simple timestamp-based remote-wins rule and no explicit user-visible conflict resolution.

### What is still needed

- conflict capture
- conflict display
- decision or merge strategy

## 10. Network drop during mutation replay

### Goal

Study how the client behaves when a sync pass partially succeeds and then loses connectivity.

### What is still needed

- explicit retry policy
- partial-success recording
- local operation queue

## 11. Missed worker run and delayed notification recovery

### Goal

Study whether missed schedules are recovered correctly on the next worker execution.

### What is still needed

- worker heartbeat or last-run record
- notification attempt history
- scenario controls for intentionally skipped runs

## 12. Notification provider degradation

### Goal

Study the difference between temporary provider failure, permanent endpoint loss, and delayed acceptance.

### What is still needed

- retry policy for notification sends
- dead-letter or failed-attempt persistence
- outcome classification

## 13. Large reconnect burst

### Goal

Study how the system behaves when a user returns online with many queued local changes.

### What is still needed

- durable outbox
- batching semantics
- rate limiting and backoff
- sync metrics

## 14. Session divergence across devices

### Goal

Study whether one device signing out, expiring, or reauthenticating leaves other devices in a consistent or confusing state.

### What is still needed

- device identity tracking
- session-event visibility
- test harness for multi-device auth scenarios

## Experiment Readiness Checklist

An experiment should only be considered truly implemented when all of the following are true:

- [ ] the scenario can be triggered intentionally
- [ ] the expected behavior is documented
- [ ] the actual behavior is observable in logs, UI, or stored evidence
- [ ] the scenario has at least one automated test where practical
- [ ] the repository explains known limitations of the scenario clearly

## Immediate Next Experiments To Stabilize

These are the best next candidates because they align with the current codebase and improve the lab fastest:

1. duplicate replay after reconnect
2. auth expiry during sync replay
3. update/delete race across devices
4. missed worker run and delayed recovery
5. large reconnect burst

## Final Goal

The point of these experiments is not to prove that the system never fails.

The point is to make failure:

- intentional
- repeatable
- explainable
- testable

Once that is true, the repository becomes a real reliability lab instead of a reliability-themed app.