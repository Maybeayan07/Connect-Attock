# Verification Upload Fix Report

## Root cause

The provider page used the correct bucket name, `verification-documents`, and an owner-folder path, but the existing INSERT policy attempted to inspect `storage.objects.metadata->>'mimetype'` and `metadata->>'size'`. Those values are not reliable at object INSERT time, so valid uploads could be denied before the row was created. The client also generated a random filename for every upload, so replacing a document created another object/row instead of replacing the prior document. Finally, the page only displayed a generic fallback because PostgrestError and StorageError objects are not necessarily JavaScript `Error` instances.

## Required migration

Run this new additive migration after the existing pre-Phase-4 migration:

`supabase/migrations/202611080001_verification_storage_upload_fixes.sql`

It keeps the bucket private, sets `allowed_mime_types` and `file_size_limit` on the bucket, removes metadata-dependent storage checks, adds owner UPDATE/DELETE policies for replacement, and allows safe pending/rejected document-row replacement. Earlier migrations were not edited.

The client now uses the path `<user id>/<document type>.<extension>` and `upsert: true` for the storage object. It replaces the matching pending/rejected database row and cleans up older paths for the same document type. Approved rows remain protected by RLS.

## UI and error handling

Each document card now shows idle, uploading, uploaded with filename, or failed with the real error. Submit is disabled until all four document types exist. A shared `src/lib/errors.ts` helper handles native Error, PostgrestError-shaped and StorageError-shaped objects and is used across verification, rides, bookings, payments, admin and auth surfaces.

## Tests

- `pnpm typecheck` passed.
- `pnpm build` passed.
- Unit suite passed: 21 tests across 5 files, including four `getErrorMessage` tests.
- `supabase/tests/verification_storage_rls.sql` was added. It checks own-folder insert, cross-user read isolation, cross-user overwrite isolation, admin read access and admin signed URL creation.

The SQL RLS/signed-URL test was not run here because no live Supabase project, PostgreSQL server, `psql` client or Supabase CLI is available. Run it in a disposable project after `seed_test_users.sql` and the new migration. Browser upload/replacement was not exercised against a live bucket in this environment.
