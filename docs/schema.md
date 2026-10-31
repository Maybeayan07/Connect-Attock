# Connect Attock schema notes

The Phase 1 migration is `supabase/migrations/202610310001_phase1_foundation.sql`. It is intended for a Supabase PostgreSQL project and assumes Supabase Auth's `auth.users` table.

## Core ownership

`profiles` is one-to-one with `auth.users`. A trigger creates a default `customer` role after signup. `user_roles` is deliberately not editable by normal users; only admins can insert/update/delete roles. `driver_profiles`, `vehicles`, offers and service records carry explicit provider ownership. Admin checks use the `security definer` `has_role()` / `is_admin()` helpers with a fixed `search_path`.

## Service records

`rides` and `ride_bookings` prepare route, seat, price and booking state. `shopping_offers`, `shopping_orders` and `shopping_order_items` separate product cost, shopping fee and delivery charge. `cargo_offers` and `cargo_orders` include unique tracking numbers, standard/doorstep pricing fields, OTP hashes, photos and delivery status. Phase 2 must use server-side transactions when changing seats or accepting bookings so double booking/overbooking cannot occur.

## Money and auditability

All money is stored as `numeric(12,2)` with an explicit currency on payments. `payments` carries a unique idempotency key and references exactly one service record. `payment_transactions` holds provider references, event IDs and signature-verification state. Refunds, commissions and settlements have separate records so later sandbox payment adapters can be provider-independent and auditable.

## Privacy and RLS

Every application table has RLS enabled. Public visibility is limited to published offer/ride data; private participant data is limited to authorized users and admins. `verification_documents` only exposes owner/admin rows and is intended for a private Storage bucket with signed URLs. `location_updates` only exposes authorized booking participants or admins; later code must stop writing location updates when a job completes/cancels. The browser must request Geolocation permission normally and must not claim background tracking after closure.

## Admin and operational tables

`reviews`, `reports`, `complaints`, `notifications`, `booking_status_history` and `audit_logs` prepare moderation, communication and audit trails. Admin dashboards and workflows are not implemented in Phase 1; the policies are conservative by default.

## Migration safety

Run the migration once in the user's Supabase project. Development and production data share the same Supabase project, so do not run destructive SQL casually. Before a future migration that removes or rewrites data, take an available export/backup and get explicit approval. Additive migrations should be preferred.
