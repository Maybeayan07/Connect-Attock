import { readFileSync } from 'node:fs'
const migration = readFileSync('supabase/migrations/202611030001_pre_phase4_fixes.sql', 'utf8')
const functions = readFileSync('supabase/functions/_shared/payment.ts', 'utf8') + readFileSync('supabase/functions/mock-payment-action/index.ts', 'utf8')
const docs = readFileSync('supabase/functions/README.md', 'utf8') + readFileSync('docs/payments.md', 'utf8')
const required = ['protect_profile_fields', 'protect_driver_profile_fields', 'protect_vehicle_fields', 'protect_role_fields', 'verification-documents', 'submit_provider_verification', 'admin_review_provider', 'admin_review_vehicle', 'ALLOW_MOCK_PAYMENTS']
const missing = required.filter((marker) => !migration.includes(marker) && !functions.includes(marker))
const badDeploys = (docs.match(/supabase functions deploy [^\n]+--no-verify-jwt/g) ?? []).filter((line) => !line.includes('payment-webhook'))
if (missing.length || badDeploys.length || !functions.includes('Mock payments are disabled')) { console.error({ missing, badDeploys }); process.exit(1) }
console.log('Pre-Phase-4 static audit passed: table-safe triggers, verification RPC markers, private mock guard and JWT deployment rules found.')
