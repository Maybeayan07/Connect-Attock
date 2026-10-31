# Connect Attock

Connect Attock is a route-aware marketplace foundation for people moving between Rawalpindi and Attock: **Travel. Shop. Send.** Phase 1 delivers the product foundation, brand system, public pages, Supabase-ready authentication, protected dashboard/profile settings, and the complete database/RLS scaffolding for later service workflows.

## What works in Phase 1

The Vite + React + TypeScript app includes a responsive navy/cyan design system, shared navigation and footer, homepage, public service pages, How It Works, About, Contact, FAQ and draft policy pages. Auth screens cover signup, login, Google OAuth entry point, forgot/reset password, email verification messaging, protected routes, logout and account deactivation. When Supabase env vars are configured, account actions use the real Supabase Auth client; without them, the UI explains what must be configured instead of inventing a session. The profile screen reads and updates `profiles` through RLS.

The migration under `supabase/migrations/` creates every requested Phase 1 table, controlled statuses, UUID keys, constraints, indexes, timestamps, profile/role triggers, admin helper functions and restrictive RLS policies. Sensitive verification documents are designed for a private Storage bucket and signed URLs.

## What is intentionally not complete

Phase 2 ride publishing/search/request/acceptance/seat reservation/trip/GPS flows are not implemented. Shopping, cargo, real payments, provider verification review, notifications, ratings, complaints, admin operations and Realtime location sharing are also not implemented. The public pages describe these as later workflows and do not pretend that a button created a booking or payment.

## Local setup

1. Create a Supabase project on the free tier.
2. Copy `.env.example` to `.env.local` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` with the browser-safe values from Supabase Project Settings → API.
3. Open the Supabase SQL editor and run `supabase/migrations/202610310001_phase1_foundation.sql`.
4. In Supabase Auth, enable Email provider and configure the Site URL plus redirect URLs for the local dev URL and deployed Vercel URL. Enable Google provider only after creating Google OAuth credentials; use the Supabase callback URL shown in its provider settings.
5. Install and run:

```bash
pnpm install
pnpm dev
```

The app runs on port 5173 locally. Use `pnpm typecheck` and `pnpm build` for checks.

## Environment variables

Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` belong in the browser. Never expose a Supabase service-role key, database password, payment secret, webhook secret or private document URL in `VITE_*` variables. Future payment/GPS Edge Functions will use server-side secrets and verified callbacks.

## Architecture

- `src/layouts` contains the shared responsive shell.
- `src/components` contains reusable brand, route, form and state primitives.
- `src/pages` contains public, auth and protected surfaces.
- `src/hooks/useAuth.tsx` owns Supabase session/profile state.
- `src/lib` contains Supabase client setup, validation and shared navigation metadata.
- `supabase/migrations` is the versioned data/security boundary.
- `public/manus-routes.json` lists all application routes for managed hosting.

The design uses Route Ledger Modernism: editorial wayfinding, deep navy safety anchors, Route Cyan action signals, and compact status language. Animations are low-amplitude and disabled for reduced-motion preferences.

## Free-tier constraints and future cost notes

The project uses free-tier-friendly Supabase, Vercel, GitHub, Leaflet and OpenStreetMap as requested. Public OSM routing/demo servers are for development/testing only and require responsible usage; production routing may need a hosted provider. SMS OTP, payment gateways such as JazzCash/Safepay/Easypaisa, email volume beyond provider limits, custom domains and higher database/storage/egress usage may cost money later. Phase 1 uses no paid service and no real-money payment.

## Deployment

For Vercel, import the repository, set the two `VITE_*` variables, build with `pnpm build` and publish the `dist` directory. Configure Supabase Auth redirect URLs for the final Vercel URL. Connect Attock's managed project checkpoint should be pushed to the user's GitHub through the Webdev GitHub confirmation flow rather than by pasting secrets or creating a separate unmanaged repository.

## Validation record

Phase 1 was checked with source inspection, TypeScript diagnostics, `pnpm typecheck` and `pnpm build`. Live Auth/Profile smoke tests remain blocked until the user's Supabase project URL/key, email settings and optional Google OAuth credentials are configured. Phase 2 should begin only after approval of this foundation.
