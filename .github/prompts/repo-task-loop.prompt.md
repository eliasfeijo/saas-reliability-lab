Your goal is to run the repository's default AI-assisted workflow:

`plan -> implement -> verify -> update docs -> commit -> ci gate -> deploy`

Start by reading the relevant docs and code, then create a brief plan.

After planning, decide whether to continue immediately:

- continue into implementation when the task is clear, bounded, and low-ambiguity
- stop after planning and ask for review or direction when behavior choices are ambiguous, scope is unclear, or workflow/deploy risk is high

If continuing:

1. implement the change as a coherent vertical slice
2. update the relevant docs
3. validate using the repo's existing commands
4. summarize merge-readiness, including the CI gate that should pass before merge

Keep the repository aligned with its reliability-lab framing and current monorepo structure.
