-- Manual Phase 2 verification script. Run only in a disposable Supabase project with two authenticated test users.
-- Do not run against production data without an export/backup and explicit approval.
-- The RPCs below must be called through authenticated sessions; service-role calls bypass RLS and are not valid RLS tests.

-- 1. Approved provider gate: an unapproved provider must fail.
-- select public.create_ride('Rawalpindi','Attock', now() + interval '1 day', 2, 400, 'test', null, null, null, '[]'::jsonb);

-- 2. Passenger request policy: request without policy acceptance must fail.
-- select public.request_ride_booking('<published-ride-uuid>', 1, false);

-- 3. RLS isolation: as passenger A, this must return zero rows for passenger B's booking.
-- select * from public.ride_bookings where passenger_id = '<passenger-b-uuid>';

-- 4. Ownership isolation: as provider B, this must return zero rows for provider A's ride.
-- select * from public.rides where driver_id = '<provider-a-uuid>' and status = 'draft';

-- 5. Concurrent last-seat test: open two authenticated SQL sessions, both call request_ride_booking
-- for the same published ride with available_seats = 1. Exactly one call must succeed; the other must
-- fail with "Not enough seats available" or the active-booking guard. Verify available_seats = 1 until
-- a provider accepts, then = 0 after one accepted hold. This proves SELECT ... FOR UPDATE serialization.

-- 6. Hold expiry: set the test booking's hold_expires_at in the past as an admin/test fixture, then:
-- select public.expire_unpaid_ride_holds();
-- Verify the booking is expired and the ride's available_seats is released.

-- 7. Completion OTP: issue from the passenger session, submit an incorrect OTP five times from the
-- provider session, verify attempt_limit, then issue a fresh code and confirm it once. Verify reviews
-- fail before passenger completion and succeed exactly once after completion.
