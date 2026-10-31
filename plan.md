# Connect Attock — Phase 1 Plan

## Implementation approach

Build a real React/TypeScript/Vite frontend with a feature-based structure and Supabase-ready auth/data boundaries. Phase 1 delivers the public marketing surface, draft policy pages, auth UI and session wiring, protected dashboards, profile settings, and a complete versioned PostgreSQL schema/RLS migration for the later marketplace workflows. No Phase 2 ride workflow or fake booking/payment/GPS behavior is included.

The browser uses Supabase Auth when `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` are configured, with graceful configuration messaging otherwise. Client-side Zod validation is used at form boundaries. Server-side authorization is represented in the SQL migration with RLS, helper functions, protected storage guidance, and admin-only role mutation policies. The app never embeds a service-role key.

## Project structure

- `src/components/` — shared layout, brand, status, form and dashboard UI.
- `src/pages/` — home, public content, auth, protected dashboard and profile pages.
- `src/lib/` — Supabase client, validation schemas, shared utilities and navigation data.
- `src/hooks/` — auth/session state.
- `supabase/migrations/` — versioned Phase 1 schema, enums, indexes, triggers and RLS.
- `docs/` — schema and deployment notes.
- `public/` — route manifest and favicon/brand assets.

## Design direction

### Considered styles

- **Route Ledger Modernism** (0.06): editorial transport-signage structure with precise dividers and utility labels.
- **Coastal Utility** (0.04): airy civic-tech surfaces with cyan navigation cues and calm navy anchors.
- **Night Route Premium** (0.08): dark-to-light journey palette with luminous route lines and high-contrast cards.

### Chosen: Route Ledger Modernism

**Design Movement:** Contemporary civic mobility product with editorial wayfinding and transport-board precision.

**Core Principles:** Trust before transaction; clarity at every route; practical warmth; mobile-first reachability.

**Color Philosophy:** Deep navy carries safety and reliability; cyan is an ownable route signal used sparingly for action and motion; warm off-white keeps the product human and legible rather than corporate or overly glossy.

**Layout Paradigm:** Offset editorial sections, route-line dividers, asymmetric hero copy paired with a route-status card, and full-width bands that feel like a connected city map rather than a centered template grid.

**Signature Elements:** Cyan route-line motif, compact uppercase wayfinding labels, and rounded cards with a subtle “departure board” status treatment.

**Interaction Philosophy:** Every interactive surface states what happens next. Buttons use direct verbs, forms expose requirements before submit, and navigation preserves the current journey with visible active states.

**Animation:** Short, low-amplitude entrance transitions; route-line draw and card lift on hover; no motion required for comprehension; respect `prefers-reduced-motion`.

**Typography System:** Inter for UI and body copy, Space Grotesk for headlines and wordmark. Headings are tight, confident and sentence-cased; labels use compact uppercase tracking.

**Brand Essence:** A trusted city-to-city connection layer for people moving between Rawalpindi and Attock. Personality: grounded, capable, neighbourly.

**Brand Voice:** Plainspoken and reassuring. Example lines: “Make the route work harder.” “Verified people, clearer handoffs.”

**Wordmark & Logo:** A compact “CA” route-marker monogram: two offset rounded blocks joined by a cyan path, paired with the Connect Attock wordmark.

**Signature Brand Color:** Route Cyan `#28D8E5`.

## Scope boundary

Phase 1 stops after foundation, UI, auth, profile, migration/RLS scaffolding, documentation and validation. Ride publishing/search/booking, shopping orders, cargo requests, payments, GPS/realtime location, ratings, notifications, provider verification workflows, admin operations and complaints remain Phase 2+ work even though their database tables and statuses are prepared.

## Delivery workflow

1. Install pinned dependencies and configure TypeScript diagnostics.
2. Implement brand system, route manifest, shared layout and all Phase 1 routes.
3. Implement Supabase client, auth provider, guarded routes, auth forms and profile settings.
4. Add complete SQL migration, schema notes, `.env.example`, README and phase report.
5. Run typecheck/build and inspect the app through Preview once the server is listening.
6. Commit the Phase 1 checkpoint. GitHub canonical transfer is only completed after the owner confirms the platform card.
