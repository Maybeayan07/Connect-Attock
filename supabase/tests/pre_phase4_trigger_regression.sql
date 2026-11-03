-- Pre-Phase-4 trigger/RLS regression checks.
-- Exact command in a disposable Supabase project:
--   supabase db reset
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/seed_test_users.sql
--   psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/pre_phase4_trigger_regression.sql
-- Expected final output: all PASS notices and no uncaught ERROR.
-- The seed script must be edited with the test email prefix first.


do $$
declare v_admin uuid; v_driver uuid; v_passenger uuid; v_vehicle uuid; v_profile_before public.profiles%rowtype;
begin
  select id into v_admin from auth.users where email like '%+admin@gmail.com' limit 1;
  select id into v_driver from auth.users where email like '%+driver@gmail.com' limit 1;
  select id into v_passenger from auth.users where email like '%+passenger1@gmail.com' limit 1;
  select id into v_vehicle from public.vehicles where provider_id=v_driver limit 1;
  if v_admin is null or v_driver is null or v_passenger is null or v_vehicle is null then raise exception 'Seed accounts/vehicle missing'; end if;

  -- Signup trigger expectation: every signed-up user has a profile and customer role.
  if not exists (select 1 from public.profiles where id=v_passenger) or not exists (select 1 from public.user_roles where user_id=v_passenger and role='customer') then raise exception 'FAIL signup profile/customer role'; end if;
  raise notice 'PASS signup creates profile and customer role';

  -- Normal user cannot change provider verification status, vehicle status or roles.
  perform set_config('request.jwt.claim.sub', v_driver::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  begin update public.driver_profiles set verification_status='approved' where user_id=v_driver; raise exception 'FAIL normal user changed verification_status'; exception when others then raise notice 'PASS normal user cannot change verification_status'; end;
  begin update public.vehicles set status='rejected' where id=v_vehicle; raise exception 'FAIL normal user changed vehicle status'; exception when others then raise notice 'PASS normal user cannot change vehicle status'; end;
  begin update public.user_roles set role='admin' where user_id=v_driver and role='service_provider'; raise exception 'FAIL normal user changed role'; exception when others then raise notice 'PASS normal user cannot change role'; end;

  -- Admin can perform the protected maintenance actions.
  perform set_config('request.jwt.claim.sub', v_admin::text, true), set_config('request.jwt.claim.role', 'authenticated', true);
  update public.driver_profiles set verification_status='approved' where user_id=v_driver;
  update public.vehicles set status='approved' where id=v_vehicle;
  raise notice 'PASS admin can update provider and vehicle review fields';
end $$;

-- Database-only concurrency, payment webhook, over-refund, ledger append-only and
-- last-seat tests remain in phase3_payments_manual.sql and phase2_ride_sharing_manual.sql.
-- Run those scripts with two authenticated sessions; they intentionally cannot be
-- proven by this single-session SQL file.
