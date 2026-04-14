---
name: repo-task-loop
description: Run the full local AI-assisted workflow for this repo: plan first, then either implement immediately or stop for review based on ambiguity, risk, and scope.
---

Use this skill for the repository's default end-to-end working loop:

`plan -> implement -> verify -> update docs -> commit -> ci gate -> deploy`

Decision process:

1. Start with a brief plan after reading the relevant docs and files.
2. Decide whether to continue immediately:
   - continue now when the task is clear, bounded, and does not require a major product or architecture decision
   - stop after planning and ask for review when behavior choices are ambiguous, scope is unclear, or workflow/deploy risk is high
3. If continuing:
   - prefer the `implementer` agent for code and config changes
   - use the `docs-followthrough` skill or `docs-writer` agent when docs need updating
   - use the `repo-verification` skill or `verifier` agent for validation
   - use the `reviewer` agent for commit and CI readiness
4. End with a concise handoff covering:
   - what changed
   - what was verified
   - what docs changed
   - what CI gate should pass before merge

This skill should optimize for low-friction completion, not repeated stopping points.
