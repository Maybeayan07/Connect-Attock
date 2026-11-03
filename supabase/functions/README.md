# Phase 3 Edge Functions

Deploy from the repository root after applying the Phase 3 migration:

```bash
supabase functions deploy create-checkout
supabase functions deploy payment-webhook --no-verify-jwt
supabase functions deploy payment-status
supabase functions deploy refund
supabase functions deploy mock-payment-action
supabase functions deploy settlement-action
supabase secrets set PAYMENT_PROVIDER=mock ALLOW_MOCK_PAYMENTS=false PUBLIC_APP_URL=https://your-preview-or-site.example MOCK_WEBHOOK_SECRET='generate-a-long-random-value'
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase Edge Functions. Never put the service-role key in the frontend or `.env` files.

Optional future Safepay skeleton variables are intentionally not used until documented sandbox keys and current public API behavior are supplied: `SAFEPAY_CLIENT_ID`, `SAFEPAY_CLIENT_SECRET`, `SAFEPAY_API_BASE_URL`, `SAFEPAY_WEBHOOK_SECRET`. Do not set them as a claim that the adapter is tested.

The mock provider is sandbox-only. Its checkout page must show `SANDBOX — NO REAL MONEY`; success/failure/cancel/replay actions call `mock-payment-action`, which signs an event and calls `payment-webhook`. The webhook verifies timestamp and HMAC before the database RPC processes it.

## Caller authentication and authorization

- `create-checkout`: Supabase JWT is verified by `requireUser`; the authenticated user is passed to the locked checkout RPC as payer.
- `payment-status`: Supabase JWT is verified by `requireUser`; the caller may read only their payer-owned payment unless `isAdmin` confirms the admin role.
- `refund`: Supabase JWT is verified by `requireUser`; `isAdmin` is checked server-side before any refund RPC.
- `settlement-action`: Supabase JWT is verified by `requireUser`; `isAdmin` is checked server-side before marking a settlement paid.
- `mock-payment-action`: Supabase JWT is verified by `requireUser`, the payer/admin ownership check is enforced, and it fails closed unless `ALLOW_MOCK_PAYMENTS=true`.
- `payment-webhook`: deployed with `--no-verify-jwt` because the provider cannot send a user JWT; the raw body timestamp and HMAC signature are verified before the locked service-role RPC.

Set `ALLOW_MOCK_PAYMENTS=false` or remove it outside a disposable test project. Never enable Mock Sandbox actions in production.
