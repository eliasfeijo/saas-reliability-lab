---
name: docs-followthrough
description: Update the relevant repository docs when behavior, workflow, testing, or deployment changes. Use this when a task changes implemented behavior or automation and the docs must stay aligned.
---

For this repository, documentation is part of the delivery.

Use this process:

1. Identify which docs should change:
   - `docs\ARCHITECTURE.md`
   - `docs\DEPLOYMENT.md`
   - `docs\LOCAL_DEVELOPMENT.md`
   - `docs\TESTING_STRATEGY.md`
   - `docs\GITHUB_AUTOMATION.md`
   - relevant subproject `README.md` files
2. Describe the implemented behavior honestly.
3. Preserve the reliability-lab framing and repo terminology.
4. If the task affects workflow or CI/CD, make sure the docs match the actual files in `.github\`.
5. Keep index docs discoverable when adding new long-form docs.
