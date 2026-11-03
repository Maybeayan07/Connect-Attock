# Pre-Phase-4 Combined Fix Report

## Scope

This pass does not start Phase 4. It uses the additive migration `supabase/migrations/202611030001_pre_phase4_fixes.sql` and leaves the Phase 1–3 migration files unchanged.

## Fixed

- Replaced the shared `prevent_protected_status_changes` attachment with separate `profiles`, `driver_profiles`, `vehicles` and `user_roles` trigger functions. Each function references only columns that exist on its attached table. The obsolete shared function is dropped after the new triggers are installed.
- Preserved the signup trigger: `handle_new_user` still creates a profile and customer role. SQL Editor/service-role maintenance is not blocked because the protection functions only restrict authenticated non-admin users.
- Added the protected `deactivate_my_account()` RPC and moved the profile deactivation UI to that server-side path.
- Added a private `verification-documents` storage bucket with owner-only upload/read/delete and admin-only read policies. File type and 10 MB size checks are enforced in storage policies and client validation; reviewers receive five-minute signed URLs.
- Added provider verification upload/resubmit workflow and a protected admin review page. Provider and vehicle approval/rejection use RLS-backed server-side RPCs, write `audit_logs`, notify providers, and add `service_provider` only server-side after provider approval.
- Removed the provider dead-end message and linked the real verification page.
- Changed Edge Function deployment guidance so only `payment-webhook` uses `--no-verify-jwt`. All user-facing functions use `requireUser` and server-side role/ownership checks.
- Added `ALLOW_MOCK_PAYMENTS` fail-closed checks to the Mock provider and mock action. It must be `true` only in a disposable test project.
- Added an idempotent test seed script and a trigger/RLS regression script.

## Migration order in Supabase SQL Editor

Run these files in this order:

1. `supabase/migrations/202610310001_phase1_foundation.sql`
2. `supabase/migrations/202610310002_phase2_ride_sharing.sql`
3. `supabase/migrations/202611010001_phase3_sandbox_payments.sql`
4. `supabase/migrations/202611030001_pre_phase4_fixes.sql`

For an already-migrated database, run only file 4. Do not edit or rerun old migrations as a substitute for the additive fix.

For a test project, edit `YOUR_EMAIL_PREFIX` in `supabase/tests/seed_test_users.sql`, run it after the migrations, then run `supabase/tests/pre_phase4_trigger_regression.sql`.

## Ran successfully in this environment

- `pnpm typecheck`
- `pnpm build`
- `pnpm test -- --run`: 14 tests passed
- `pnpm test:phase2-schema`
- `pnpm test:phase3-security`
- `pnpm test:pre-phase4-fixes`
- `git diff --check`
- Static searches for stale provider dead-end copy, public verification storage, committed payment secrets and unauthorized `--no-verify-jwt` deployment references.

## Not run

No user Supabase project credentials or disposable Postgres/Supabase instance are available in this environment. Therefore I did not claim to run:

- SQL migration execution against Postgres or Supabase Storage policies.
- Auth signup trigger execution with real `auth.users` records.
- Normal-user versus admin RLS tests against a live database.
- Concurrent last-seat bookings, duplicate/concurrent webhooks, payment-after-expiry, over-refund, ledger append-only or settlement isolation tests.
- Real Edge Function deployment, JWT verification at the Supabase gateway, signed URL expiry, Realtime, pg_cron or multi-user browser workflows.
- The verification upload and admin approval flow against live Storage/RLS.

Request a fresh Git bundle when you want to transfer this phase.
