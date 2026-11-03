-- NEVER RUN THIS SCRIPT ON PRODUCTION.
-- Test project only. Replace YOUR_EMAIL_PREFIX with the local part used for the four test accounts.
-- It is idempotent and uses auth.users plus the real application columns.

do $$
declare
  v_admin uuid; v_driver uuid; v_passenger1 uuid; v_passenger2 uuid; v_vehicle uuid;
  v_prefix text := 'YOUR_EMAIL_PREFIX';
begin
  -- Look up the four already-signed-up test accounts in Supabase Auth.
  select id into v_admin from auth.users where email = v_prefix || '+admin@gmail.com';
  select id into v_driver from auth.users where email = v_prefix || '+driver@gmail.com';
  select id into v_passenger1 from auth.users where email = v_prefix || '+passenger1@gmail.com';
  select id into v_passenger2 from auth.users where email = v_prefix || '+passenger2@gmail.com';
  if v_admin is null or v_driver is null or v_passenger1 is null or v_passenger2 is null then raise exception 'All four test accounts must exist before running this seed'; end if;

  -- Make the first account an admin through the server-side role table.
  insert into public.user_roles(user_id, role) values (v_admin, 'admin') on conflict do nothing;
  -- Make the driver approved and review it as if an administrator completed verification.
  insert into public.driver_profiles(user_id, verification_status, reviewed_by, reviewed_at, rejection_reason)
    values (v_driver, 'approved', v_admin, timezone('utc', now()), null)
    on conflict (user_id) do update set verification_status='approved', reviewed_by=v_admin, reviewed_at=timezone('utc', now()), rejection_reason=null;
  insert into public.user_roles(user_id, role) values (v_driver, 'service_provider') on conflict do nothing;
  -- Create one realistic approved vehicle for the driver, without storing an unmasked registration.
  insert into public.vehicles(provider_id, make, model, year, color, registration_masked, seats, status)
    values (v_driver, 'Toyota', 'Corolla', 2021, 'White', 'ABC-***', 4, 'approved')
    on conflict do nothing;
  -- Keep both passenger accounts as ordinary customers and remove elevated roles if this seed was rerun after manual experiments.
  insert into public.user_roles(user_id, role) values (v_passenger1, 'customer') on conflict do nothing;
  insert into public.user_roles(user_id, role) values (v_passenger2, 'customer') on conflict do nothing;
  delete from public.user_roles where user_id in (v_passenger1, v_passenger2) and role <> 'customer';
  select id into v_vehicle from public.vehicles where provider_id=v_driver order by created_at limit 1;
  raise notice 'Seeded admin %, driver %, passengers %, %, vehicle %', v_admin, v_driver, v_passenger1, v_passenger2, v_vehicle;
end $$;
