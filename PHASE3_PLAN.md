# Phase 3 — Sandbox Payments Plan

## Scope

Implement sandbox-only payment orchestration for ride bookings. Do not build shopping, cargo, live GPS or the full admin panel. Existing Phase 1 payment tables are extended additively; old migrations are not edited.

## Design

- **Provider adapter:** Deno Edge Function `_shared/payment.ts` defines `PaymentProvider`; `MockSandboxProvider` creates a clearly labelled hosted sandbox route and sends signed HMAC webhook events; `SafepaySandboxProvider` is an explicit untested skeleton that refuses to guess undocumented behavior; JazzCash/Easypaisa remain extension points.
- **Server authority:** `create-checkout`, `payment-webhook`, `payment-status`, `refund`, `mock-payment-action` and `settlement-action` Edge Functions use the user JWT for authorization and the service-role client only server-side. Browser code never confirms payment.
- **Database authority:** An additive migration adds service-polymorphic payment columns, idempotent active-payment indexes, append-only ledger/refund triggers, commission snapshots, settlement-per-booking fields, payment settings and locked RPCs for checkout creation, verified webhook processing, refunds and settlement eligibility/mark-paid.
- **Race handling:** webhook processing locks payment and booking rows. Success after hold expiry becomes `under_review` and creates an automatic refund request; it never confirms an expired booking. Duplicate provider events are no-ops by unique `provider_event_id`.
- **Frontend:** Booking pay step with fare/fee/total, policy and hold countdown; sandbox checkout page with Success/Failure/Cancel/Replay controls; return page polls server status; passenger payment history; provider earnings; minimal protected admin payment/refund/settlement/settings screens.
- **Testing:** Vitest calculation/security tests, static security checks, Edge Function unit-testable helpers, and an explicit manual Supabase/Edge test script. Real Safepay sandbox and authenticated multi-user/cron tests remain open unless credentials are supplied.

## Delivery

Make small meaningful commits in the managed repository only. Do not push to GitHub. At completion, stop after the Phase 3 report and remind the owner to request a fresh Git bundle.
