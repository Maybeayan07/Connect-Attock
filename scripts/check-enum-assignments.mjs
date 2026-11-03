import { readFileSync, readdirSync } from 'node:fs'

const files = readdirSync('supabase/migrations').filter((file) => file.endsWith('.sql')).map((file) => `supabase/migrations/${file}`).sort()
const source = files.map((file) => readFileSync(file, 'utf8')).join('\n')
const fix = readFileSync('supabase/migrations/202611030002_enum_assignment_fixes.sql', 'utf8')
const smoke = readFileSync('supabase/tests/rpc_enum_smoke.sql', 'utf8')
const enumColumns = ['rides.status', 'ride_bookings.status', 'booking_status_history.from_status', 'booking_status_history.to_status', 'payment_transactions.status', 'payments.status', 'refunds.status', 'settlements.status', 'vehicles.status', 'driver_profiles.verification_status', 'verification_documents.status', 'user_roles.role']
const triggerOnly = new Set(['set_updated_at', 'handle_new_user', 'prevent_protected_status_changes', 'validate_ride_row', 'payment_append_only_guard', 'payment_on_booking_cancel', 'payment_on_booking_completed', 'payment_commission_settings_audit', 'ca_is_authenticated_user', 'protect_profile_fields', 'protect_driver_profile_fields', 'protect_vehicle_fields', 'protect_role_fields'])
const allFunctions = [...source.matchAll(/create or replace function public\.([a-z0-9_]+)\s*\(/gi)].map((match) => match[1])
const affectedFunctions = {
  publish_ride: 'public.ride_status', update_ride: 'public.ride_status', record_ride_booking_event: 'public.ride_booking_status',
  driver_respond_ride_booking: 'public.ride_status', expire_unpaid_ride_holds: 'public.ride_status', cancel_ride_booking: 'public.ride_status',
  payment_process_webhook: 'public.payment_status', payment_process_refund: 'public.payment_status', admin_review_vehicle: 'public.vehicle_status'
}
const missing = Object.entries(affectedFunctions).filter(([name, type]) => !new RegExp(`create or replace function public\\.${name}\\b`).test(fix) || !fix.includes(`::${type}`)).map(([name]) => name)
const riskyPattern = /status\s*=\s*case[\s\S]{0,260}?end/gi
const risky = [...source.matchAll(riskyPattern)].map((m) => m[0].replace(/\s+/g, ' ').slice(0, 180))
const missingSmoke = Object.keys(affectedFunctions).filter((name) => !new RegExp(`public\\.${name}\\s*\\(`).test(smoke))
const missingRpcSmoke = [...new Set(allFunctions)].filter((name) => !triggerOnly.has(name) && !new RegExp(`public\\.${name}\\s*\\(`).test(smoke))
const oldMigrationTouched = files.filter((file) => file.includes('202611030002_enum_assignment_fixes.sql'))
if (missing.length || missingSmoke.length || missingRpcSmoke.length || oldMigrationTouched.length !== 1 || !risky.length) {
  console.error(JSON.stringify({ missing, missingSmoke, missingRpcSmoke, riskyCount: risky.length, oldMigrationTouched }, null, 2))
  process.exit(1)
}
console.log(`Enum assignment audit passed: ${enumColumns.length} protected enum columns inventoried, ${risky.length} historical risky CASE assignment(s) detected, and additive overrides/smoke calls are present.`)
