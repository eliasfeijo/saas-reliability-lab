---
applyTo: "flutter-app/**/*.dart,flutter-app/pubspec.yaml,flutter-app/web/**"
---

Treat `flutter-app\` as the web-first client surface of the reliability lab, not as a generic todo UI.

- Preserve the current lab-shell framing and terminology.
- Keep runtime evidence visible when behavior changes touch sync, auth, push, or local state.
- Prefer existing provider, service, and widget patterns over introducing parallel abstractions.
- If behavior changes, update the relevant docs in `docs\`.
- Validate with the existing Flutter test command unless the task is documentation-only.
