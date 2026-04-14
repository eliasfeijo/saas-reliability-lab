---
name: repo-review-ready
description: Review the current diff for merge readiness in this repository. Use this when you want a high-signal pass over commit scope, doc alignment, CI expectations, and deploy implications.
---

Use this skill when the implementation is mostly done and you want a review-readiness pass.

Process:

1. Review the diff as one coherent change.
2. Check whether code, docs, and workflow behavior are aligned.
3. Identify what still blocks merge trust, if anything.
4. Suggest a Conventional Commit message that fits the actual change.
5. State which CI workflow should gate merge.
6. Call out whether the change has deploy implications for:
   - frontend deploy
   - worker deploy
   - verification only

Prefer using the `reviewer` agent when a dedicated review pass would help keep the main context focused.
