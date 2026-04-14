# Task Workspace Responsive UX

This document captures the current responsive strategy for the middle pane after the Task Queue action and compact-layout iterations.

## Goal

Preserve the strong desktop operator experience on wide displays while making notebook and mobile layouts feel intentional instead of compressed.

The main UX rule is:

- keep the queue readable first
- keep task details and batch actions accessible second
- avoid floating surfaces that hide the queue's primary controls and row actions

## Recommended model

### Wide desktop

Keep the existing split workspace:

- Task Queue on the left side of the center pane
- Task Inspector on the right side
- no responsive compromise needed when the available height and width are healthy

This layout already works well on large monitors and should remain the reference experience.

### Notebook and compact widths

Use a scrollable stacked workspace instead of overlays.

- Queue Controls remain near the top of the Task Workspace
- Task Queue stays visible as the primary browsing surface
- task details and batch actions appear in an attached panel inside normal document flow
- the attached panel can be minimized to a small persistent handle
- the workspace scrolls vertically so smaller screens do not have to sacrifice full task rows just to keep details visible

This keeps the current context visible without covering queue controls or row-level actions.

### Mobile and very small widths

Use the same attached-panel model rather than introducing a separate overlay interaction.

- the queue remains first
- details/batch actions open below the queue controls in the same scrollable column
- minimized state stays discoverable through a persistent handle

Using one compact interaction model across notebook and mobile keeps the behavior easier to learn and easier to maintain.

## Queue behavior that pairs with this layout

- single-task browsing remains the default mode
- batch mode is explicit and opt-in
- completed state is represented by an explicit CTA or passive status badge, not a row-level checkbox in browse mode
- queue sorting belongs in Queue Controls beside search and filter controls

These choices reduce ambiguity in the row actions and keep the center pane focused on queue-first decision making.

## Initial batch operations

The current project can safely support these batch actions without introducing new backend semantics:

- select all visible
- clear selection
- mark done
- reopen
- delete

The visible-scope rule matters because batch actions should respect the current search and filter context.

## Why overlays were rejected

Earlier responsive experiments used floating inspector and batch overlays. They solved part of the height problem, but they created new UX problems:

- covered Queue Controls
- covered task-row actions
- felt cramped on notebook screens
- made mobile layouts feel even more constrained

The attached-panel model is less flashy, but it protects the queue and gives the user a more stable mental model.

## Implementation notes

- preserve the current wide split-pane layout
- keep minimum heights on compact surfaces so queue and details remain legible
- make compact layouts scrollable by design
- support minimize and close actions for the attached compact panel
- keep copy aligned with the new model by referring to `Task details` and `Batch actions`, not overlays or inline inspector language

## Follow-up opportunities

- tune compact breakpoints after more real-device usage
- add stronger sticky behavior for the compact panel handle if needed
- consider bulk actions such as defer or reprioritize only after the sync model grows beyond the current task-level reconciliation
