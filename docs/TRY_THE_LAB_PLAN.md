# Try the Lab Plan

## Purpose

This document defines the planned end-to-end shape of a low-friction `Try the Lab` entry path for the SaaS Reliability Lab.

It is a planning document, not an implementation record.
Nothing in this file should be read as already implemented unless another repository document says so explicitly.

## Decision record

The plan below is based only on the decisions provided for this feature.

- primary goal: fastest first-run access while preserving most of the current authenticated experience
- default easy path: one public shared authenticated sandbox account
- data model for the easy path: shared and resettable public state is acceptable
- push behavior in the easy path: disable web push registration and reminder delivery for the public sandbox account
- credential policy: do not expose reusable shared credentials in the client or docs
- lifecycle policy: manual operator-managed account and manual reset only
- personal-account path: keep the current personal sign up and sign in flow as a secondary option
- primary label: `Try the Lab`
- default entry mode: immediate authenticated cloud-backed sandbox
- implementation boundary: a dedicated backend path for sandbox entry is acceptable
- sandbox permissions: create, edit, delete, and run reliability scenarios are all allowed
- environment scope for the first plan: production-only operational account

## Implemented baseline

The repository currently provides:

- anonymous local-only task usage before sign-in
- email-and-password sign-in through Supabase Auth
- sign-up with OTP verification in the Flutter auth sheet
- direct authenticated task sync from the client into `public.tasks`
- automatic push-registration sequencing after authenticated setup
- runtime diagnostics that already expose auth, sync, storage, and push evidence

Relevant current files include:

- `flutter-app/lib/widgets/bottomsheets/login.dart`
- `flutter-app/lib/widgets/forms/otp_verify_form.dart`
- `flutter-app/lib/services/workspace_session_coordinator.dart`
- `flutter-app/lib/helpers/web_push_helper_web.dart`
- `supabase/functions/save_subscription/index.ts`
- `supabase/functions/delete_subscription/index.ts`

## Problem framing

The current product already has two meaningful auth-adjacent experiences:

1. local anonymous use before sign-in
2. full personal-account authentication through Supabase

Neither is ideal as the default path for a curious first-time visitor who wants to experience the lab quickly.

Anonymous local mode is friction-light, but it does not preserve the cloud-backed part of the product story.
The personal-account path is real and important, but it adds sign-up and confirmation friction too early for casual exploration.

The feature goal is therefore not generic "demo auth."
It is a deliberate third path:

- fast enough for immediate exploration
- authenticated enough to exercise the real cloud-backed lab surface
- constrained enough that the public path does not become the default model for personal or private usage

## Recommended product stance

Treat `Try the Lab` as a public sandbox entry path, not as a hidden auth shortcut and not as a replacement for personal accounts.

That means the product should present three distinct modes honestly:

1. `Try the Lab`
   A public shared sandbox for immediate exploration.
2. `Sign in`
   Existing users enter with their own credentials.
3. `Create account`
   New users opt into the full personal-account flow.

Why this framing is stronger than only treating one account as "special":

- it defines the user-facing contract, not only the backend exception
- it keeps the public path explicit and explainable
- it avoids pretending the shared account is a normal personal account
- it preserves the current personal-account path without burying it

## Non-goals for the first slice

The first implementation slice should not attempt to introduce these larger changes:

- isolated per-visitor demo workspaces
- Supabase anonymous-auth adoption as the new default auth model
- a fully server-owned task mutation boundary
- automatic sandbox reset or scheduled cleanup
- push delivery support for the shared sandbox account
- local-development sandbox parity as a required first deliverable

## Target behavior

When a new visitor lands on the app, the primary auth CTA should be `Try the Lab`.
Choosing it should place the visitor into the authenticated cloud-backed sandbox without exposing a reusable sandbox password in the client.

The user should then see:

- that they are in a public shared sandbox
- that state is shared and resettable
- that push is intentionally disabled in this mode
- that they can still choose their own account path if they want a personal experience

The product should preserve the current personal flows as secondary actions.

## Proposed architecture

### 1. Public sandbox identity model

Use one operator-managed Supabase auth user as the public sandbox account.

This account should:

- exist only in the production Supabase project for the first slice
- be created and maintained operationally, not through SQL migrations
- have a stable user id recorded in app configuration or backend secrets where needed
- remain clearly separate from personal user accounts in product copy and behavior

Why not manage this through migrations:

- `auth.users` is an operational auth surface, not part of the repo-managed application schema history
- the repository already treats Auth and database schema as related but separate concerns
- operational account creation and rotation should stay outside migration replay

### 2. Sandbox entry boundary

Add a dedicated Supabase Edge Function for sandbox entry.

Working name:

- `supabase/functions/enter-public-lab/index.ts`

Responsibilities:

- accept an unauthenticated request from the Flutter app
- authenticate against Supabase using operator-managed sandbox credentials stored only in Edge Function secrets
- return a session payload that the Flutter client can adopt
- return explicit metadata that the session belongs to the public sandbox mode
- reject unsupported methods and emit operator-useful error messages

This approach is preferable to exposing a shared password in the client because it keeps reusable credentials off the public frontend surface.

### 3. Client session adoption

The Flutter client should call the sandbox-entry function from the auth sheet and then adopt the returned session into the local Supabase client.

Planned client seam:

- add a dedicated auth service or coordinator method instead of embedding the whole flow directly in the widget

Candidate files:

- `flutter-app/lib/widgets/bottomsheets/login.dart`
- `flutter-app/lib/services/workspace_session_coordinator.dart`
- new file likely under `flutter-app/lib/services/` for the sandbox entry flow

Important validation item:

- the repo does not currently document a client-side session handoff from a custom Edge Function response into `supabase_flutter`
- before implementation, validate the exact supported SDK path for adopting a returned session cleanly on Flutter web

This is a required spike, not an optional detail.

### 4. Sandbox-mode classification

The app will need a reliable way to know whether the current authenticated session belongs to the public sandbox account.

Preferred first-slice approach:

- compare `currentUser.id` against a configured public sandbox user id

Likely configuration shape:

- expose a client-visible `PUBLIC_SANDBOX_USER_ID` runtime value

Why this is acceptable:

- a user id is not a secret
- the client already receives public Supabase runtime configuration
- the product needs a stable classification signal to adjust UI and behavior

Longer-term alternative if the product grows more roles:

- attach a clearer auth-app metadata classification and read that instead of hard-coding one id comparison

The first slice does not need that extra abstraction.

### 5. Push suppression for the sandbox

The sandbox account should authenticate successfully but skip push registration and sandbox-targeted delivery.

That requires two protections:

Client-side:

- `WorkspaceSessionCoordinator` should not trigger `registerWebPushSubscription` when the active user is the public sandbox account
- the UI should explain that push is unavailable in `Try the Lab`

Backend-side:

- push-related edges and worker behavior should not rely only on the client behaving correctly
- the delivery path should defensively ignore the sandbox account if a subscription is ever created accidentally

The first slice should implement both.

### 6. UI contract

The auth sheet should stop presenting only a binary `Log In` and `Create Account` emphasis.
It should instead present a three-path choice with clear explanation.

Recommended structure:

- primary action: `Try the Lab`
- secondary action: `Log In`
- secondary action: `Create Account`
- supporting note: `Public shared sandbox. Resettable. No private data. Push disabled.`

The sandbox entry should not masquerade as a personal sign-in.

### 7. Operator reset model

Because the sandbox is intentionally shared and manual-reset only, the plan should use an operator-run reset workflow instead of automated cleanup.

That workflow should be documented outside the customer-facing UI text and should include:

- when to reset
- what gets deleted
- how to verify the sandbox is clean again
- how to recover if the sandbox account is accidentally modified or locked out

This is an operational runbook concern, not a migration concern.

## End-to-end user flows

### Flow A: first-time visitor uses `Try the Lab`

1. Visitor opens the auth sheet.
2. Visitor selects `Try the Lab`.
3. Flutter calls `enter-public-lab`.
4. Edge Function signs in with sandbox credentials held in secrets.
5. Edge Function returns a Supabase session payload plus sandbox-mode metadata.
6. Flutter adopts that session.
7. Existing auth/session coordination runs.
8. Sandbox-mode check classifies the session as the public shared account.
9. Authenticated task sync proceeds normally.
10. Push registration is skipped.
11. UI shows that the operator is in the public sandbox.

### Flow B: visitor chooses personal sign-in

1. Visitor uses `Log In`.
2. Existing email/password path runs unchanged.
3. Existing authenticated setup and push behavior continue as implemented today.

### Flow C: visitor chooses personal sign-up

1. Visitor uses `Create Account`.
2. Existing sign-up path runs.
3. Existing OTP verification path runs.
4. Existing authenticated setup and push behavior continue as implemented today.

### Flow D: sandbox sign-out

1. Visitor signs out from the sandbox account.
2. Existing sign-out behavior clears local authenticated state.
3. The auth sheet returns with `Try the Lab` still as the primary entry path.

## Step-by-step implementation plan

### Phase 0 - Validation spike

1. Verify the exact Flutter web SDK path for taking a session returned from an Edge Function and installing it into `supabase_flutter` cleanly.
2. Confirm the Edge Function response shape needed for that handoff.
3. Decide whether the function should return raw session fields directly or a normalized wrapper object.
4. Stop and record the spike result before continuing with feature implementation.

Exit criterion:

- the repo has a confirmed and documented client session-adoption path for custom sandbox entry

### Phase 1 - Operational account preparation

1. Create a dedicated production sandbox auth user outside migrations.
2. Mark it operationally as the public shared sandbox account.
3. Set a strong operator-managed password even though visitors will never see it directly.
4. Record the user id and credential ownership in deployment documentation or operator runbook notes.
5. Store the sandbox credentials only as backend secrets.

Exit criterion:

- the production environment has one stable sandbox account with no client-visible reusable credentials

### Phase 2 - Backend entry path

1. Add `supabase/functions/enter-public-lab/index.ts`.
2. Implement method validation and CORS handling consistent with the current Edge Function style.
3. Read sandbox email and password from Edge Function secrets.
4. Perform sandbox sign-in on the backend.
5. Return the session payload needed by the Flutter client.
6. Return explicit mode metadata such as `accountMode: publicSandbox`.
7. Add defensive logging and clear error responses for operator diagnosis.

Exit criterion:

- the frontend can request sandbox entry without knowing the shared credentials

### Phase 3 - Flutter auth-sheet experience

1. Refactor the auth sheet so sandbox entry is a first-class action rather than a hidden alternate button.
2. Add the `Try the Lab` CTA as the primary auth action.
3. Keep `Log In` and `Create Account` as visible secondary actions.
4. Add honest explanatory copy for the sandbox behavior.
5. Surface sandbox-entry failures distinctly from personal-auth failures.
6. Keep the existing sign-up and OTP paths intact.

Exit criterion:

- the product presents an explicit three-path auth choice with the sandbox as the default exploration path

### Phase 4 - Session classification and behavior gating

1. Add a reliable sandbox-account classification helper in the client.
2. Thread that classification into session coordination and UI state.
3. Skip push registration for the sandbox account.
4. Show sandbox-mode messaging in the operator rail and auth-related UI surfaces.
5. Ensure sign-out and session restore preserve the correct classification behavior.

Exit criterion:

- sandbox sessions behave like authenticated cloud-backed sessions except for the intentionally disabled capabilities

### Phase 5 - Defensive backend and delivery behavior

1. Add a backend-side guard so accidental sandbox subscriptions are ignored or cleaned up.
2. Ensure the notify worker does not deliver push reminders for the sandbox account.
3. Decide whether subscription save/delete functions should reject sandbox mode explicitly or silently no-op it.
4. Document the chosen behavior honestly.

Exit criterion:

- sandbox push suppression does not depend only on frontend logic

### Phase 6 - Operator reset runbook

1. Document the manual reset steps for the sandbox data.
2. Define the reset target surface clearly:
   - tasks
   - push subscriptions if any slipped through
   - any related runtime artifacts that should be cleaned up operationally
3. Define when operators should use reset.
4. Define a short verification checklist after reset.

Exit criterion:

- operators can restore the sandbox to a predictable state without editing migrations or exposing credentials

## File and surface impact map

### Flutter app

Likely files to change:

- `flutter-app/lib/widgets/bottomsheets/login.dart`
- `flutter-app/lib/services/workspace_session_coordinator.dart`
- `flutter-app/lib/helpers/web_push_helper_web.dart`
- `flutter-app/lib/widgets/lab/lab_left_rail.dart`
- `flutter-app/lib/widgets/lab/task_workspace.dart`
- `flutter-app/lib/providers/runtime_debug_provider.dart`
- `flutter-app/lib/main.dart`
- `flutter-app/env.example.json`

### Supabase backend surface

Likely files to change:

- `supabase/functions/enter-public-lab/index.ts`
- `supabase/README.md`
- `supabase/api.http` if manual test snippets for the feature are useful

Possible non-migration configuration follow-through:

- production function secrets for sandbox credentials

### Notify worker

Likely files to change only if backend-side push suppression is implemented there:

- `notify-worker/src/**`
- `notify-worker/test/**`

### Docs

Docs that should be updated when implementation begins:

- `docs/ARCHITECTURE.md`
- `docs/DEPLOYMENT.md`
- `docs/LOCAL_DEVELOPMENT.md` if local parity is ever added later
- `docs/TESTING_STRATEGY.md`
- `README.md`
- `docs/README.md`
- `flutter-app/README.md`
- `supabase/README.md`

## Testing plan

### Flutter coverage

Add or extend tests for:

- auth sheet renders the `Try the Lab` path distinctly from personal flows
- sandbox entry success path
- sandbox entry failure path
- sandbox-mode push suppression
- sandbox-mode explanatory copy
- sign-out returning the user to the correct auth choices

### Backend coverage

Add tests or at least deterministic manual verification for:

- successful sandbox session issuance
- failure when credentials are missing or invalid
- failure on unsupported methods
- CORS and unauthenticated request handling

### Worker coverage

If worker-side push suppression is implemented there, add tests for:

- sandbox account notifications are skipped
- non-sandbox accounts remain unaffected

### Manual verification

1. New visitor enters through `Try the Lab` and lands in authenticated cloud-backed state.
2. Shared sandbox tasks are visible and mutable.
3. Push is not registered for the sandbox path.
4. Personal sign-in still works.
5. Personal sign-up plus OTP verification still works.
6. Sandbox sign-out returns the visitor to the same auth choices.

## Risks and tradeoffs

### 1. Shared-state ambiguity

Visitors will see shared public data and can modify it.
That is accepted by feature decision, but the UI must explain it plainly.

### 2. Public-account abuse

Manual reset without automated cleanup keeps the first slice simple, but it increases operator burden when the sandbox becomes noisy or vandalized.

### 3. Session handoff complexity

The key technical risk is the custom session adoption path from Edge Function to Flutter web.
That must be validated before implementation proceeds.

### 4. Special-case growth

One public sandbox account is reasonable now, but it introduces account-specific branching in the app.
The implementation should keep the classification seam narrow so it does not spread arbitrary special-case logic through the codebase.

## Recommendation summary

The right mental model is not "make one old test user special."
The right model is "introduce a first-class public sandbox entry path with one operator-managed backing account."

That gives the repo:

- a clearer visitor-facing story
- less auth friction for curious users
- a cleaner separation between exploration and personal ownership
- a bounded implementation slice that fits the current architecture

It also keeps the tradeoff honest:

- the sandbox is shared
- it is not private
- it is not the long-term answer for isolated demo environments
- but it is a pragmatic first `Try the Lab` path for this repo

## Ready-to-implement checklist

Before implementation starts, confirm these items explicitly:

- Flutter session adoption from Edge Function output is technically validated
- production sandbox account is created operationally
- sandbox credentials are stored as backend secrets only
- chosen client-visible sandbox classification value is defined
- push suppression is implemented both in the client and defensively in backend delivery
- sandbox reset runbook is documented
