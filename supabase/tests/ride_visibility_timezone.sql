-- Disposable Supabase regression test. Never run against production.
-- Prerequisites: run seed_test_users.sql and replace the email prefix below.
-- Execute in one SQL session with permission to set request.jwt.claims.

do $$
declare
  v_driver uuid; v_passenger uuid; v_vehicle uuid;
  v_late uuid; v_early uuid; v_draft uuid;
  v_count bigint; v_date_count bigint; v_draft_count bigint;
begin
  select id into v_driver from auth.users where email = 'YOUR_EMAIL_PREFIX+driver@gmail.com';
  select id into v_passenger from auth.users where email = 'YOUR_EMAIL_PREFIX+passenger1@gmail.com';
  select id into v_vehicle from public.vehicles where provider_id = v_driver and status = 'approved' order by created_at limit 1;
  if v_driver is null or v_passenger is null or v_vehicle is null then raise exception 'Run seed_test_users.sql and set YOUR_EMAIL_PREFIX first'; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_driver, 'role', 'authenticated')::text, true);
  v_late := public.create_ride('Rawalpindi','Attock', timezone('Asia/Karachi', timestamp '2026-12-31 23:55'), 3, 400, 'timezone late', v_vehicle, null, null, '[]'::jsonb);
  v_early := public.create_ride('Rawalpindi','Attock', timezone('Asia/Karachi', timestamp '2027-01-01 00:05'), 3, 400, 'timezone early', v_vehicle, null, null, '[]'::jsonb);
  v_draft := public.create_ride('Attock','Rawalpindi', timezone('Asia/Karachi', timestamp '2027-01-01 10:00'), 3, 400, 'draft must stay private', v_vehicle, null, null, '[]'::jsonb);
  perform public.publish_ride(v_late);
  perform public.publish_ride(v_early);

  -- A different authenticated passenger sees both published rides through the no-filter search.
  perform set_config('request.jwt.claims', json_build_object('sub', v_passenger, 'role', 'authenticated')::text, true);
  select count(*) into v_count from public.search_published_rides(null, null, null, null, null, null, 1, 'earliest', 1, 50) where id in (v_late, v_early);
  if v_count <> 2 then raise exception 'Published rides were not visible to another user; expected 2, got %', v_count; end if;

  -- The local date is Asia/Karachi: 23:55 belongs to Dec 31 and 00:05 belongs to Jan 1.
  select count(*) into v_date_count from public.search_published_rides(null, null, date '2026-12-31', null, null, null, 1, 'earliest', 1, 50) where id = v_late;
  if v_date_count <> 1 then raise exception 'Asia/Karachi Dec 31 date filter missed the 23:55 ride'; end if;
  select count(*) into v_date_count from public.search_published_rides(null, null, date '2027-01-01', null, null, null, 1, 'earliest', 1, 50) where id = v_early;
  if v_date_count <> 1 then raise exception 'Asia/Karachi Jan 1 date filter missed the 00:05 ride'; end if;

  -- A draft is never returned to passengers, even when route/date otherwise match.
  select count(*) into v_draft_count from public.search_published_rides(null, null, date '2027-01-01', null, null, null, 1, 'earliest', 1, 50) where id = v_draft;
  if v_draft_count <> 0 then raise exception 'Draft ride leaked into passenger search'; end if;

  raise notice 'PASS: published visibility, Karachi midnight date filters, and draft exclusion';
end $$;
