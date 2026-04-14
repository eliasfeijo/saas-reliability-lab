---
name: repo-review-ready
description: Review the current diff for merge readiness in this repository. Use this when you want a high-signal pass over commit scope, doc alignment, CI expectations, and deploy implications.
---

Use this skill when the implementation is mostly done and you want a review-readiness pass.

Process:

1. Review the diff as one coherent change.
2. Check whether code, docs, and workflow behavior are aligned.
3. Identify what still blocks merge trust, including whether the diff should be split into smaller commit units.
4. Suggest a Conventional Commit message that fits the actual change, or multiple commit messages if the current diff should not land as one commit.
5. State which CI workflow should gate merge.
6. Call out whether the change has deploy implications for:
   - frontend deploy
   - worker deploy
   - verification only

Default commit discipline still applies here:

- do not bless a large mixed commit if the diff contains unrelated work
- prefer atomic commit guidance even when the branch review itself is otherwise positive

Prefer using the `reviewer` agent when a dedicated review pass would help keep the main context focused.
