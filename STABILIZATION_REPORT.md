# Connect Attock Stabilization Report

## Scope completed

This pass adds `supabase/migrations/202611110001_stabilization.sql` as a new additive migration. It does not edit the historical migrations.

The migration:

- makes `submit_provider_verification()` create the missing `driver_profiles` row safely, requires four distinct required document types, and returns the real verification status;
- seeds 40 route locations across the Attock–Rawalpindi corridor and adds the `search_route_locations(text, integer)` RPC;
- replaces `publish_ride()` and `update_ride()` with explicit `public.ride_status` casts, preserves a full ride as `full`, and blocks edits to in-progress/completed/cancelled rides;
- adds request, held-seat and confirmed-seat metrics to ride search/detail results and adds `list_provider_rides()`;
- sets private verification bucket MIME and size limits;
- adds a controlled optional geocoder wrapper. Seeded search is used for autocomplete; the configured fallback runs only after an explicit user action.

The frontend now lazy-loads Leaflet-dependent map modules, shows provider request/seat metrics, shows the provider verification status in the offer flow, and uses seeded place suggestions in the map picker.

## Required deployment order

Run the existing migrations in order, then run:

`supabase/migrations/202611110001_stabilization.sql`

After applying it, run `supabase/tests/rpc_enum_smoke.sql` in a disposable Supabase project. The smoke script now includes `search_route_locations()` and `list_provider_rides()`.

## Validation run in this environment

- `pnpm typecheck` passed.
- `pnpm build` passed. Leaflet is now emitted as a separate lazy chunk (`leaflet-CdWQ6Zil.js`); the main application chunk remains above the existing Vite warning threshold.
- `pnpm test -- --run` passed: 21 tests across 5 files.
- Phase 2 schema audit passed.
- Phase 3 security audit passed.
- Pre-Phase-4 audit passed.
- The enum-assignment audit passed after adding the two new RPC smoke calls.
- The managed development server served HTTP 200 for `/manus-routes.json` and the app shell on port 3000.

## Not run here

There is no live Supabase project, PostgreSQL server, `psql` client or Supabase CLI available in this environment. Therefore I could not execute the new migration, verify the provider-submission RPC against real auth/RLS, verify the seeded catalog in the database, run concurrent ride updates, or run the RPC smoke SQL against a real database. Browser geolocation, external geocoder responses, OpenStreetMap tile availability and OSRM routing were not exercised end-to-end.
