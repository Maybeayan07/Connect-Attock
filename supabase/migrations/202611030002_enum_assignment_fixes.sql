-- Connect Attock additive enum-assignment fixes.
-- Never edit or rerun the earlier migrations to apply this repair.
-- Run after 202611030001_pre_phase4_fixes.sql.

-- booking_status_history.from_status and to_status are enum columns. Keep the
-- public text signature for compatibility, but cast at the insert boundary.
create or replace function public.record_ride_booking_event(p_booking_id uuid, p_from text, p_to text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_passenger uuid; v_driver uuid; v_ride_id uuid; v_origin text; v_destination text; v_title text; v_body text;
begin
  select b.passenger_id, b.ride_id, r.driver_id, r.origin, r.destination into v_passenger, v_ride_id, v_driver, v_origin, v_destination
  from public.ride_bookings b join public.rides r on r.id = b.ride_id where b.id = p_booking_id;
  insert into public.booking_status_history (changed_by, ride_booking_id, from_status, to_status, note)
  values (auth.uid(), p_booking_id, nullif(p_from, '')::public.ride_booking_status, p_to::public.ride_booking_status, p_note);
  v_title := 'Ride booking updated'; v_body := format('%s → %s is now %s.', v_origin, v_destination, replace(p_to, '_', ' '));
  perform public.notify_ride_user(v_passenger, 'ride_booking_status', v_title, v_body, '/bookings/' || p_booking_id::text);
  if v_driver is distinct from auth.uid() then perform public.notify_ride_user(v_driver, 'ride_booking_status', v_title, v_body, '/provider/bookings/' || v_ride_id::text); end if;
end; $$;

create or replace function public.publish_ride(p_ride_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if v_ride.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if not public.is_approved_provider(auth.uid()) then raise exception 'Your provider verification is not approved'; end if;
  if v_ride.status <> 'draft' then raise exception 'Only draft rides can be published'; end if;
  if v_ride.departure_at <= timezone('utc', now()) then raise exception 'Departure must be in the future'; end if;
  if v_ride.vehicle_id is not null and not exists (select 1 from public.vehicles where id = v_ride.vehicle_id and provider_id = auth.uid() and status = 'approved') then raise exception 'The selected vehicle is not approved'; end if;
  update public.rides
  set status = (case when available_seats = 0 then 'full' else 'published' end)::public.ride_status,
      published_at = timezone('utc', now())
  where id = p_ride_id;
  return p_ride_id;
end; $$;

create or replace function public.update_ride(
  p_ride_id uuid, p_origin text, p_destination text, p_departure_at timestamptz, p_total_seats integer,
  p_price_per_seat numeric, p_description text default null, p_vehicle_id uuid default null,
  p_pickup_point jsonb default null, p_dropoff_point jsonb default null, p_stops jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_active integer; v_origin_id uuid; v_destination_id uuid; v_stop jsonb; v_index integer := 0;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if v_ride.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if v_ride.status not in ('draft','published','full') then raise exception 'Only draft, published or full rides can be edited'; end if;
  select count(*) into v_active from public.ride_bookings where ride_id = p_ride_id and status in ('accepted', 'awaiting_payment', 'confirmed');
  if v_active > 0 then raise exception 'Ride details cannot be edited while seats are held or confirmed'; end if;
  if p_departure_at <= timezone('utc', now()) then raise exception 'Departure must be in the future'; end if;
  if lower(trim(p_origin)) = lower(trim(p_destination)) then raise exception 'Origin and destination must be different'; end if;
  if p_total_seats < 1 or p_total_seats > 20 or p_total_seats < (v_ride.total_seats - v_ride.available_seats) then raise exception 'Seats cannot be lower than already requested seats'; end if;
  if p_price_per_seat < 0 then raise exception 'Fare cannot be negative'; end if;
  select id into v_origin_id from public.route_locations where lower(name) = lower(trim(p_origin)) and active = true;
  select id into v_destination_id from public.route_locations where lower(name) = lower(trim(p_destination)) and active = true;
  if v_origin_id is null or v_destination_id is null then raise exception 'This route location is not configured'; end if;
  if p_vehicle_id is not null and not exists (select 1 from public.vehicles where id = p_vehicle_id and provider_id = auth.uid() and status = 'approved') then raise exception 'Select one of your approved vehicles'; end if;
  update public.rides set origin=trim(p_origin), destination=trim(p_destination), route_origin_id=v_origin_id, route_destination_id=v_destination_id,
    departure_at=p_departure_at, total_seats=p_total_seats, available_seats=p_total_seats - (v_ride.total_seats - v_ride.available_seats),
    price_per_seat=p_price_per_seat, description=nullif(trim(p_description), ''), vehicle_id=p_vehicle_id, pickup_point=p_pickup_point, dropoff_point=p_dropoff_point,
    status=(case when v_ride.status = 'draft' then 'draft' when v_ride.status = 'full' then 'full' else 'published' end)::public.ride_status
  where id=p_ride_id;
  delete from public.ride_stops where ride_id = p_ride_id;
  for v_stop in select value from jsonb_array_elements(coalesce(p_stops, '[]'::jsonb)) loop
    insert into public.ride_stops (ride_id, stop_order, name, latitude, longitude, estimated_at)
    values (p_ride_id, v_index, trim(v_stop->>'name'), nullif(v_stop->>'latitude', '')::numeric, nullif(v_stop->>'longitude', '')::numeric, nullif(v_stop->>'estimated_at', '')::timestamptz);
    v_index := v_index + 1;
  end loop;
  return p_ride_id;
end; $$;

create or replace function public.driver_respond_ride_booking(p_booking_id uuid, p_accept boolean, p_reason text default null)
returns public.ride_booking_status language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_from text; v_hold timestamptz;
begin
  select r.* into v_ride from public.rides r join public.ride_bookings b on b.ride_id=r.id where b.id=p_booking_id for update;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  if v_booking.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Booking not found or not your ride'; end if;
  if v_booking.status <> 'requested' then raise exception 'Only requested bookings can be accepted or rejected'; end if;
  v_from := v_booking.status::text;
  if not p_accept then
    update public.ride_bookings set status='rejected', cancelled_at=timezone('utc', now()), cancellation_reason=nullif(trim(p_reason), '') where id=p_booking_id;
    perform public.record_ride_booking_event(p_booking_id, v_from, 'rejected', p_reason); return 'rejected';
  end if;
  if v_ride.available_seats < v_booking.seats_requested then raise exception 'Not enough seats remain'; end if;
  v_hold := timezone('utc', now()) + make_interval(mins => public.ride_setting_int('ride_hold_minutes', 15));
  update public.rides set available_seats=available_seats-v_booking.seats_requested,
    status=(case when available_seats-v_booking.seats_requested=0 then 'full' else status::text end)::public.ride_status where id=v_ride.id;
  update public.ride_bookings set status='accepted', hold_expires_at=v_hold, accepted_at=timezone('utc', now()) where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, v_from, 'accepted', 'Seats are temporarily held');
  update public.ride_bookings set status='awaiting_payment' where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, 'accepted', 'awaiting_payment', 'Payment is waiting for the sandbox checkout');
  return 'awaiting_payment';
end; $$;

create or replace function public.expire_unpaid_ride_holds()
returns integer language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_count integer := 0; v_ride public.rides%rowtype;
begin
  for v_booking in select * from public.ride_bookings where status='awaiting_payment' and hold_expires_at is not null and hold_expires_at < timezone('utc', now()) order by hold_expires_at for update skip locked loop
    select * into v_ride from public.rides where id=v_booking.ride_id for update;
    update public.rides set available_seats=least(total_seats, available_seats+v_booking.seats_requested),
      status=(case when status='full' then 'published' else status::text end)::public.ride_status where id=v_ride.id;
    update public.ride_bookings set status='expired', hold_expires_at=null where id=v_booking.id;
    perform public.record_ride_booking_event(v_booking.id, 'awaiting_payment', 'expired', 'The temporary seat hold expired'); v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

create or replace function public.cancel_ride_booking(p_booking_id uuid, p_reason text)
returns public.ride_booking_status language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_to public.ride_booking_status; v_late boolean; v_from text;
begin
  if nullif(trim(p_reason), '') is null then raise exception 'A cancellation reason is required'; end if;
  select r.* into v_ride from public.rides r join public.ride_bookings b on b.ride_id=r.id where b.id=p_booking_id for update;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  if v_booking.id is null then raise exception 'Booking not found'; end if;
  if v_booking.passenger_id <> auth.uid() and v_ride.driver_id <> auth.uid() then raise exception 'You cannot cancel this booking'; end if;
  if v_booking.status not in ('requested','accepted','awaiting_payment','confirmed') then raise exception 'This booking is not cancellable'; end if;
  v_from := v_booking.status::text; v_late := v_ride.departure_at < timezone('utc', now()) + make_interval(mins => public.ride_setting_int('ride_free_cancellation_minutes', 60));
  v_to := (case when v_ride.driver_id = auth.uid() then 'cancelled_by_driver' else 'cancelled_by_passenger' end)::public.ride_booking_status;
  if v_booking.status in ('accepted','awaiting_payment','confirmed') then update public.rides set available_seats=least(total_seats, available_seats+v_booking.seats_requested), status=(case when status='full' then 'published' else status::text end)::public.ride_status where id=v_ride.id; end if;
  update public.ride_bookings set status=v_to, cancelled_at=timezone('utc', now()), cancelled_by=auth.uid(), cancellation_reason=trim(p_reason), late_cancellation=v_late, hold_expires_at=null where id=p_booking_id;
  if v_to = 'cancelled_by_driver' and v_late then update public.driver_profiles set reliability_cancellations=reliability_cancellations+1 where user_id=v_ride.driver_id; end if;
  perform public.record_ride_booking_event(p_booking_id, v_from, v_to::text, p_reason); return v_to;
end; $$;

-- payment_transactions.status is an enum column. Cast the CASE expression at
-- the insert boundary, and cast the refund status CASE assigned to payments.
create or replace function public.payment_process_webhook(
  p_provider text, p_provider_event_id text, p_payment_id uuid, p_provider_reference text, p_event_type text,
  p_event_status text, p_amount numeric, p_currency text, p_signature_verified boolean, p_payload_hash text,
  p_safe_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_payment public.payments%rowtype; v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_tx public.payment_transactions%rowtype; v_status public.payment_status; v_refund_exists boolean;
begin
  if auth.role() <> 'service_role' then raise exception 'Webhook processing is server-only'; end if;
  if not p_signature_verified then raise exception 'Signature must be verified before processing'; end if;
  if p_provider_event_id is null or length(trim(p_provider_event_id)) < 8 then raise exception 'Provider event ID is required'; end if;
  select * into v_tx from public.payment_transactions where provider_event_id=p_provider_event_id;
  if found then return jsonb_build_object('duplicate', true, 'payment_id', v_tx.payment_id, 'status', 'ignored'); end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found then raise exception 'Payment not found'; end if;
  insert into public.payment_transactions(payment_id, provider_reference, provider_event_id, event_type, transaction_type, amount, status, signature_verified, raw_metadata, payload_hash, occurred_at)
  values (v_payment.id, coalesce(p_provider_reference, 'event') || ':event:' || p_provider_event_id, p_provider_event_id, p_event_type, 'webhook', coalesce(p_amount, v_payment.amount),
    (case when p_event_status='succeeded' then 'succeeded' when p_event_status='failed' then 'failed' when p_event_status='cancelled' then 'cancelled' else 'under_review' end)::public.payment_status,
    true, coalesce(p_safe_metadata,'{}'::jsonb), p_payload_hash, timezone('utc', now()));
  if p_currency <> v_payment.currency or p_amount <> v_payment.amount then
    update public.payments set status='under_review', under_review_reason='Webhook amount or currency mismatch', provider_reference=coalesce(p_provider_reference, provider_reference), updated_at=timezone('utc', now()) where id=v_payment.id;
    return jsonb_build_object('under_review', true, 'reason', 'amount_or_currency_mismatch');
  end if;
  if p_event_status='succeeded' then
    select * into v_booking from public.ride_bookings where id=v_payment.ride_booking_id for update;
    select * into v_ride from public.rides where id=v_booking.ride_id;
    if v_booking.status <> 'awaiting_payment' or v_booking.hold_expires_at is null or v_booking.hold_expires_at <= timezone('utc', now()) then
      update public.payments set status='under_review', under_review_reason='Successful payment arrived after booking hold expiry', provider_reference=p_provider_reference, updated_at=timezone('utc', now()) where id=v_payment.id;
      select exists(select 1 from public.refunds where payment_id=v_payment.id and status in ('requested','approved','processing')) into v_refund_exists;
      if not v_refund_exists then insert into public.refunds(payment_id, amount, reason, status, requested_by) values (v_payment.id, v_payment.amount, 'Successful payment received after seat hold expiry; automatic refund review required', 'requested', v_payment.payer_id); end if;
      return jsonb_build_object('under_review', true, 'reason', 'hold_expired');
    end if;
    update public.payments set status='succeeded', succeeded_at=timezone('utc', now()), provider_reference=p_provider_reference, updated_at=timezone('utc', now()) where id=v_payment.id;
    update public.ride_bookings set status='confirmed', paid_at=timezone('utc', now()), updated_at=timezone('utc', now()) where id=v_booking.id;
    perform public.record_ride_booking_event(v_booking.id, 'awaiting_payment', 'confirmed', 'Sandbox payment verified by webhook');
    perform public.notify_ride_user(v_booking.passenger_id, 'payment_confirmed', 'Sandbox payment confirmed', 'Your ride booking is confirmed. This was a sandbox payment; no real money moved.', '/bookings/'||v_booking.id);
    perform public.notify_ride_user(v_ride.driver_id, 'payment_confirmed', 'Passenger payment confirmed', 'A passenger payment was verified and the seat is now permanently held.', '/provider/bookings/'||v_ride.id);
    return jsonb_build_object('confirmed', true, 'payment_id', v_payment.id);
  elsif p_event_status='failed' then v_status := 'failed'::public.payment_status;
  elsif p_event_status='cancelled' then v_status := 'cancelled'::public.payment_status;
  else v_status := 'under_review'::public.payment_status;
  end if;
  update public.payments set status=v_status, failed_at=case when v_status='failed' then timezone('utc', now()) else failed_at end, cancelled_at=case when v_status='cancelled' then timezone('utc', now()) else cancelled_at end, provider_reference=coalesce(p_provider_reference, provider_reference), updated_at=timezone('utc', now()) where id=v_payment.id;
  return jsonb_build_object('processed', true, 'status', v_status);
exception when unique_violation then return jsonb_build_object('duplicate', true, 'status', 'ignored');
end; $$;

create or replace function public.payment_process_refund(p_refund_id uuid, p_admin_id uuid, p_provider_reference text, p_success boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refund public.refunds%rowtype; v_payment public.payments%rowtype; v_total numeric;
begin
  if auth.role() <> 'service_role' or not public.payment_is_admin(p_admin_id) then raise exception 'Admin refund processing required'; end if;
  select * into v_refund from public.refunds where id=p_refund_id for update; select * into v_payment from public.payments where id=v_refund.payment_id for update;
  if p_success then
    update public.refunds set status='processed', processed_by=p_admin_id, processed_at=timezone('utc', now()), payment_provider_reference=p_provider_reference where id=v_refund.id;
    select coalesce(sum(amount),0) into v_total from public.refunds where payment_id=v_payment.id and status in ('processed','completed');
    update public.payments set status=(case when v_total >= v_payment.amount then 'refunded' else 'partially_refunded' end)::public.payment_status, updated_at=timezone('utc', now()) where id=v_payment.id;
  else update public.refunds set status='failed', processed_by=p_admin_id, processed_at=timezone('utc', now()), payment_provider_reference=p_provider_reference where id=v_refund.id;
  end if;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata) values (p_admin_id, case when p_success then 'payment.refund_processed' else 'payment.refund_failed' end, 'refund', v_refund.id, jsonb_build_object('payment_id', v_payment.id, 'amount', v_refund.amount));
  return jsonb_build_object('refund_id', v_refund.id, 'success', p_success);
end; $$;

-- The prior implementation already assigns a typed variable, but use explicit
-- assignments here as a defensive audit boundary for vehicle_status.
create or replace function public.admin_review_vehicle(p_vehicle_id uuid, p_approve boolean, p_reason text default null)
returns public.vehicle_status language plpgsql security definer set search_path = public as $$
declare v_status public.vehicle_status; v_provider uuid;
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;
  if not p_approve and nullif(trim(p_reason), '') is null then raise exception 'A rejection reason is required'; end if;
  if p_approve then v_status := 'approved'::public.vehicle_status; else v_status := 'rejected'::public.vehicle_status; end if;
  update public.vehicles set status=v_status, updated_at=timezone('utc', now()) where id=p_vehicle_id returning provider_id into v_provider;
  if v_provider is null then raise exception 'Vehicle not found'; end if;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), case when p_approve then 'vehicle.approved' else 'vehicle.rejected' end, 'vehicle', p_vehicle_id, jsonb_build_object('reason', p_reason));
  perform public.notify_ride_user(v_provider, 'vehicle_reviewed', 'Vehicle review updated', case when p_approve then 'Your vehicle is approved for ride publishing.' else coalesce(trim(p_reason), 'Your vehicle was not approved.') end, '/provider/vehicles');
  return v_status;
end; $$;
