# Connect Attock — Phase 1 TODO

## 1. Project foundation and design system

- [x] Create Vite + React + TypeScript foundation with feature-based folders, routing, Tailwind CSS and Lucide icons.
- [x] Establish navy primary, cyan accent, white/light-grey surfaces, modern typography, consistent spacing, premium cards, responsive mobile-first layout, accessible focus states and reduced-motion behavior.
- [x] Add shared navbar, footer, status badges, form primitives, loading/empty/error/success states and route manifest.

## 2. Public website

- [x] Implement homepage with the required hero copy, three service cards, Rawalpindi↔Attock route search surface, How It Works, Why Connect Attock, Safety & Verification, Popular Routes, Become a Provider, testimonials, FAQ and footer policies/contact.
- [x] Implement public pages: Find a Ride, Offer a Ride, Shopping, Cargo Delivery, How It Works, About, Contact, FAQ, Terms, Privacy, Cancellation & Refund Policy, and Prohibited Items Policy.
- [x] Keep later workflows honest: public service surfaces must explain that booking/payment/GPS workflows are staged and must not present static dummy data as real functionality.

## 3. Authentication and authorization

- [x] Implement signup with full name, email, phone, password + confirmation, and terms acceptance; login; logout; forgot/reset password; email verification messaging; Google OAuth entry point; session state; account deactivation affordance.
- [x] Implement protected routes and role-aware customer/provider/admin route guards without frontend-only claims.
- [x] Use Supabase Auth through public env vars only; never expose a service-role key or invent a logged-in user.

## 4. Database foundation and security

- [x] Add versioned Supabase/PostgreSQL migration for all requested tables: profiles, user_roles, driver_profiles, verification_documents, vehicles, rides, ride_stops, ride_bookings, shopping_offers, shopping_orders, shopping_order_items, cargo_offers, cargo_orders, payments, payment_transactions, refunds, settlements, commissions, reviews, reports, complaints, notifications, location_updates, booking_status_history, and audit_logs.
- [x] Use UUID primary keys, foreign keys, check constraints, indexes, numeric money fields, timestamps, controlled status enums, ownership triggers and security-definer helper functions.
- [x] Write RLS policies for every table; prevent user role escalation and keep verification documents private. Admin role changes are admin-only.
- [x] Document future platform-first sandbox payment adapter, GPS/Realtimе privacy boundaries, prohibited items, backup/recovery, and free-tier cost boundaries.

## 5. Profile settings

- [x] Connect profile settings to `profiles` with editable name, phone, avatar URL and notification preference fields, validation, loading/error/success states and account deactivation action.

## 6. Documentation and delivery

- [x] Add `.env.example`, setup/architecture/migration/deployment README and schema docs.
- [ ] Set up a real Supabase project URL/key, run the migration, configure Google OAuth redirect credentials, and verify email delivery.
- [ ] Run authenticated Supabase smoke tests against the user’s project after env configuration.
- [ ] Connect the project to the user’s GitHub repository through the managed GitHub confirmation flow if the user confirms the target.

## Phase 2 — Ride Sharing

- [x] Add a new versioned migration without editing the Phase 1 migration. Extend ride/booking statuses, add configurable route locations/settings, hold/OTP/reliability fields, safe indexes and RLS for rides, stops, bookings, vehicles, booking history, notifications and ride reviews.
- [x] Implement transactional Postgres RPCs with row locks for ride creation/update/publish/cancel, booking request/accept/reject/cancel/expiry, trip start/complete/no-show, review submission and dev-only sandbox confirmation. Seat availability must never be calculated or mutated in the frontend.
- [x] Implement provider ride publishing and management with approved-driver gating, saved vehicle management, stops, pickup/drop-off map selection, edit restrictions, cancellation reasons, requests, passenger list, trip lifecycle, OTP handoff and display-only earnings/history.
- [x] Implement passenger search with route/date/time filters, max fare, departure range, minimum seats, sorting and server-side pagination; ride detail with sanitized public driver/vehicle data, map route preview, policy acceptance, request/cancel and booking timeline.
- [x] Implement in-app notifications with unread count, mark-read, notifications page and Supabase Realtime updates for ride events.
- [x] Implement ride ratings after completed bookings only, one review per direction, aggregate driver rating updates and review reporting.
- [x] Add Leaflet/OpenStreetMap manual map selection and OSRM development route preview. Request browser location only through the standard permission prompt; block current-location actions when denied and document desktop accuracy/demo routing limits.
- [x] Add Vitest logic tests, migration/security static checks and a manual Supabase RLS/concurrency test script. Local tests and static checks pass; live Supabase/RLS/concurrency execution remains open until project credentials and test accounts are configured. Report untestable multi-user/GPS/cron behavior honestly.

## Explicitly not complete in Phase 1

- Ride publishing/search/request/acceptance/payment/booking/trip/GPS/rating workflows.
- Shopping offer/order/purchase/delivery workflows.
- Cargo request/availability/OTP/proof/tracking workflows.
- Live provider tracking, routing provider integration and Supabase Realtime event flows.
- Real payments, refunds, settlements, commissions and webhook verification.
- Provider verification review, admin operations, notifications, complaints, reports and analytics beyond schema/UI scaffolding.
