Your goal is to prepare the current repository work for **clean, atomic commits**.

Review the diff and:

1. identify the smallest coherent commit units
2. separate unrelated changes instead of batching them together
3. keep docs, workflow, and behavior changes together only when they are part of the same unit of work
4. suggest a Conventional Commit message for each unit
5. tune commit scope to the affected repo area when that improves clarity in this monorepo
6. identify which CI gate matters before merge

Default rules:

- one coherent unit of work per commit
- no big mixed commits
- prefer Conventional Commits
- preserve this repository's reliability-lab framing and monorepo boundaries
