import { readFileSync } from 'node:fs'
const sql = readFileSync(new URL('../supabase/migrations/202610310002_phase2_ride_sharing.sql', import.meta.url), 'utf8')
const required = [
  'create table if not exists public.app_settings',
  'create table if not exists public.route_locations',
  "alter type public.ride_booking_status add value if not exists 'awaiting_payment'",
  'create or replace function public.request_ride_booking',
  'create or replace function public.driver_respond_ride_booking',
  'create or replace function public.expire_unpaid_ride_holds',
  'create or replace function public.dev_confirm_ride_booking',
  'create or replace function public.get_passenger_completion_otp',
  'create or replace function public.driver_confirm_passenger_dropoff',
  'create or replace function public.submit_ride_review',
  'for update',
  'create policy ride_bookings_participant_or_admin',
  'create policy booking_history_authorized',
]
const missing = required.filter((marker) => !sql.toLowerCase().includes(marker.toLowerCase()))
if (missing.length) { console.error('Missing Phase 2 markers:', missing); process.exit(1) }
for (const table of ['rides', 'ride_stops', 'ride_bookings', 'booking_status_history', 'notifications', 'reviews']) {
  if (!sql.includes(`public.${table}`)) { console.error(`Missing touched table marker: ${table}`); process.exit(1) }
}
console.log(`Phase 2 migration static audit passed: ${required.length} required markers, ${sql.split('\n').length} SQL lines.`)
