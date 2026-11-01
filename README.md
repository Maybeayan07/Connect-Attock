# Connect Attock

Connect Attock is a route-aware marketplace for people moving between Rawalpindi and Attock: **Travel. Shop. Send.** Phase 1 delivered the product foundation and Phase 2 now implements the ride-sharing module end to end around database-owned transitions.

## What works in Phase 2

The app includes a responsive navy/cyan design system, Supabase Auth/profile foundation, passenger ride search with route/date/time/fare/seat filters and server-side pagination, sanitized ride detail pages, provider ride creation/edit/publish/cancel flows, approved-provider gating, vehicle records, pickup/drop-off map selection, intermediate stops, booking requests, provider accept/reject, temporary unpaid seat holds, cancellation reasons, trip start/complete/no-show actions, passenger completion OTPs, in-app notifications with unread count/mark-read/Realtime subscription, and ride reviews after completion.

Seat availability is never calculated in the browser. Requests, acceptance, cancellation, expiry, trip lifecycle, OTP verification and review eligibility use security-definer Postgres RPCs. The acceptance RPC locks the ride row with `FOR UPDATE`, and hold expiry releases seats through a database function.

The payment state is intentionally honest: provider acceptance ends in `awaiting_payment`. The optional control labelled **DEV-ONLY sandbox confirmation** is visible only when `VITE_ENABLE_DEV_RIDE_CONFIRM=true` and the signed-in user is an admin. It requires the database setting `dev_ride_confirmation_enabled=true` and never processes real money.

## Explicitly out of scope

Phase 2 does not implement payments, refunds, webhooks, shopping, cargo, background/live GPS tracking, SMS, email notifications or admin verification UI. Browser location is only used for optional pickup/drop-off selection after a normal permission prompt. The route preview uses the public OSRM demo server for development/testing and must be replaced or proxied responsibly before production traffic.

## Setup

1. Create a Supabase project on the free tier.
2. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
3. Run these migrations in order in Supabase SQL Editor:
   - `supabase/migrations/202610310001_phase1_foundation.sql`
   - `supabase/migrations/202610310002_phase2_ride_sharing.sql`
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

7. For a non-production sandbox only, an admin may set:

```sql
update public.app_settings
set value = 'true'::jsonb
where key = 'dev_ride_confirmation_enabled';
```

Then set `VITE_ENABLE_DEV_RIDE_CONFIRM=true` locally. Keep both disabled in production.

## Run and validate

```bash
pnpm install
pnpm dev              # managed Preview listens on port 3000
pnpm typecheck
pnpm test
pnpm test:phase2-schema
pnpm build
```

`src/features/rides/validation.test.ts` covers client validation. `scripts/check-phase2-schema.mjs` checks required RPC, lock and policy markers. `supabase/tests/phase2_ride_sharing_manual.sql` describes authenticated RLS, concurrent-last-seat, hold-expiry and OTP tests that require a real Supabase project and multiple test sessions.

## Environment variables

- `VITE_SUPABASE_URL` — browser-safe Supabase project URL.
- `VITE_SUPABASE_ANON_KEY` — browser-safe Supabase anon key.
- `VITE_ENABLE_DEV_RIDE_CONFIRM` — optional local-only flag for the admin sandbox confirmation control; it does not process payments.

Never expose a service-role key, database password, payment secret, webhook secret or private document URL in `VITE_*` variables.

## Architecture

- `src/layouts` — shared responsive shell and navigation.
- `src/components` — reusable brand, form and state primitives.
- `src/features/rides` — typed ride API/RPC calls, validation, Leaflet map/route preview and status helpers.
- `src/features/notifications` — in-app notification state and Realtime subscription.
- `src/pages/rides` — passenger, provider, booking, vehicle and notification workflows.
- `src/hooks/useAuth.tsx` — Supabase session, profile and server-provided roles.
- `supabase/migrations` — additive versioned data/security boundary.
- `supabase/tests` — manual project-level security/concurrency checks.
- `public/manus-routes.json` — complete managed hosting route manifest.

## Known limitations and risks

Live Supabase Auth/Profile/RPC smoke tests were not possible without the user's project URL/key and test accounts. Real concurrent requests, RLS isolation, pg_cron execution, browser GPS accuracy and multiple-device Realtime behavior require the manual project tests. The OSRM public demo server is not a production SLA. Provider verification documents remain a private-schema/storage boundary; admin review UI is a later phase.

## Deployment

For Vercel, set the browser-safe environment variables, build with `pnpm build` and publish `dist`. Configure Supabase redirect URLs for the final domain. The managed GitHub transfer to `Maybeayan07/Connect-Attock` remains paused until the platform confirmation card is completed; do not paste secrets or use a separate unmanaged repository.
