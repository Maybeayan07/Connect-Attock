

## Stabilization migration

Run `supabase/migrations/202611110001_stabilization.sql` after the previous migrations. It fixes provider submission for users without a pre-existing `driver_profiles` row, seeds the route-location catalog, adds `search_route_locations`, replaces the ride publish/update RPCs with enum-safe versions, exposes request/held/confirmed seat metrics, and adds `list_provider_rides`. It also sets the private verification bucket MIME and size limits.

Ride autocomplete uses the seeded catalog only. The optional `VITE_GEOCODER_URL` fallback is explicit-action only; do not use a public Nominatim endpoint for as-you-type requests. OpenStreetMap tiles and the public OSRM demo route preview remain development/testing integrations and must be replaced or approved before production scale.
