---
name: repo-commit-discipline
description: Prepare commit-ready units of work for this repository using atomic Conventional Commits, repo-aligned scope, and CI-aware merge discipline.
---

Use this skill when the implementation is ready to be organized into commitable units.

Process:

1. Review the current diff as a set of related or unrelated units of work.
2. Split the work conceptually into the smallest reasonable commit groups that still tell a coherent story.
3. Do **not** mix unrelated code, docs, workflow, or scaffolding changes in one commit.
4. For each commit group:
   - summarize what belongs in that commit
   - identify any files that should be left for a different commit
   - suggest a Conventional Commit message
   - tune the scope to the affected repo area when that improves clarity in this monorepo
5. Call out what should be committed together because it must stay aligned:
   - behavior + docs
   - workflow + workflow docs
   - config + lockfile or generated metadata when required
6. Identify which CI gate matters before merge.

Default commit discipline:

- prefer one coherent unit of work per commit
- prefer Conventional Commits by default
- prefer repo-area scope such as `flutter-app`, `notify-worker`, `docs`, or `github` when it clarifies the change
- avoid a large catch-all commit unless the diff is truly one inseparable unit
