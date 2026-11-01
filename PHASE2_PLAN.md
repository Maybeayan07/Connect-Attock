# Connect Attock — Phase 2 Ride Sharing Plan

## Phase boundary

Implement only Module A: ride sharing. Do not implement payments, shopping, cargo or live GPS tracking. Payment remains a clearly labeled `awaiting_payment` state with an admin-only sandbox confirmation RPC gated by a database setting and a frontend environment flag.

## Backend approach

Use one additive migration, `202610310002_phase2_ride_sharing.sql`, without modifying the Phase 1 migration. The migration adds route locations, app settings, hold/OTP/reliability fields, aggregate provider rating fields, expanded booking statuses, indexes, transition-safe RLS and security-definer Postgres RPCs. All seat changes happen inside RPCs using `SELECT ... FOR UPDATE`; the frontend never calculates or mutates seat availability directly.

The principal RPC surface is: ride creation/update/publish/cancel; paginated published-ride search; sanitized ride detail; booking request/driver response/passenger or driver cancellation; unpaid-hold expiry; development-only admin confirmation; trip start; passenger OTP issue; driver drop-off OTP confirmation; passenger completion confirmation; driver no-show; ride review submission and review reporting. Booking transitions write history and in-app notifications in the same transaction.

Hold expiry is implemented as a database function with a documented Supabase `pg_cron` setup option. The app also exposes a safe manual/admin expiry action only where explicitly labeled. No production claim is made that cron is active until the user schedules it in Supabase.

## Frontend approach

Add feature files under `src/features/rides` and route pages for Find a Ride, ride details, Offer a Ride, provider rides/requests, vehicles, bookings and notifications. Use React Hook Form + Zod at all user input boundaries; RPCs perform server-side validation. Add Leaflet + OpenStreetMap for manual pickup/drop-off selection and route preview, with browser geolocation only after the standard permission prompt. A small OSRM wrapper calculates a development route preview/distance and is documented as demo/testing infrastructure.

Provider UI checks verification status and never presents a publish action as available for an unapproved driver. Passenger UI supports search filters, server pagination, detail/policy review, request/cancel, timeline and completion confirmation. Provider UI supports vehicle management, ride lifecycle, request accept/reject, OTP confirmation and no-show records. Notifications are in-app only with unread count, mark-read and Supabase Realtime subscription.

## Testing approach

Add Vitest tests for pure ride validation/status helpers and a SQL/static security test script that checks migration coverage and required RPC/lock/policy markers. Add a manual Supabase SQL test file for RLS and concurrency verification against a configured project. The report will distinguish tests actually run in this environment from tests that require the user's Supabase project and multiple authenticated sessions.
