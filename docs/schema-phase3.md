# Phase 3 schema notes

The Phase 3 migration is `supabase/migrations/202611010001_phase3_sandbox_payments.sql`. It is additive and must run after the Phase 1 and Phase 2 migrations.

`payments` gains service-polymorphic identifiers, payer/provider references, checkout/expiry timestamps, commission snapshots and under-review reasons. `payment_transactions` is an append-only webhook/attempt ledger with unique provider event IDs and signature-verified markers. `refunds` stores requested/processed actors and provider references. `payment_commission_settings` stores admin-editable ride/shopping/cargo defaults; the rate and fixed amount are copied to each payment so later changes do not rewrite history. `settlements` gains a unique ride-booking reference and becomes eligible only from the completed-booking trigger.

Browser roles can read only their own payments/transactions/refunds, providers can read their own settlement/commission rows without payer payment details, and admins can read all. Browser inserts/updates/deletes are revoked. Edge Functions use the service role and locked database RPCs. The old development confirmation function remains physically present for migration compatibility but its execute privilege is revoked from `anon` and `authenticated`, and the frontend no longer references it.

The webhook RPC locks payment and booking rows, rejects amount/currency mismatch into `under_review`, records duplicate provider events as no-ops, and never confirms a booking after the hold expires. Cancellation and completion triggers create refund requests and settlements without trusting browser state.
