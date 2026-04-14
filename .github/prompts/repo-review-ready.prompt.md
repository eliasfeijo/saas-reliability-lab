Your goal is to review the current repository change for **merge readiness**.

Review the diff as one coherent change and report:

1. what changed
2. whether code, docs, and workflow files are aligned
3. what still blocks merge trust, including whether the diff should be split into smaller commit units
4. a Conventional Commit message suggestion, or multiple commit messages if the current diff should not land as one commit
5. which CI gate should pass before merge
6. whether the change affects:
   - frontend deploy
   - worker deploy
   - verification only

Keep the review high-signal and practical.
Do not approve a large mixed commit if the diff should be separated first.
