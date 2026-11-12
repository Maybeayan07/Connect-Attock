import { readFileSync } from 'node:fs'

const findRide = readFileSync('src/pages/rides/FindRidePage.tsx', 'utf8')
const offerRide = readFileSync('src/pages/rides/OfferRidePage.tsx', 'utf8')
const providerRides = readFileSync('src/pages/rides/ProviderPages.tsx', 'utf8')
const migration = readFileSync('supabase/migrations/202611110002_ride_search_timezone.sql', 'utf8')
const manualTest = readFileSync('supabase/tests/ride_visibility_timezone.sql', 'utf8')

const checks = [
  ['Find a Ride defaults origin to empty', /origin: params\.get\('from'\) \?\? ''/],
  ['Find a Ride defaults destination to empty', /destination: params\.get\('to'\) \?\? ''/],
  ['Find a Ride omits empty filters', /origin: parsed\.data\.origin \|\| undefined/],
  ['offer form converts Karachi local datetime', /rideLocalDateTimeToUtcIso\(values\.departureAt\)/],
  ['provider rides exposes publish action', /ride\.status === 'draft'.*Publish ride/s],
  ['search only returns published/full rides', /r\.status in \('published','full'\)/],
  ['search date uses Asia/Karachi', /r\.departure_at at time zone 'Asia\/Karachi'/],
  ['search time uses Asia/Karachi', /::time >= p_departure_from/],
  ['manual test checks another-user visibility', /different authenticated passenger sees both published rides/i],
  ['manual test checks midnight date boundaries', /23:55 belongs to Dec 31 and 00:05 belongs to Jan 1/i],
  ['manual test checks draft exclusion', /Draft is never returned|draft is never returned/i],
]
const failures = checks.filter(([, pattern]) => !pattern.test(pattern === checks[0]?.[1] ? findRide : `${findRide}\n${offerRide}\n${providerRides}\n${migration}\n${manualTest}`))
// The first three checks are scoped to Find a Ride; all remaining checks scan the combined contract.
const scopedFailures = checks.map(([label, pattern], index) => {
  const source = index < 3 ? findRide : `${offerRide}\n${providerRides}\n${migration}\n${manualTest}`
  return pattern.test(source) ? null : label
}).filter(Boolean)
if (scopedFailures.length) { console.error(`Ride search contract failed:\n- ${scopedFailures.join('\n- ')}`); process.exit(1) }
console.log(`Ride search contract passed (${checks.length} checks)`)
