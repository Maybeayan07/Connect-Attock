

## Phase 2 migration

`supabase/migrations/202610310002_phase2_ride_sharing.sql` is additive and must run after the Phase 1 migration. It does not rewrite the old migration. It adds `app_settings` for hold/cancellation/start/OTP configuration and `route_locations` for the configured Rawalpindi ↔ Attock route.

The ride flow uses the existing `rides`, `ride_stops`, `ride_bookings`, `vehicles`, `notifications`, `booking_status_history` and `reviews` tables with new hold, cancellation, OTP, completion and provider aggregate fields. Booking states include requested, accepted, awaiting_payment, confirmed, rejected, cancelled_by_passenger, cancelled_by_driver, expired, completed and no_show. The legacy `payment_pending`/`cancelled` enum values remain for compatibility but are not used by the new RPC flow.

## Seat safety and transitions

The browser never performs seat arithmetic. `request_ride_booking`, `driver_respond_ride_booking`, `cancel_ride_booking`, `cancel_ride`, and `expire_unpaid_ride_holds` lock the relevant ride/booking rows and update seats inside a transaction. Provider acceptance records an `accepted` history event, immediately enters the clearly labelled `awaiting_payment` state and stores a default 15-minute hold. `expire_unpaid_ride_holds()` releases held seats and creates history/notifications. Schedule it through reviewed Supabase `pg_cron` configuration; the migration only supplies the safe callable function.

## OTP and completion

A passenger can issue a short OTP while a ride is in progress. Only the SHA-256 hash and expiry are stored. The driver submits the code through `driver_confirm_passenger_dropoff`; wrong attempts are counted and capped. The passenger then confirms completion, after which the booking is eligible for one passenger-to-driver and one driver-to-passenger review. Driver aggregate rating and completed-trip counters update inside the review/completion functions.

## RLS and public data

Ride reads expose published/full/in-progress/completed ride rows and stops, while private booking rows are limited to the passenger, the ride driver or an admin. Direct writes for ride transitions, bookings, booking history and reviews are removed or admin-only; authenticated clients use the security-definer RPCs. `get_ride_detail` returns only public driver profile fields and vehicle details, never verification documents or private storage paths. Notifications are owner-readable and should be added to Supabase Realtime publication by the project owner.

## Manual verification

Use `supabase/tests/phase2_ride_sharing_manual.sql` with two authenticated users to verify approved-provider gating, policy acceptance, passenger/driver RLS isolation, a concurrent last-seat request, hold expiry, OTP attempt limits and review uniqueness. Do not use a service-role client for RLS tests. The browser-level and real multi-device checks remain project-specific because the managed environment does not have the user's Supabase credentials.
