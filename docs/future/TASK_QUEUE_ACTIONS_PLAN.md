# Task Queue Completion CTA and Batch Actions Plan

## Purpose

This document defines the recommended end-to-end implementation plan for fixing the misleading completion control in the Task Workspace queue and for adding explicit multi-select batch operations without breaking the current local-first/task-level sync model.

## Problem summary

Today each queue row in `flutter-app\lib\widgets\lab\task_workspace.dart` renders:

- a round selected-state indicator
- a native `Checkbox` bound to task completion

That creates two adjacent affordances that both look like selection controls.

In the current workspace architecture, the default mental model is:

- browse the queue
- select one task
- inspect and act in the detail pane

The completion checkbox breaks that model because it looks like a second selection mechanism instead of an explicit task action.

## Recommended approach

### 1. Replace the completion checkbox with an explicit CTA

Do not use a checkbox for completion in the default queue view.

Recommended row treatment:

- keep row tap as the single-task selection behavior
- keep selection state visible through row styling and a lightweight selected-state treatment
- replace the checkbox with a labeled completion action such as `Mark done`
- once a task is completed, replace that CTA with a passive `Completed` badge and expose `Reopen task` from the inspector and batch toolbar

Why this is the safest recommendation:

- it makes completion read as an action, not a selection model
- it aligns with the existing inspector language, which already says `Mark complete`
- it preserves the current master/detail architecture instead of turning the queue into an always-multi-select surface
- it leaves real checkboxes available for a future explicit batch-selection mode

### 2. Introduce multi-select only through an explicit batch mode

Do not show batch-selection checkboxes all the time.

Recommended interaction:

1. Add a `Select` or `Batch actions` entry point in the Task Queue header.
2. Entering batch mode swaps the default single-selection affordances for real multi-select controls.
3. While batch mode is active, each visible row gets a checkbox dedicated to batch selection.
4. The workspace shows a batch summary and action bar instead of pretending single-task selection and multi-selection are active at the same time.
5. Exiting batch mode clears the batch selection and returns the queue to the normal browse/inspect flow.

Why this should be opt-in:

- the architecture doc explicitly positions `TaskWorkspace` as a canonical selection workflow with a persistent inspector
- the product is a reliability lab, not a general productivity suite that needs constant spreadsheet-like bulk editing
- keeping batch mode explicit avoids repeating the exact ambiguity that exists today

## UX plan

## Default browse mode

Recommended queue-row layout:

- row body remains clickable for single selection
- selected state is conveyed by border/background emphasis and optional `Selected` treatment
- trailing actions become action-oriented, not selector-oriented

Recommended task-completion presentation:

- incomplete task: `Mark done` as an outlined or tonal button with a check icon
- completed task: passive `Completed` badge in the row
- inspector keeps the reversible action with clearer labels:
  - `Mark done` for incomplete tasks
  - `Reopen task` for completed tasks

Implementation note:

`AgendaProvider.toggleTaskCompletion()` currently supports both states, but the UI copy should move to explicit verbs. The provider layer should gain explicit methods such as `markTaskCompleted()` and `reopenTask()` so the code matches the product language.

## Batch mode

Recommended header behavior:

- add `Select` in the Task Queue header when tasks are visible
- replace `Clear selection` with batch controls once batch mode is active
- show a visible selection count such as `3 selected`

Recommended row behavior in batch mode:

- replace the normal selected-state indicator with a real checkbox for membership in the batch selection set
- disable the row-level completion CTA to reduce accidental mixed-mode actions
- row tap toggles batch selection instead of opening the inspector

Recommended right-side pane behavior:

- wide layouts: replace the single-task inspector with a batch summary panel
- compact layouts: render the batch summary inline above the queue

Recommended initial batch actions:

- `Select all visible`
- `Clear selection`
- `Mark done`
- `Reopen`
- `Delete`

## Recommended scope boundaries

Implement now:

- explicit row-level completion CTA
- explicit batch mode
- batch mark done
- batch reopen
- batch delete
- select all visible / clear selection

Do not implement in this task:

- archive or trash semantics
- batch reschedule
- batch priority editing
- batch tag editing
- cross-filter hidden selection persistence
- remote atomic bulk APIs

Why these are out of scope:

- the current sync engine is still task reconciliation, not an operation outbox
- archive is already documented elsewhere as unsafe to fake locally before the lifecycle model evolves
- broader batch editing would expand the product surface more than this queue-clarity task requires

## End-to-end implementation plan

### 1. Provider and controller state

Current constraint:

- `TaskSelectionController` only stores one selected task
- `AgendaProvider` assumes single selection for the active workspace flow

Recommended changes:

1. Keep single-selection state for normal browse mode.
2. Add explicit batch-mode state in `AgendaProvider`, for example:
   - `bool isBatchMode`
   - `Set<String> batchSelectedTaskIds`
3. Add derived getters:
   - `int batchSelectedCount`
   - `List<TaskModel> selectedBatchTasks`
   - `bool get hasBatchSelection`
   - `bool isTaskBatchSelected(String taskId)`
4. Add actions:
   - `enterBatchMode()`
   - `exitBatchMode()`
   - `toggleTaskInBatchSelection(String taskId)`
   - `selectAllVisibleTasks()`
   - `clearBatchSelection()`
   - `markTaskCompleted(String taskId)`
   - `reopenTask(String taskId)`
   - `markSelectedTasksCompleted()`
   - `reopenSelectedTasks()`
   - `deleteSelectedTasks()`

Recommended interaction rule:

- entering batch mode clears the single selected task
- leaving batch mode clears the batch selection

That rule is simpler and avoids dual state fighting over the inspector.

### 2. Persistence and sync behavior

Current constraint:

- `toggleTaskCompletion()` saves immediately and triggers a debounced sync
- looping that method for multiple tasks would cause repeated saves and repeated sync scheduling

Recommended implementation:

1. Add an internal provider helper that mutates many tasks in one pass.
2. Save the full task list once after the full batch mutation completes.
3. Trigger one sync pass after the save.

Recommended shape:

- use explicit local mutations per affected task
- preserve local-first behavior even when offline
- call `syncAllTasks()` or a single debounced whole-list sync after the batch save rather than firing one sync per task

Delete semantics must stay aligned with the existing documented lifecycle:

- anonymous local-only tasks are removed immediately
- authenticated tasks are marked `SyncStatus.deleted` and reconciled through the existing sync flow

Important limitation to document in code review and implementation notes:

- batch actions are a client-side orchestration of multiple task mutations, not a transactional backend bulk endpoint

### 3. Task Queue UI changes

Files likely touched:

- `flutter-app\lib\widgets\lab\task_workspace.dart`
- potentially shared queue/tile widgets if the team decides to keep row rendering reusable

Recommended UI steps:

1. Replace the row-level `Checkbox` in `_WorkspaceTaskCard` with an explicit completion CTA.
2. Keep completion state visible through status badge styling and a passive completed label.
3. Add a queue-header entry point for batch mode.
4. Render batch checkboxes only while batch mode is active.
5. Render a batch action bar with count-driven enable/disable rules.
6. Switch the inspector pane to a batch summary when batch mode is active.

Recommended enable/disable rules:

- `Mark done` enabled when at least one selected task is incomplete
- `Reopen` enabled when at least one selected task is complete
- `Delete` enabled when at least one task is selected

Recommended selection scope rule:

- `Select all visible` must only act on `agenda.filteredTasks`, not on hidden tasks outside the current search/filter scope

That keeps the queue honest and avoids surprising background selection.

### 4. Inspector copy and CTA alignment

The inspector already uses explicit completion language, but the labels should be normalized with the queue:

- prefer `Mark done` or `Mark task done` consistently in queue and inspector
- keep `Reopen task` for the reverse action

Recommended follow-through:

- avoid mixed vocabulary such as `complete`, `done`, and `checked` describing the same action in different places
- update tooltips and semantics labels to match the chosen product term

## Validation plan

### Provider tests

Add or extend tests around `AgendaProvider` to cover:

- entering and exiting batch mode
- selecting visible tasks only
- batch completion marking only incomplete tasks
- batch reopen clearing `completedAt` correctly
- batch delete preserving anonymous-vs-authenticated delete behavior
- selection reset rules when filters/search change during batch mode

### Widget tests

Add `TaskWorkspace` coverage for:

- default queue rows no longer rendering a completion checkbox
- row-level completion CTA using explicit copy
- batch mode rendering real selection checkboxes
- batch summary/action bar replacing single-task inspector behavior
- `Select all visible` respecting current search/filter state

### Integration-style flow

Add one high-value interaction test that covers:

1. create multiple tasks
2. enter batch mode
3. select a subset
4. mark them done or delete them
5. verify queue counts, row state, and inspector/batch-summary transitions

## Documentation follow-through

Recommended documentation updates when implementation begins:

- keep this plan doc as the implementation source of truth
- update `docs\ARCHITECTURE.md` only after behavior ships, so the architecture document continues to describe implemented ownership rather than planned behavior
- keep `docs\README.md` linked to this plan so the work stays discoverable during execution

## Recommended delivery sequence

1. Introduce provider/state support for explicit completion verbs and batch mode.
2. Replace the queue checkbox with the explicit `Mark done` CTA.
3. Add batch-mode entry, row selection, and batch summary toolbar.
4. Implement batch complete, reopen, and delete flows with one-save/one-sync orchestration.
5. Add provider and widget coverage.
6. Update architecture docs after the feature is implemented.

## Recommendation summary

The recommended solution is:

- default queue: explicit `Mark done` CTA, not a checkbox
- multi-select: explicit batch mode, not always-visible second selectors
- initial batch actions: mark done, reopen, delete, select all visible, clear selection

That gives the queue a cleaner mental model, preserves the current master/detail architecture, and keeps the implementation inside the reliability lab's current sync and lifecycle constraints.
