

## Verification upload fix

Run the additive migration `supabase/migrations/202611080001_verification_storage_upload_fixes.sql` after `202611030001_pre_phase4_fixes.sql`. It keeps `verification-documents` private, configures bucket MIME/size limits, removes metadata-dependent INSERT checks, and enables safe owner replacement for pending or rejected documents. Validate a disposable Supabase project with `supabase/tests/verification_storage_rls.sql`. See [`VERIFICATION_UPLOAD_FIX_REPORT.md`](./VERIFICATION_UPLOAD_FIX_REPORT.md) for the exact scope and untested live-database boundaries.
