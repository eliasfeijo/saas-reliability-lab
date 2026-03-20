# Experiments - SaaS Reliability Lab

## Purpose

This document defines the reliability scenarios the lab is meant to demonstrate and the evidence each scenario should leave behind.

The current shell transformation matters here.
Experiments are no longer expected to hide behind dialogs or console output alone.
They should be inspectable through the operator shell:

- `LabLeftRail` for durable controls and session context
- `TaskWorkspace` for direct task interactions
- `SyncDebugPanel` for runtime evidence

## Current experiment surface

What the UI can already expose today:

- authenticated versus anonymous session state
- cached identity versus live auth identity
- manual sync initiation from the operator rail
- sync lifecycle and last outcome summaries
- local dirty, deleted, and anonymous task counts
- push permission and subscription state
- recent runtime events in memory

What the UI intentionally reserves but does not yet truly implement:

- queued operations
- sending and acknowledged operation states
- failed operations with retry policy
- conflict capture and resolution
- fault injection controls

## Experiment format

Each experiment should eventually include:

- objective
- setup
- action
- expected behavior
- expected evidence
- current gaps

The evidence section is mandatory.
An experiment is not complete until the system leaves behind enough visible information to explain what happened.

## Currently runnable experiments

## 1. Anonymous local work before login

### Objective

Verify that a user can create tasks locally without authentication and later decide whether to keep or discard that work after signing in.

### Setup

- open the app with no active session
- create one or more tasks locally

### Action

- sign in

### Expected behavior

- the app restores the authenticated user id
- the app runs a full sync pass for the authenticated account
- if anonymous tasks still exist, the app offers an explicit decision path
- choosing `Keep` assigns the current user id to those tasks and syncs them
- choosing `Discard` removes them from local storage

### Expected evidence

- anonymous-task count is visible in the operator rail
- the login-time decision flow appears when needed
- the event timeline records the related auth and storage activity
- the resulting task state is visible in the workspace after the choice

### Current gaps

- no audit trail of exactly which tasks were adopted versus discarded
- no conflict-aware strategy if local anonymous work overlaps meaningfully with remote state

## 2. Session truth and startup recovery visibility

### Objective

Verify that the UI distinguishes cached identity from the actual authenticated session and shows startup recovery behavior clearly.

### Setup

- sign in
- refresh the page or relaunch the app with a stored session

### Action

- observe startup
- sign out again

### Expected behavior

- the app restores local snapshot and cached identity first
- the runtime model reflects initial-load activity
- Supabase auth remains the source of truth for authenticated state
- signed-out cleanup clears local session state and local tasks as designed

### Expected evidence

- `Session Truth` in the diagnostics rail shows active versus cached identity
- `Initial load` changes from running to settled
- auth-related runtime events appear in the event timeline
- the operator rail updates between anonymous and authenticated states

### Current gaps

- there is no persisted audit history of session transitions across reloads
- there is no separate incident trail for startup recovery anomalies

## 3. Manual sync visibility for authenticated users

### Objective

Verify that an authenticated user can trigger sync manually and inspect the resulting sync state in the UI.

### Setup

- sign in
- create or edit tasks so local sync work exists

### Action

- use `Sync now` in the operator rail

### Expected behavior

- the sync pass starts immediately
- the diagnostics rail reflects sync lifecycle changes
- the latest sync outcome is captured visibly after completion

### Expected evidence

- `Sync State` and `Sync Outcomes` update in the diagnostics rail
- `Last sync` and outcome timestamps change in the operator and debug rails
- the event timeline records the manual sync request and resulting sync outcome

### Current gaps

- there is no operation-level breakdown of what was actually replayed
- retry and backoff semantics are still absent

## 4. Remote-wins on stale local state

### Objective

Verify that a stale local dirty task does not overwrite a fresher remote version.

### Setup

- create a task with the same id locally and remotely
- make the remote copy newer than the local `lastModifiedAt`

### Action

- run the sync path

### Expected behavior

- the stale local copy is replaced by the remote canonical copy
- the stale local copy is not pushed back over the fresher remote state

### Expected evidence

- automated Flutter regression coverage in `test/widget_test.dart`
- a completed sync outcome in the diagnostics rail

### Current gaps

- the user is still not told explicitly that a local change lost to remote state
- there is still no conflict state or per-task reconciliation explanation in the UI

## 5. Scheduled notification dispatch

### Objective

Verify that due tasks can be dispatched by backend infrastructure without requiring an active client session at send time.

### Setup

- sign in on a browser that supports web push
- register a push subscription for the current browser profile
- create a task whose `notify_at` will become due

### Action

- wait for the scheduled worker run

### Expected behavior

- the worker fetches due notifications
- a push request is sent to the provider
- the task is marked with `notification_sent = true` when the provider accepts it
- the browser service worker shows the notification

### Expected evidence

- notification appears in the subscribed browser profile
- worker logs show pending count and send outcome
- the diagnostics rail shows push permission and subscription state for the current profile

### Current gaps

- there is no delivery-attempt history table
- there is no client-side panel for last notification dispatch outcome
- notification cadence remains cron-based and coarse at five minutes

## 6. Stale subscription cleanup

### Objective

Verify that dead push subscriptions are removed when the provider reports them as gone.

### Setup

- use an invalid subscription or simulate `404` or `410` responses in tests

### Action

- run the scheduled worker or on-demand sender against that subscription

### Expected behavior

- push send fails for the stale subscription
- the stale subscription is deleted from persistence
- the send run reports both the failed push and the cleanup

### Expected evidence

- automated worker coverage in `@backend/agenda-notify-worker/test/index.spec.ts`
- worker logs show stale-subscription cleanup activity

### Current gaps

- the current user-facing diagnostics rail does not expose subscription churn history
- there is no re-registration prompt tied to cleanup

## 7. Per-profile notification fan-out

### Objective

Verify that multiple active browser profiles for the same account can each receive the same due notification.

### Setup

- sign in as the same user in two or more browser profiles
- allow push permission in each profile

### Action

- create a due task for that account

### Expected behavior

- every still-valid subscription for the user receives a push attempt
- multiple profiles can receive the same reminder independently

### Expected evidence

- observable live behavior across multiple profiles
- multiple `push_subscriptions` rows for the same account

### Current gaps

- there is no admin or debug UI listing subscriptions per account
- there is no delivery fan-out summary in the app shell

## Planned experiments that still need more infrastructure

## 8. Duplicate operation replay after reconnect

### Goal

Study whether repeated delivery of the same local mutation creates duplicate or inconsistent remote state.

### What is still needed

- durable outbox
- operation ids or idempotency keys
- server-side idempotency handling

## 9. Auth expiry during replay

### Goal

Study how queued local work behaves when the user session expires during replay.

### What is still needed

- explicit outbox state
- blocked-by-auth operation state
- clearer retry and recovery semantics

## 10. Update/delete race across devices

### Goal

Study what happens when one device deletes a task while another device updates it.

### What is still needed

- conflict capture
- deterministic experiment setup tools
- user-visible conflict handling

## 11. Concurrent edit conflict across devices

### Goal

Study whether concurrent edits converge correctly and visibly.

### What is still needed

- explicit conflict state
- merge or resolution policy
- conflict evidence in the shell

## 12. Network drop during partial replay

### Goal

Study how the client behaves when a sync pass partially succeeds and then loses connectivity.

### What is still needed

- partial replay accounting
- retry and backoff policy
- durable operation queue

## 13. Controlled fault injection from the operator shell

### Goal

Turn the lab from a passive observer into an active experiment harness.

### What is still needed

- real operator-rail toggles for connectivity loss, delayed sync, expired auth, duplicate replay, and conflict simulation
- runtime state capable of representing injected failures clearly
- documentation for expected evidence per injected scenario

## Practical reading of the current state

The repository can already demonstrate a meaningful slice of SaaS reliability behavior, but only for the parts it can currently model explicitly.

The shell transformation means future experiments now have a stable place to live.
The next major step is to make the sync contract explicit enough that queued, failed, and conflicted work can be observed rather than inferred.