# Connect Attock — Phase 2 Ride Sharing Report

## 1. What is implemented and how to try it

Phase 2 implements the ride-sharing module only. The passenger flow is available at `/find-a-ride`: search by direction/date/time, fare, minimum seats and sorting, then open `/rides/:id`, review the provider/vehicle/route details, accept the cancellation policy and request seats. Requests move through database RPCs and appear at `/bookings/:id` with a status timeline.

The provider flow is available at `/offer-a-ride`, `/provider/rides`, `/provider/vehicles` and `/provider/bookings/:rideId`. Only an approved provider can create/publish. Providers can add vehicles, create/edit/publish/cancel rides, review requests, accept/reject, start/complete trips, enter passenger completion OTPs and record no-shows. Ride changes, booking changes, seat holds and expiries are database-owned.

In-app notifications are available at `/notifications` with unread count, mark-read and a Supabase Realtime subscription. After a completed booking, both participants can submit one review in their direction. Leaflet/OpenStreetMap supports manual pickup/drop-off selection; optional browser location uses the normal permission prompt. Ride detail shows a non-live OSRM route preview/distance.

Payment is not implemented. Provider acceptance ends in `awaiting_payment`. A clearly labelled DEV-ONLY sandbox confirmation control is hidden unless both `VITE_ENABLE_DEV_RIDE_CONFIRM=true` and the database setting `dev_ride_confirmation_enabled` are enabled, and the signed-in user is an admin. It never charges or verifies real payment.

## 2. Tests run and results

- `pnpm typecheck` — passed.
- `pnpm test` — passed: 5 Vitest validation tests.
- `pnpm test:phase2-schema` — passed: required Phase 2 migration/RPC/RLS/lock markers found.
- `pnpm build` — passed. Vite emitted the existing React Router directive warning and a large-bundle advisory; no build error occurred.
- Preview verification — `GET /manus-routes.json` returned HTTP 200 with 27 routes, including ride detail and provider request routes.
- Static migration review — confirmed the additive migration includes `FOR UPDATE` locking, hold expiry, expanded statuses, provider gating, booking history, notifications and review functions.

The real Supabase RLS, concurrent last-seat, pg_cron, Auth, Realtime and OTP multi-session tests are documented in `supabase/tests/phase2_ride_sharing_manual.sql` but were not run here because no user Supabase project credentials or test accounts are configured. They must not be claimed as passed until run against the user's project.

## 3. Not done or limited

Payments, refunds, webhooks, shopping, cargo, live/background GPS tracking, SMS/email notifications and admin verification UI are not part of Phase 2. Verification documents remain a private-schema/storage boundary. The OSRM public demo server is development/testing infrastructure only. The map requests browser location permission but cannot guarantee desktop accuracy. Cron is implemented as a callable expiry function and documented schedule; it is not active until the user enables and schedules it in Supabase.

## 4. Known risks and bugs

The migration has not been executed against the user's Supabase instance in this environment, so project-specific PostgreSQL extensions, existing data, Realtime publication state, Auth policies and cron availability still need verification. The shared development/production database warning applies: run migrations carefully and back up first. The client bundle is large because Leaflet is currently bundled into the main route; production code-splitting is recommended before scale.

## 5. Exact user steps

1. Run `supabase/migrations/202610310001_phase1_foundation.sql` if it has not already been run.
2. Run `supabase/migrations/202610310002_phase2_ride_sharing.sql` in Supabase SQL Editor. Do not edit the old migration.
3. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`; keep service-role/payment/database secrets out of `VITE_*` variables.
4. Enable Realtime for `public.notifications`.
5. Enable/review `pg_cron`, then schedule `select public.expire_unpaid_ride_holds();` every minute using the documented cron statement in README/schema docs.
6. Create an admin, approved provider, provider vehicle and passenger test accounts. Run the manual RLS/concurrency/OTP tests with two authenticated sessions.
7. Only in a non-production sandbox, set `app_settings.dev_ride_confirmation_enabled` to true and set `VITE_ENABLE_DEV_RIDE_CONFIRM=true` for the admin test environment.
8. Replace the public OSRM demo routing with a production-approved routing provider or responsible proxy before public traffic.

## Delivery boundary

Phase 2 code and documentation are complete in the workspace and ready for the user's Supabase migration/smoke-test approval. Phase 3 payments has not started. The managed GitHub transfer to `Maybeayan07/Connect-Attock` is still paused at the platform confirmation card; the managed repository remains canonical until that transfer is explicitly confirmed and completed.
