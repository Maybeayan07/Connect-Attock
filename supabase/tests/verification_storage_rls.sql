-- Verification storage regression test for a disposable Supabase project.
-- Run after seed_test_users.sql and 202611080001_verification_storage_upload_fixes.sql:
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/verification_storage_rls.sql
-- This exercises storage.objects RLS in SQL. The signed URL assertion uses the
-- storage schema helper and confirms an admin can create a short-lived URL.

do $$
declare v_admin uuid; v_driver uuid; v_other uuid; v_name text; v_count integer; v_signed jsonb;
begin
  select id into v_admin from auth.users where email like '%+admin@gmail.com' limit 1;
  select id into v_driver from auth.users where email like '%+driver@gmail.com' limit 1;
  select id into v_other from auth.users where email like '%+passenger1@gmail.com' limit 1;
  if v_admin is null or v_driver is null or v_other is null then raise exception 'Seed accounts missing'; end if;
  v_name := v_driver::text || '/identity.pdf';

  perform set_config('request.jwt.claim.sub', v_driver::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('verification-documents', v_name, v_driver, jsonb_build_object('mimetype','application/pdf','size',1024));
  raise notice 'PASS normal user can insert own verification object';

  perform set_config('request.jwt.claim.sub', v_other::text, true);
  select count(*) into v_count from storage.objects where bucket_id='verification-documents' and name=v_name;
  if v_count <> 0 then raise exception 'FAIL other user can read verification object'; end if;
  raise notice 'PASS normal user cannot read another user object';
  update storage.objects set metadata=jsonb_build_object('tampered',true) where bucket_id='verification-documents' and name=v_name;
  if found then raise exception 'FAIL other user can overwrite verification object'; end if;
  raise notice 'PASS normal user cannot overwrite another user object';

  perform set_config('request.jwt.claim.sub', v_admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  select count(*) into v_count from storage.objects where bucket_id='verification-documents' and name=v_name;
  if v_count <> 1 then raise exception 'FAIL admin cannot read verification object'; end if;
  raise notice 'PASS admin can read verification object';
  select storage.create_signed_url('verification-documents', v_name, 300)::jsonb into v_signed;
  if coalesce(v_signed->>'signedURL', v_signed->>'signedUrl', '') = '' then raise exception 'FAIL admin signed URL was not created'; end if;
  raise notice 'PASS admin can create a signed verification URL';

  delete from storage.objects where bucket_id='verification-documents' and name=v_name;
end $$;
