# Phase 3 Edge Functions

Deploy from the repository root after applying the Phase 3 migration:

```bash
supabase functions deploy create-checkout --no-verify-jwt
supabase functions deploy payment-webhook --no-verify-jwt
supabase functions deploy payment-status --no-verify-jwt
supabase functions deploy refund --no-verify-jwt
supabase functions deploy mock-payment-action --no-verify-jwt
supabase functions deploy settlement-action --no-verify-jwt
supabase secrets set PAYMENT_PROVIDER=mock PUBLIC_APP_URL=https://your-preview-or-site.example MOCK_WEBHOOK_SECRET='generate-a-long-random-value'
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are supplied by Supabase Edge Functions. Never put the service-role key in the frontend or `.env` files.

Optional future Safepay skeleton variables are intentionally not used until documented sandbox keys and current public API behavior are supplied: `SAFEPAY_CLIENT_ID`, `SAFEPAY_CLIENT_SECRET`, `SAFEPAY_API_BASE_URL`, `SAFEPAY_WEBHOOK_SECRET`. Do not set them as a claim that the adapter is tested.

The mock provider is sandbox-only. Its checkout page must show `SANDBOX — NO REAL MONEY`; success/failure/cancel/replay actions call `mock-payment-action`, which signs an event and calls `payment-webhook`. The webhook verifies timestamp and HMAC before the database RPC processes it.
