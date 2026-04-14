---
name: repo-plan-task
description: Create a repo-aligned implementation plan for a task without automatically implementing it. Use this when you want a planning-first pass in the SaaS Reliability Lab.
---

Use this skill when the user wants a planning-first workflow.

Required behavior:

1. Read the relevant docs and identify which surfaces are affected.
2. Summarize:
   - implemented state
   - desired state
   - constraints or open questions
3. Produce a concrete step-by-step plan aligned with this monorepo.
4. Name the verification and documentation follow-through the task will require.
5. Stop after the plan unless the user explicitly asks to continue into implementation.

Prefer using the `planner` agent when a dedicated planning pass would help keep the main context clean.
