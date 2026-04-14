# Lab Shell Responsive Specification

This document records the current responsive implementation in `flutter-app` and defines the expected UI/UX contract for each layout section across viewport sizes and device classes.

It exists to turn responsiveness into an explicit product rule, not an implicit side effect of the current Flutter layout tree.

## Why this matters

The lab is web-first and can run in a resizable browser window. That means responsiveness must behave the same way:

- on first load
- after a browser window resize
- after a host container resize such as an embedded web view or iframe-like wrapper

The app must not require a reload to re-apply layout rules after the available width or height changes.

## Current implementation snapshot

The current implementation already uses live layout primitives rather than one-time size checks:

- `LabShell` switches between wide three-pane mode and drawer mode with `LayoutBuilder`
- `_WorkspaceCanvas` caps the center pane at a maximum readable width
- `TaskWorkspace` switches between split and compact workspace modes with `LayoutBuilder`
- the workspace header also reacts to height through `MediaQuery.sizeOf(context).height`
- each task card has its own internal width breakpoint for stacked headers

### Implemented breakpoints

| Surface | Current rule | Current behavior |
| --- | --- | --- |
| Shell width | `>= 1500px` | Persistent left rail, centered workspace canvas, persistent diagnostics rail |
| Shell width | `< 1500px` | App bar plus left/right drawers, workspace becomes the primary body |
| Workspace width | `>= 920px` | Split center pane with queue on the left and persistent inspector on the right |
| Workspace width | `< 920px` | Scrollable compact workspace with attached details or batch panel above the queue |
| Workspace height | `< 820px` | Dense spacing, tighter header, more compact chips and notices |
| Compact workspace height | `< 780px` | Smaller minimum queue height |
| Task card width | `< 520px` | Card header badges and actions stack vertically |

### Current gaps

The implementation is responsive by structure, but the full contract is not yet documented or fully validated.

Most existing widget coverage exercises fixed widths at render time. It does **not** yet make resize-in-place a documented acceptance criterion for the shell as a whole. From now on, live resize behavior should be treated as required UX.

## Device classes

These device classes describe the intended experience. They are UX categories, not additional hard-coded breakpoints beyond the rules above.

| Device class | Typical shape | Expected shell mode |
| --- | --- | --- |
| Large desktop monitor | very wide browser window | persistent three-pane shell |
| Notebook / small desktop | medium browser window | drawer shell, with workspace layout decided by available center width |
| Tablet landscape | medium width, lower height | usually drawer shell, often dense workspace |
| Tablet portrait | narrow-to-medium width | drawer shell, compact workspace |
| Phone | narrow width and height constraints | drawer shell, compact workspace, dense UI where needed |

## Expected behavior by layout section

### 1. Root shell

#### Large desktop

- show all three primary surfaces at once: Operator Rail, Task Workspace, Runtime Diagnostics
- keep the center workspace visually dominant but width-bounded
- avoid stretching the task canvas across the entire monitor

#### Notebook, tablet, and phone

- keep the Task Workspace as the main visible surface
- move Operator Rail into the left drawer
- move Runtime Diagnostics into the right drawer
- keep the shell ownership model unchanged even when the rails are hidden behind drawers

#### Resize requirement

When the viewport crosses the shell breakpoint in either direction, the shell must immediately reflow between:

- persistent rails
- drawer-based rails

No refresh should be needed, and task state, selection state, search, filters, and diagnostics state must remain intact.

### 2. App bar and drawer entry points

#### Wide shell

- hide the app bar
- expose both rails directly in the layout

#### Narrow shell

- show an app bar
- use the leading action to open the Operator Rail drawer
- use the trailing action to open the Runtime Diagnostics drawer
- keep the title stable and readable

#### Resize requirement

When moving from narrow to wide, drawer-only actions should disappear because their surfaces become persistently visible. When moving from wide to narrow, those actions should appear automatically.

### 3. Operator Rail

The Operator Rail is a persistent column on wide layouts and drawer content on narrower layouts. Its information architecture must stay the same in both forms.

#### Expected behavior on all sizes

- keep section order stable: session controls, task scope, anonymous task review, scenario controls
- allow long chip groups and action groups to wrap instead of clipping
- remain vertically scrollable

#### Wide shell

- render as a fixed-width left column
- preserve card spacing and readable section separation

#### Narrow shell

- render inside a drawer without losing any controls
- avoid introducing a second compact-only control model

### 4. Runtime Diagnostics rail

The diagnostics surface follows the same shell ownership rule as the Operator Rail.

#### Expected behavior on all sizes

- keep status cards stacked vertically in a scrollable column
- allow badges, chips, and event labels to wrap
- preserve access to sync, session, local state, push, and timeline evidence

#### Wide shell

- render as a fixed-width right column

#### Narrow shell

- render inside the end drawer
- preserve the same card order and meaning as desktop

### 5. Workspace canvas

The center pane is not allowed to become an infinitely stretched list.

#### Wide shell

- center the workspace horizontally inside the remaining shell space
- cap the workspace width to the current desktop maximum
- keep full-height alignment with the rails

#### Narrow shell

- let the workspace use the available body width with standard page padding

#### Resize requirement

The center pane must recompute its maximum readable width continuously as the shell width changes.

### 6. Workspace header

#### Regular height

- show `Task Workspace`, the contextual subtitle, and the primary create action
- allow the subtitle to describe current queue or inspector state

#### Dense height

- reduce padding
- reduce title emphasis one step
- shorten the primary CTA label from `New task` to `New`
- keep the subtitle to a single readable line with ellipsis

#### Resize requirement

Height changes must immediately switch between regular and dense header treatments.

### 7. Queue Controls

Queue Controls stay attached to the task queue on every device class.

#### Wide and split layouts

- keep search, sort, filters, metrics, and session notices at the top of the queue flow
- allow sort and filter controls to share the same wrapping row when space allows

#### Compact layouts

- keep sort above the filter chip group
- allow filter chips to wrap into multiple rows
- keep metrics visible without forcing horizontal overflow
- if density is tight, allow the metric strip to scroll horizontally rather than compressing labels into illegibility

#### Session notices

- show anonymous-mode and local-review notices inline with Queue Controls
- use a shorter, denser treatment when vertical space is limited
- keep the CTA visible in both regular and dense modes

### 8. Task Queue

The queue remains the primary browsing surface across all sizes.

#### Split workspace

- keep the queue in the left portion of the workspace
- let the queue scroll independently from the inspector

#### Compact workspace

- keep the queue below Queue Controls and any attached details panel
- make the whole compact workspace scroll as one document
- preserve a minimum queue body height so the queue still feels primary

#### Empty and filtered states

- center the empty-state messaging inside the queue panel
- keep the reset-view action visible when the current filter or search hides all rows

### 9. Task cards

Each task card must remain tappable and scannable without horizontal clipping.

#### Wider cards

- keep status badges and row actions on the same header row
- show the title, summary, and schedule metadata with comfortable spacing

#### Narrower cards

- stack badges above actions when the card width becomes tight
- keep action affordances visible without truncating the title block
- reduce summary length before sacrificing action clarity

#### Batch mode

- replace the normal selection affordance with checkboxes
- keep row actions understandable without opening the inspector first

### 10. Inspector and batch panel

#### Split workspace

- keep a persistent inspector on the right side of the workspace
- allow the queue and inspector to stay visible together
- keep placeholder, details, and batch modes within the same fixed inspector surface

#### Compact workspace

- move task details or batch actions into an attached panel above the queue
- keep that panel in normal document flow instead of using a floating overlay
- support minimize and close actions
- when minimized, replace the panel with a persistent handle that can reopen it

#### Resize requirement

When the workspace crosses the split breakpoint:

- wide mode must promote the attached compact panel into the persistent inspector
- compact mode must demote the inspector into the attached panel model
- current selection or batch context must survive the transition

### 11. Forms, dialogs, and bottom sheets

These surfaces are not the main shell, but they must still respect constrained viewports.

#### Expected behavior

- auth entry remains in a scroll-controlled bottom sheet
- task create and edit flows remain reachable on smaller heights
- destructive confirmations stay readable without overflowing the viewport

Dialogs must never be the only place where core shell controls live.

## Required live-resize contract

This requirement is now explicit:

1. Every responsive decision must react to the **current** viewport or container size, not only the initial render size.
2. Crossing a breakpoint during runtime must apply the same layout rules used on first load.
3. Search state, filter state, selected task state, batch-selection state, and runtime evidence state must survive a resize.
4. No shell mode may require a manual refresh to become usable after a resize.

## Automated verification strategy

The responsive contract should be enforced primarily with Flutter widget tests in `flutter-app\test\`, because the current shell behavior is driven by Flutter layout state, not browser-only CSS behavior.

### Current automated baseline

The repository already has responsive widget coverage in `flutter-app\test\task_workspace_responsive_test.dart`.

That file already proves several layout behaviors at fixed viewport sizes:

- desktop-width workspace behavior through `_LabWorkspaceHarness`
- notebook-width attached-details behavior through `_NotebookWorkspaceHarness`
- compact-width behavior through `_CompactWorkspaceHarness`
- compact queue header stacking
- compact filter wrapping
- compact attached details
- compact panel minimization

This is a good starting point, but it currently validates **entry into a size**, not **transition between sizes during runtime**.

### Test layers to automate

#### 1. Shell contract tests

These tests should render the real `LabShell` and verify shell ownership across breakpoints:

- wide shell shows persistent `LabLeftRail`, `TaskWorkspace`, and `SyncDebugPanel`
- narrow shell shows the app bar and hides the rails behind drawers
- opening the left drawer reveals the Operator Rail
- opening the end drawer reveals Runtime Diagnostics

These tests are responsible for the `1500px` shell contract.

#### 2. Workspace contract tests

These tests should render `TaskWorkspace` with seeded provider state and verify:

- split mode at `>= 920px`
- compact attached-panel mode at `< 920px`
- dense mode at heights `< 820px`
- queue minimum-height behavior on compact short viewports
- task-card header stacking below `520px`

These tests are responsible for the center-pane implementation details.

#### 3. Resize-in-place tests

These are the most important missing tests and should become required for this contract.

Each test should:

1. pump the widget at one size
2. create meaningful state first
3. change `tester.view.physicalSize`
4. call `pump()` and `pumpAndSettle()`
5. assert that the new layout is active **without losing state**

Required transitions:

- wide shell -> narrow shell -> wide shell
- split workspace -> compact workspace -> split workspace
- regular height -> dense height -> regular height
- selected task retained across workspace transitions
- batch mode and batch selection retained across workspace transitions
- queue controls still readable after repeated resize transitions

### Implementation details for widget automation

The current test suite already uses the right primitives, so the planned automation should follow the same style:

- set viewport size with `tester.view.physicalSize`
- normalize density with `tester.view.devicePixelRatio = 1.0`
- reset both values with `addTearDown(...)`
- seed state through `AgendaProvider`, `RuntimeDebugProvider`, and the in-memory repository/service helpers already present in the test file
- assert layout mode by looking for user-visible shell markers instead of private implementation details

Recommended assertions by surface:

| Surface | Preferred assertions |
| --- | --- |
| Shell mode | presence/absence of app bar, left rail, right rail, drawer-open content |
| Workspace mode | presence of `Task Inspector` vs `Task details`, queue position, attached panel handle |
| Dense mode | `New` vs `New task`, compact notice treatment, compact metric rendering |
| Task cards | stacked action position, preserved badges, visible CTA or checkbox state |
| State persistence | selected task title, search query, active filter, batch selected count |

### Recommended test organization

The current responsive coverage is in `task_workspace_responsive_test.dart`, which is acceptable for now because it already contains the workspace harnesses.

As coverage grows, the responsive contract should be split into dedicated files such as:

- `flutter-app\test\lab_shell_responsive_test.dart`
- `flutter-app\test\task_workspace_responsive_test.dart`

That split is recommended for maintenance, not required before adding the next tests.

### Acceptance criteria for future responsive changes

A responsive change should not be treated as complete until automated tests cover:

1. the breakpoint entry case
2. the resize-in-place transition case
3. the persistence of user state across that transition
4. the continued discoverability of the relevant controls after the transition

### Short-term test backlog

The next responsive tests to add are:

- `LabShell` wide/narrow shell transition coverage
- `TaskWorkspace` split/compact resize coverage with an active task selected
- `TaskWorkspace` split/compact resize coverage in batch mode
- dense-height transition coverage for the workspace header and notices

## Relationship to other docs

- `TASK_WORKSPACE_RESPONSIVE_UX.md` remains the focused strategy note for the center pane
- this document is the shell-wide responsive contract for the full lab layout
