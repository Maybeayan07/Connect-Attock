-- Enum-assignment RPC smoke test. Run only in a disposable Supabase project after
-- all migrations and test-user seed data are installed.
-- The calls intentionally use fixture UUIDs and may produce expected authorization
-- or missing-record errors. Any enum/text mismatch is re-raised and fails the test.
-- This is a call-coverage smoke test, not a substitute for RLS/concurrency tests.

create or replace function pg_temp.try_rpc(p_label text, p_sql text)
returns void language plpgsql as $$
declare v_text text;
begin
  execute p_sql into v_text;
  raise notice 'CALLED %', p_label;
exception when others then
  if sqlerrm ilike '%enum%' or sqlerrm ilike '%type text%' or sqlerrm ilike '%cannot cast%' or sqlerrm ilike '%invalid input value%' then
    raise;
  end if;
  raise notice 'CALLED % (expected fixture/auth error: %)', p_label, sqlerrm;
end; $$;

do $$
declare z uuid := '00000000-0000-0000-0000-000000000000';
begin
  perform pg_temp.try_rpc('has_role', $$select public.has_role('00000000-0000-0000-0000-000000000000'::uuid, 'customer'::public.app_role)$$);
  perform pg_temp.try_rpc('is_admin', $$select public.is_admin()$$);
  perform pg_temp.try_rpc('is_approved_provider', $$select public.is_approved_provider('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('ride_setting_int', $$select public.ride_setting_int('ride_hold_minutes', 15)$$);
  perform pg_temp.try_rpc('dev_ride_confirmation_enabled', $$select public.dev_ride_confirmation_enabled()$$);
  perform pg_temp.try_rpc('notify_ride_user', $$select public.notify_ride_user('00000000-0000-0000-0000-000000000000'::uuid, 'smoke', 'Smoke', 'Smoke', null)$$);
  perform pg_temp.try_rpc('record_ride_booking_event', $$select public.record_ride_booking_event('00000000-0000-0000-0000-000000000000'::uuid, null, 'requested', 'Smoke')$$);
  perform pg_temp.try_rpc('create_ride', $$select public.create_ride('Rawalpindi','Attock',timezone('utc',now()) + interval '1 day',2,400,'Smoke',null,null,null,'[]'::jsonb)$$);
  perform pg_temp.try_rpc('publish_ride', $$select public.publish_ride('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('update_ride', $$select public.update_ride('00000000-0000-0000-0000-000000000000'::uuid,'Rawalpindi','Attock',timezone('utc',now()) + interval '1 day',2,400,'Smoke',null,null,null,'[]'::jsonb)$$);
  perform pg_temp.try_rpc('cancel_ride', $$select public.cancel_ride('00000000-0000-0000-0000-000000000000'::uuid,'Smoke')$$);
  perform pg_temp.try_rpc('search_published_rides', $$select count(*) from public.search_published_rides(null,null,null,null,null,null,1,'earliest',1,10)$$);
  perform pg_temp.try_rpc('search_route_locations', $$select count(*) from public.search_route_locations('Attock',8)$$);
  perform pg_temp.try_rpc('list_provider_rides', $$select count(*) from public.list_provider_rides()$$);
  perform pg_temp.try_rpc('get_ride_detail', $$select public.get_ride_detail('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('request_ride_booking', $$select public.request_ride_booking('00000000-0000-0000-0000-000000000000'::uuid,1,true)$$);
  perform pg_temp.try_rpc('driver_respond_ride_booking', $$select public.driver_respond_ride_booking('00000000-0000-0000-0000-000000000000'::uuid,false,'Smoke')$$);
  perform pg_temp.try_rpc('expire_unpaid_ride_holds', $$select public.expire_unpaid_ride_holds()$$);
  perform pg_temp.try_rpc('dev_confirm_ride_booking', $$select public.dev_confirm_ride_booking('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('cancel_ride_booking', $$select public.cancel_ride_booking('00000000-0000-0000-0000-000000000000'::uuid,'Smoke')$$);
  perform pg_temp.try_rpc('start_ride', $$select public.start_ride('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('get_passenger_completion_otp', $$select public.get_passenger_completion_otp('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('driver_confirm_passenger_dropoff', $$select public.driver_confirm_passenger_dropoff('00000000-0000-0000-0000-000000000000'::uuid,'000000')$$);
  perform pg_temp.try_rpc('passenger_confirm_ride_completion', $$select public.passenger_confirm_ride_completion('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('complete_ride', $$select public.complete_ride('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('mark_ride_no_show', $$select public.mark_ride_no_show('00000000-0000-0000-0000-000000000000'::uuid,'Smoke')$$);
  perform pg_temp.try_rpc('submit_ride_review', $$select public.submit_ride_review('00000000-0000-0000-0000-000000000000'::uuid,z,5,'Smoke')$$);
  perform pg_temp.try_rpc('report_ride_review', $$select public.report_ride_review('00000000-0000-0000-0000-000000000000'::uuid,'Smoke','Smoke')$$);
  perform pg_temp.try_rpc('get_ride_booking_detail', $$select public.get_ride_booking_detail('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('get_provider_ride_requests', $$select public.get_provider_ride_requests('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('mark_notification_read', $$select public.mark_notification_read('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('payment_setting_num', $$select public.payment_setting_num('ride_commission_rate',0.1)$$);
  perform pg_temp.try_rpc('payment_is_admin', $$select public.payment_is_admin('00000000-0000-0000-0000-000000000000'::uuid)$$);
  perform pg_temp.try_rpc('payment_create_checkout', $$select public.payment_create_checkout(z,z,'smoke-idempotency','mock_sandbox')$$);
  perform pg_temp.try_rpc('payment_process_webhook', $$select public.payment_process_webhook('mock_sandbox','smoke-event-0001',z,'smoke-ref','payment.succeeded','failed',0,'PKR',true,'smoke-hash','{}'::jsonb)$$);
  perform pg_temp.try_rpc('payment_request_refund', $$select public.payment_request_refund(z,1,'Smoke',z)$$);
  perform pg_temp.try_rpc('payment_process_refund', $$select public.payment_process_refund(z,z,'Smoke',false)$$);
  perform pg_temp.try_rpc('payment_mark_settlement_paid', $$select public.payment_mark_settlement_paid(z,z,'Smoke')$$);
  perform pg_temp.try_rpc('ca_is_authenticated_user', $$select public.ca_is_authenticated_user()$$);
  perform pg_temp.try_rpc('deactivate_my_account', $$select public.deactivate_my_account()$$);
  perform pg_temp.try_rpc('submit_provider_verification', $$select public.submit_provider_verification()$$);
  perform pg_temp.try_rpc('admin_review_provider', $$select public.admin_review_provider(z,true,null)$$);
  perform pg_temp.try_rpc('admin_review_vehicle', $$select public.admin_review_vehicle(z,true,null)$$);
end $$;

-- Trigger-only functions are exercised indirectly by the table mutations in
-- phase2_ride_sharing_manual.sql, phase3_payments_manual.sql and
-- pre_phase4_trigger_regression.sql; they are intentionally not directly called.
