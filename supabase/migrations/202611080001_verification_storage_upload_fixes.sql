-- Connect Attock additive verification upload fixes.
-- Run after 202611030001_pre_phase4_fixes.sql. Do not edit earlier migrations.

update storage.buckets
set public = false,
    allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf']::text[],
    file_size_limit = 10485760
where id = 'verification-documents';

-- The browser upload uses paths of the form <auth uid>/<document type>.<ext>.
-- MIME and size are enforced by bucket configuration, not object metadata,
-- which is not reliable during an INSERT policy check.
drop policy if exists verification_docs_object_owner_insert on storage.objects;
drop policy if exists verification_docs_object_owner_update on storage.objects;
drop policy if exists verification_docs_object_owner_delete on storage.objects;
create policy verification_docs_object_owner_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy verification_docs_object_owner_update on storage.objects for update to authenticated
using (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy verification_docs_object_owner_delete on storage.objects for delete to authenticated
using (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- Providers may replace their own pending document row. They cannot alter
-- review fields or another user's row.
drop policy if exists documents_delete_owner_safe on public.verification_documents;
drop policy if exists documents_update_owner_safe on public.verification_documents;
create policy documents_delete_owner_safe on public.verification_documents for delete to authenticated
using (user_id = auth.uid() and status in ('pending', 'rejected'));
create policy documents_update_owner_safe on public.verification_documents for update to authenticated
using (user_id = auth.uid() and status in ('pending', 'rejected') and reviewed_by is null and reviewed_at is null)
with check (user_id = auth.uid() and status = 'pending' and reviewed_by is null and reviewed_at is null);
