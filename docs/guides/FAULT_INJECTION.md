# Fault Injection Guide

Status: active guide for implemented and planned scenario controls

## Purpose

This document is the single fault-injection reference for the lab.

It replaces the separate broad fault-injection plan and delayed-sync execution note with one purpose-based guide that distinguishes clearly between what exists now and what still remains planned.

## Implemented now

The repository already supports:

- an explicit local outbox with queued, sending, acknowledged, failed, conflict, blocked-session, and blocked-review states
- operator-facing connectivity-loss and delayed-sync scenarios
- delayed-sync presets of `500 ms`, `2 s`, `5 s`, and `10 s`
- delayed-sync modes of `local`, `transport`, and `backend`
- persistent and one-shot delayed-sync behavior
- runtime diagnostics and event timeline evidence for active delayed-sync configuration and replay-stage holds

## Current implementation boundary

The current delayed-sync modes are honest client-side simulations on the explicit outbox replay path.

That means:

- `local` delays hold the replay pass before remote work begins
- `transport` delays slow the client-owned outbound replay seam
- `backend` delays simulate acknowledgement delay after remote success and before local acknowledgement is recorded

This is useful and educational, but it is not yet a true server-owned mutation contract.

## Principles

1. Keep the project a reliability lab first.
2. Inject failures at real seams, not only in widgets.
3. Leave visible evidence for every synthetic scenario.
4. Describe planned behavior as planned behavior.
5. Prefer one active scenario at a time until stacked-failure evidence becomes easier to explain.

## Current scenario model

### Connectivity loss

- owned from the operator surface
- applied at the sync boundary
- visible through runtime diagnostics and event timeline evidence

### Delayed sync

- operator-selectable mode, duration, and behavior
- stage-aware delay injection on the outbox replay path
- explicit timeline evidence when replay input is refreshed or deferred due to newer local mutations

## Recommended next scenarios

The next priority order remains:

1. richer delayed-sync coverage on the outbox replay path
2. expired auth during replay
3. partial replay drop
4. duplicate replay
5. update/update conflict simulation
6. worker-side fault injection

## Validation surfaces

Primary implementation surfaces in `flutter-app/lib/`:

- `models/fault_injection_state.dart`
- `models/fault_injection_scenario.dart`
- `providers/fault_injection_provider.dart`
- `services/fault_injection_policy.dart`
- `services/task_sync_service.dart`
- `providers/runtime_debug_provider.dart`
- `widgets/lab/lab_left_rail.dart`
- `widgets/debug/sync_debug_panel.dart`

Likely tests to extend in `flutter-app/test/`:

- `fault_injection_provider_test.dart`
- `sync_logic_test.dart`
- `sync_debug_panel_test.dart`
- `lab_left_rail_test.dart`

## Related docs

- [`../phases/OBJECTIVE_1_OUTBOX.md`](../phases/OBJECTIVE_1_OUTBOX.md)
- [`EXPERIMENTS.md`](EXPERIMENTS.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`../TESTING_STRATEGY.md`](../TESTING_STRATEGY.md)