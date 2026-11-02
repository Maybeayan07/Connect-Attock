# Connect Attock — Phase 3 Sandbox Payments Report

## 1. Implemented scope and how to try the Mock provider

Phase 3 replaces the browser DEV confirmation path with a server-authoritative sandbox payment flow for ride bookings. Provider acceptance remains `awaiting_payment`; the passenger sees a fare/platform-fee/total breakdown and hold countdown, starts checkout through the `create-checkout` Edge Function, and is sent to a clearly labelled **SANDBOX — NO REAL MONEY** Mock checkout page. The Mock page exposes Success, Failure, Cancel and Replay actions. Those actions create signed HMAC webhook requests to `payment-webhook`; the webhook verifies freshness/signature, normalizes the event and calls the locked database RPC. The browser never sets a payment or booking to succeeded/confirmed.

Payment return polling reads the server-side status and does not trust URL parameters. Passenger payment history, provider earnings, minimal admin payment/refund/settlement/settings screens and notifications are wired. The additive migration adds service-polymorphic payment identifiers, active-payment/idempotency indexes, append-only transaction protection, commission snapshots, refund constraints, per-booking settlements and cancellation/completion triggers. Safepay is an explicit untested skeleton; JazzCash and Easypaisa are documented extension points only.

The intended try-it sequence after Supabase setup is: create an approved provider and passenger, publish a ride, request a seat, accept it, click `Pay in Sandbox Checkout`, choose Success, return to the status page and observe confirmation only after the webhook updates the database. Choose Failure/Cancel to verify retry states. Choose Replay after Success to exercise duplicate event handling.

## 2. Validation actually run

- `pnpm typecheck` — passed.
- `pnpm test -- --run` — passed: 12 tests across ride validation and payment calculations/security helpers.
- `pnpm test:phase2-schema` — passed.
- `pnpm test:phase3-security` — passed: 40 source files scanned; required server-only payment markers found.
- `pnpm build` — passed. Vite emitted the existing React Router `use client` directive warning and large-bundle advisory; no build error occurred.
- Route manifest validation — passed with 34 routes, including payment return, Mock checkout, history, earnings and admin routes.
- `git diff --check` — passed.
- Phase 1 migration — unchanged.
- Browser source scan — no remaining `devConfirmRideBooking`, DEV confirmation label, or `VITE_ENABLE_DEV_RIDE_CONFIRM` reference.
- Secret-name scan — no service-role key or Mock HMAC secret reference in `src` browser code.

## 3. Not tested or limited

The Mock provider has not been run against a deployed Supabase Edge Function in this environment. Deno and the Supabase CLI are not installed here, and no user Supabase project URL, Edge secrets, Auth users or database test sessions are configured. Therefore I do not claim that Edge Function deployment, HMAC delivery, live RLS, PostgreSQL migration execution, concurrent webhook locking, duplicate webhook delivery, hold-expiry refund race, provider refund call, Realtime notifications, pg_cron, admin role checks or multi-user isolation have passed.

Safepay has not been tested and is intentionally not claimed to work. Real money, real refunds, real payouts, merchant approval, tax/legal review and production provider webhooks are not implemented. The platform commission settings UI writes through admin RLS and an audit trigger, but the full admin panel is not part of this phase. The public OSRM route preview remains development infrastructure.

## 4. Known risks and follow-up items

The migration must be run carefully because the Supabase database is shared by development and production. Test the Phase 3 migration on a disposable/exported project first. The Mock Edge Function uses a short-lived in-memory checkout rate limiter per Edge instance; production abuse prevention should use a durable distributed limiter. The payment ledger stores normalized safe webhook metadata and payload hashes rather than credential/card-bearing raw payloads. Before live provider adoption, verify the provider's current signature, currency, refund and settlement contract against official documentation.

## 5. Exact setup steps

1. Run migrations in order: Phase 1, Phase 2 and `supabase/migrations/202611010001_phase3_sandbox_payments.sql`.
2. Enable Realtime for `public.notifications` if it is not already enabled.
3. Configure Edge secrets without committing them:

```bash
supabase secrets set PAYMENT_PROVIDER=mock PUBLIC_APP_URL=https://your-site.example MOCK_WEBHOOK_SECRET='generate-a-long-random-server-secret'
```

Supabase supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Never put the service-role key or HMAC secret into browser `.env` files.

4. Deploy:

```bash
supabase functions deploy create-checkout --no-verify-jwt
supabase functions deploy payment-webhook --no-verify-jwt
supabase functions deploy payment-status --no-verify-jwt
supabase functions deploy refund --no-verify-jwt
supabase functions deploy mock-payment-action --no-verify-jwt
supabase functions deploy settlement-action --no-verify-jwt
```

5. Use two authenticated test accounts and run `supabase/tests/phase3_payments_manual.sql`, including wrong/missing/stale signatures, amount tampering, duplicate/concurrent webhooks, expired holds, retries, refund overage, RLS and settlement eligibility. Do not use the service role for RLS tests.
6. Keep `PAYMENT_PROVIDER=mock` and clearly label the environment as sandbox. Do not enable a real provider until merchant approval, legal/tax review, real settlement operations and a fully tested adapter are complete.

## Delivery boundary

Phase 3 changes are implemented and committed in the managed repository only. No GitHub transfer or push was attempted. Phase 4 shopping marketplace work has not started. Stop here for approval.
