---
name: repo-verification
description: Validate repository changes using the existing repo commands. Use this when asked to verify work, check readiness, or confirm what still blocks merge trust.
---

For this repository, verification should follow the documented repo commands rather than inventing new tooling.

Use this process:

1. Identify which surfaces changed: `flutter-app\`, `notify-worker\`, `supabase\`, `docs\`, or `.github\`.
2. Run the existing validation commands relevant to the changed surfaces:
   - `Push-Location .\flutter-app; flutter test; Pop-Location`
   - `Push-Location .\notify-worker; yarn test; Pop-Location`
3. If the task is docs-only, verify documentation alignment with the implemented behavior and workflow files instead of pretending code tests were needed.
4. Distinguish clearly between:
   - local verification
   - CI gate expectations
   - deploy readiness
5. Summarize failures precisely and avoid noisy output when everything passed.
