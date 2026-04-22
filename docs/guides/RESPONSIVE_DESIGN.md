# Responsive Design Guide

Status: active UX contract

## Purpose

This document is the single responsive reference for the lab shell and the task workspace.

It replaces the separate shell-wide responsive spec and task-workspace responsive UX note so the reader can answer one question in one place: how should the UI reflow across widths and heights without breaking the operator model?

## Core rule

The app must respond correctly both on first render and after live resize.
No reload should be required when width or height crosses a layout threshold.

## Current breakpoints

| Surface | Rule | Behavior |
| --- | --- | --- |
| Shell width | `>= 1500px` | Persistent Operator Rail, bounded Task Workspace, persistent Runtime Diagnostics |
| Shell width | `< 1500px` | App bar plus left and right drawers, workspace becomes the primary body |
| Workspace width | `>= 920px` | Split workspace with queue and persistent inspector |
| Workspace width | `< 920px` | Compact stacked workspace with attached details or batch panel |
| Workspace height | `< 820px` | Dense header and tighter spacing |
| Compact workspace height | `< 780px` | Smaller minimum queue height |
| Task card width | `< 520px` | Card header badges and actions stack vertically |

## Shell behavior

### Wide layouts

- show all three primary surfaces at once
- keep the center workspace visually dominant but width-bounded
- keep the rails visible without stretching the center pane into a full-width list

### Narrow layouts

- keep the Task Workspace as the main visible surface
- move the Operator Rail into the left drawer
- move Runtime Diagnostics into the right drawer
- preserve the same ownership model even when the rails are hidden behind drawers

## Workspace behavior

### Wide desktop

- keep the split workspace
- keep Task Queue on the left and Task Inspector on the right
- avoid responsive compromises when space is healthy

### Notebook and compact widths

- use a scrollable stacked workspace instead of overlays
- keep Queue Controls near the top of the workspace
- keep Task Queue visible as the primary browsing surface
- show task details and batch actions in an attached panel inside normal document flow
- allow the compact panel to minimize to a persistent handle

### Mobile and very small widths

- use the same attached-panel model rather than a separate overlay interaction
- keep the queue first and details second
- preserve discoverability through a persistent minimized handle

## Queue and inspector rules

- Queue Controls remain attached to the queue on every device class
- the queue remains the primary browsing surface across all sizes
- the inspector stays persistent only when the available width supports it
- compact layouts scroll as one document rather than layering floating surfaces over queue controls

## Why overlays were rejected

Earlier compact-layout experiments used floating overlays for details and batch actions.
They created avoidable problems:

- covered Queue Controls
- covered task-row actions
- felt cramped on notebook widths
- made mobile layouts more constrained instead of clearer

The attached-panel model is intentionally less flashy and more reliable.

## Validation expectations

Current targeted responsive coverage lives in `flutter-app\test\task_workspace_responsive_test.dart`.

When editing shell or workspace responsiveness, validate:

- shell breakpoint changes
- split versus compact workspace behavior
- dense-height behavior
- attached details and batch-panel behavior
- resize-in-place behavior, not only fixed-width first render

## Related docs

- [`../LOCAL_DEVELOPMENT.md`](../LOCAL_DEVELOPMENT.md)
- [`../TESTING_STRATEGY.md`](../TESTING_STRATEGY.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)