---
applyTo: ".github/workflows/**/*.yml,.github/workflows/**/*.yaml,.github/actions/**/*.yml,.github/actions/**/*.yaml,.github/copilot-instructions.md,.github/agents/**/*.md"
---

Keep repository automation explicit and easy to reason about.

- `verify.yaml` is the repository trust workflow.
- Frontend and worker deploys are intentionally separate surfaces unless the task explicitly changes that design.
- Changes to workflows or agent configuration should be reflected in the relevant docs.
- Do not treat any future Copilot cloud-agent setup as a substitute for source-code verification.
- Prefer simple, explicit workflow wiring over clever hidden behavior.
