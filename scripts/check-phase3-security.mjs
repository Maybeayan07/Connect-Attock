import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
const root = new URL('..', import.meta.url).pathname
const appFiles = []
function walk(dir) { for (const entry of readdirSync(dir, { withFileTypes: true })) { const path = join(dir, entry.name); if (entry.isDirectory() && !['node_modules','dist','.git'].includes(entry.name)) walk(path); else if (/\.(ts|tsx|js|mjs)$/.test(entry.name)) appFiles.push(path) } }
walk(join(root, 'src'))
const app = appFiles.map((path) => readFileSync(path, 'utf8')).join('\n')
const migration = readFileSync(join(root, 'supabase/migrations/202611010001_phase3_sandbox_payments.sql'), 'utf8')
const forbiddenClientConfirm = /devConfirmRideBooking|Mark confirmed for testing/.test(app)
const required = ['payment_create_checkout', 'payment_process_webhook', 'payment_request_refund', 'payment_process_refund', 'revoke execute on function public.dev_confirm_ride_booking', 'payments_one_active_service_idx', 'payment_transactions_no_update', 'hold expiry']
const missing = required.filter((marker) => !migration.toLowerCase().includes(marker.toLowerCase()))
if (forbiddenClientConfirm) { console.error('Client confirmation path still exists'); process.exit(1) }
if (missing.length) { console.error('Missing Phase 3 security markers:', missing); process.exit(1) }
console.log(`Phase 3 static security audit passed: ${appFiles.length} source files scanned, ${required.length} migration markers found.`)
