# Connect Attock

Connect Attock is a route-aware marketplace for people moving between Rawalpindi and Attock: **Travel. Shop. Send.** Phase 1 delivered the product foundation, Phase 2 implemented ride sharing, and Phase 3 adds sandbox-only payment orchestration around database-owned transitions.

## What works in Phase 2

The app includes a responsive navy/cyan design system, Supabase Auth/profile foundation, passenger ride search with route/date/time/fare/seat filters and server-side pagination, sanitized ride detail pages, provider ride creation/edit/publish/cancel flows, approved-provider gating, vehicle records, pickup/drop-off map selection, intermediate stops, booking requests, provider accept/reject, temporary unpaid seat holds, cancellation reasons, trip start/complete/no-show actions, passenger completion OTPs, in-app notifications with unread count/mark-read/Realtime subscription, and ride reviews after completion.

Seat availability is never calculated in the browser. Requests, acceptance, cancellation, expiry, trip lifecycle, OTP verification and review eligibility use security-definer Postgres RPCs. The acceptance RPC locks the ride row with `FOR UPDATE`, and hold expiry releases seats through a database function.

Provider acceptance ends in `awaiting_payment`, then the passenger starts a clearly labelled **SANDBOX — NO REAL MONEY** checkout. Only a verified, fresh, HMAC-signed provider webhook can move the payment to `succeeded` and the booking to `confirmed`. Duplicate events are ignored, amount/currency mismatches enter `under_review`, and success after hold expiry creates a refund request without confirming the expired booking.

## Explicitly out of scope

Phase 3 does not implement real-money payments, live provider settlement, shopping, cargo, background/live GPS tracking, SMS, email notifications, Safepay sandbox execution or the full admin panel. Browser location is only used for optional pickup/drop-off selection after a normal permission prompt. The route preview uses the public OSRM demo server for development/testing and must be replaced or proxied responsibly before production traffic.

## Setup

1. Create a Supabase project on the free tier.
2. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
3. Run these migrations in order in Supabase SQL Editor:
   - `supabase/migrations/202610310001_phase1_foundation.sql`
   - `supabase/migrations/202610310002_phase2_ride_sharing.sql`
   - `supabase/migrations/202611010001_phase3_sandbox_payments.sql`
   - `supabase/migrations/202611030001_pre_phase4_fixes.sql`
4. In Supabase Auth, enable Email provider and configure Site URL plus redirect URLs for local Preview and the deployed URL. Configure Google OAuth only when its credentials are ready.
5. In Supabase Database > Replication, enable Realtime for `public.notifications`.
6. After reviewing shared-database implications, enable `pg_cron` and schedule hold expiry. A typical reviewed schedule is:

```sql
select cron.schedule(
  'connect-attock-expire-ride-holds',
  '* * * * *',
  $$select public.expire_unpaid_ride_holds();$$
);
```

7. Deploy the Edge Functions and set their server-only secrets as described in `docs/payments.md` and `supabase/functions/README.md`. Use `PAYMENT_PROVIDER=mock`; never put the service-role key or HMAC secret into `VITE_*` variables.

## Run and validate

```bash
pnpm install
pnpm dev              # managed Preview listens on port 3000
pnpm typecheck
pnpm test
pnpm test:phase2-schema
pnpm test:phase3-security
pnpm test:enum-assignments
pnpm build
```

`src/features/rides/validation.test.ts` covers ride validation. `src/features/payments/calculations.test.ts` covers minor-unit money math, commission rounding and webhook helper behavior. The two static scripts check required database/security markers. `supabase/tests/phase2_ride_sharing_manual.sql` and `supabase/tests/phase3_payments_manual.sql` require a real Supabase project, Edge secrets and multiple authenticated sessions.

## Environment variables

- `VITE_SUPABASE_URL` — browser-safe Supabase project URL.
- `VITE_SUPABASE_ANON_KEY` — browser-safe Supabase anon key.
- Edge-only `PAYMENT_PROVIDER`, `PUBLIC_APP_URL`, `MOCK_WEBHOOK_SECRET` and `ALLOW_MOCK_PAYMENTS` — set with `supabase secrets set`, never in browser `.env` files. Keep `ALLOW_MOCK_PAYMENTS=false` outside a disposable test project.

Never expose a service-role key, database password, payment secret, webhook secret or private document URL in `VITE_*` variables.

## Architecture

- `src/layouts` — shared responsive shell and navigation.
- `src/components` — reusable brand, form and state primitives.
- `src/features/rides` — typed ride API/RPC calls, validation, Leaflet map/route preview and status helpers.
- `src/features/notifications` — in-app notification state and Realtime subscription.
- `src/features/payments` — browser-safe checkout/status calls and integer-unit display calculations.
- `src/pages/rides` — passenger, provider, booking, vehicle and notification workflows.
- `src/pages/payments` — sandbox checkout, return polling, payment history, provider earnings and minimal admin actions.
- `src/hooks/useAuth.tsx` — Supabase session, profile and server-provided roles.
- `supabase/migrations` — additive versioned data/security boundary.
- `supabase/tests` — manual project-level security/concurrency checks.
- `public/manus-routes.json` — complete managed hosting route manifest.

## Known limitations and risks

Live Supabase Auth/Profile/RPC/payment webhook smoke tests were not possible without the user's project URL/key, Edge secrets and test accounts. Real concurrent webhooks, RLS isolation, refund races, pg_cron execution, browser GPS accuracy and multiple-device Realtime behavior require the manual project tests. Safepay is an untested skeleton. The OSRM public demo server is not a production SLA. Provider verification documents remain a private-schema/storage boundary; the full admin panel is a later phase.

## Deployment

For Vercel, set the browser-safe environment variables, build with `pnpm build` and publish `dist`. Configure Supabase redirect URLs for the final domain. Deploy Edge Functions from the repository and set their server-only secrets through Supabase. This phase is committed only to the managed repository; do not push to GitHub from this workflow.


## Pre-Phase-4 combined fixes

The additive migration `supabase/migrations/202611030001_pre_phase4_fixes.sql` fixes the table-specific protected-field trigger bug, adds private provider verification storage and review RPCs, promotes approved providers server-side, and hardens Mock Sandbox Edge Functions. Run it after the Phase 1, Phase 2 and Phase 3 migrations; on an already migrated project, run only this new migration. The exact checklist and limitations are in [`PRE_PHASE4_REPORT.md`](./PRE_PHASE4_REPORT.md).

Provider verification is available at `/provider/verification`. It accepts identity, driving licence, vehicle registration and vehicle image files into the private `verification-documents` bucket. Admin review is available at `/admin/provider-verification`; access is protected by the existing admin route and database RPC/RLS checks, while document previews use five-minute signed URLs.

For a disposable test project, edit the email prefix in `supabase/tests/seed_test_users.sql`, then run it followed by `supabase/tests/pre_phase4_trigger_regression.sql`. The scripts are not a substitute for a real two-session RLS/concurrency test. `ALLOW_MOCK_PAYMENTS=true` is permitted only in a disposable Mock Sandbox project; it must be false or unset in production.


## Enum assignment repair

The additive migration `supabase/migrations/202611030002_enum_assignment_fixes.sql` repairs enum/text assignment failures in ride publishing/editing, booking history, ride status transitions, payment transaction webhooks, refunds and vehicle review. It must run after `202611030001_pre_phase4_fixes.sql`; earlier migrations remain unchanged. The full audit is documented in [`ENUM_ASSIGNMENT_REPORT.md`](./ENUM_ASSIGNMENT_REPORT.md).

For a disposable Supabase project, run `supabase/tests/rpc_enum_smoke.sql` after applying all migrations. It attempts every public non-trigger RPC at least once and re-raises enum/type mismatch errors. Live execution requires `psql` and authenticated/test fixtures.
