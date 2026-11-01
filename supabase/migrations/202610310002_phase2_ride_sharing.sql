-- Connect Attock Phase 2: Ride Sharing
-- Additive migration. Do not edit or rerun the Phase 1 migration in place.
-- Run after 202610310001_phase1_foundation.sql in Supabase SQL Editor.

alter type public.ride_booking_status add value if not exists 'cancelled_by_passenger';
alter type public.ride_booking_status add value if not exists 'cancelled_by_driver';
alter type public.ride_booking_status add value if not exists 'expired';
alter type public.ride_booking_status add value if not exists 'awaiting_payment';

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  description text,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references public.profiles(id)
);

create table if not exists public.route_locations (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  latitude numeric(9,6),
  longitude numeric(9,6),
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

insert into public.app_settings (key, value, description)
values
  ('ride_hold_minutes', '15'::jsonb, 'Minutes an accepted unpaid ride booking keeps seats reserved.'),
  ('ride_free_cancellation_minutes', '60'::jsonb, 'Minutes before departure when cancellation is marked late.'),
  ('ride_start_window_minutes', '30'::jsonb, 'Minutes before departure when a driver may start a trip.'),
  ('ride_completion_otp_minutes', '30'::jsonb, 'Minutes a completion OTP remains valid.'),
  ('ride_completion_otp_attempts', '5'::jsonb, 'Maximum incorrect OTP attempts per booking.'),
  ('dev_ride_confirmation_enabled', 'false'::jsonb, 'Must be explicitly enabled by an admin in a sandbox project; never enable in production.')
on conflict (key) do nothing;

insert into public.route_locations (name, slug, latitude, longitude)
values
  ('Rawalpindi', 'rawalpindi', 33.5651, 73.0169),
  ('Attock', 'attock', 33.7667, 72.3598)
on conflict (slug) do nothing;

alter table public.rides add column if not exists route_origin_id uuid references public.route_locations(id);
alter table public.rides add column if not exists route_destination_id uuid references public.route_locations(id);
alter table public.rides add column if not exists published_at timestamptz;
alter table public.rides add column if not exists cancellation_by uuid references public.profiles(id);
alter table public.rides add column if not exists late_cancellation boolean not null default false;

alter table public.ride_bookings add column if not exists policy_accepted_at timestamptz;
alter table public.ride_bookings add column if not exists hold_expires_at timestamptz;
alter table public.ride_bookings add column if not exists cancelled_by uuid references public.profiles(id);
alter table public.ride_bookings add column if not exists late_cancellation boolean not null default false;
alter table public.ride_bookings add column if not exists driver_confirmed_at timestamptz;
alter table public.ride_bookings add column if not exists passenger_confirmed_at timestamptz;
alter table public.ride_bookings add column if not exists completion_otp_expires_at timestamptz;
alter table public.ride_bookings add column if not exists completion_otp_attempts smallint not null default 0 check (completion_otp_attempts >= 0);
alter table public.ride_bookings add column if not exists completed_at timestamptz;

alter table public.driver_profiles add column if not exists rating_average numeric(4,2) not null default 0 check (rating_average between 0 and 5);
alter table public.driver_profiles add column if not exists rating_count integer not null default 0 check (rating_count >= 0);
alter table public.driver_profiles add column if not exists completed_trips integer not null default 0 check (completed_trips >= 0);
alter table public.driver_profiles add column if not exists reliability_cancellations integer not null default 0 check (reliability_cancellations >= 0);

alter table public.ride_bookings drop constraint if exists ride_bookings_ride_id_passenger_id_key;
create unique index if not exists ride_bookings_one_active_per_passenger_idx
  on public.ride_bookings (ride_id, passenger_id)
  where status in ('requested', 'accepted', 'awaiting_payment', 'confirmed');
create index if not exists rides_search_idx on public.rides (origin, destination, departure_at, status, available_seats);
create index if not exists ride_bookings_hold_expiry_idx on public.ride_bookings (hold_expires_at) where status = 'awaiting_payment';
create index if not exists route_locations_active_idx on public.route_locations (active, name);
create index if not exists reviews_ride_booking_idx on public.reviews (ride_booking_id);

create or replace function public.ride_setting_int(p_key text, p_default integer)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::integer from public.app_settings where key = p_key), p_default);
$$;

create or replace function public.dev_ride_confirmation_enabled()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::boolean from public.app_settings where key = 'dev_ride_confirmation_enabled'), false);
$$;

create or replace function public.notify_ride_user(p_user_id uuid, p_type text, p_title text, p_body text, p_action_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, type, title, body, action_url)
  values (p_user_id, p_type, p_title, p_body, p_action_url);
end; $$;

create or replace function public.record_ride_booking_event(p_booking_id uuid, p_from text, p_to text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_passenger uuid;
  v_driver uuid;
  v_ride_id uuid;
  v_origin text;
  v_destination text;
  v_title text;
  v_body text;
begin
  select b.passenger_id, b.ride_id, r.driver_id, r.origin, r.destination
    into v_passenger, v_ride_id, v_driver, v_origin, v_destination
  from public.ride_bookings b join public.rides r on r.id = b.ride_id
  where b.id = p_booking_id;
  insert into public.booking_status_history (changed_by, ride_booking_id, from_status, to_status, note)
  values (auth.uid(), p_booking_id, p_from, p_to, p_note);
  v_title := 'Ride booking updated';
  v_body := format('%s → %s is now %s.', v_origin, v_destination, replace(p_to, '_', ' '));
  perform public.notify_ride_user(v_passenger, 'ride_booking_status', v_title, v_body, '/bookings/' || p_booking_id::text);
  if v_driver is distinct from auth.uid() then
    perform public.notify_ride_user(v_driver, 'ride_booking_status', v_title, v_body, '/provider/bookings/' || v_ride_id::text);
  end if;
end; $$;

create or replace function public.validate_ride_row()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(trim(new.origin)) = lower(trim(new.destination)) then
    raise exception 'Origin and destination must be different';
  end if;
  if new.departure_at <= timezone('utc', now()) and new.status in ('draft', 'published', 'full') then
    raise exception 'Departure must be in the future';
  end if;
  if new.total_seats < 1 or new.available_seats < 0 or new.available_seats > new.total_seats then
    raise exception 'Seat counts are invalid';
  end if;
  if new.price_per_seat < 0 then
    raise exception 'Fare cannot be negative';
  end if;
  if new.status in ('published', 'full') and not public.is_approved_provider(new.driver_id) and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Only an approved provider can publish a ride';
  end if;
  return new;
end; $$;

drop trigger if exists rides_validate_row on public.rides;
create trigger rides_validate_row before insert or update on public.rides for each row execute procedure public.validate_ride_row();

-- Replace permissive Phase 1 policies with a server-transition model.
drop policy if exists rides_select_published_or_participant on public.rides;
drop policy if exists rides_insert_driver on public.rides;
drop policy if exists rides_update_driver_or_admin on public.rides;
create policy rides_select_published_or_participant on public.rides for select using (status in ('published', 'full', 'in_progress', 'completed') or driver_id = auth.uid() or public.is_admin());
create policy rides_admin_write on public.rides for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists stops_select_visible_ride on public.ride_stops;
drop policy if exists stops_manage_driver_or_admin on public.ride_stops;
create policy stops_select_visible_ride on public.ride_stops for select using (exists (select 1 from public.rides r where r.id = ride_id and (r.status in ('published', 'full', 'in_progress', 'completed') or r.driver_id = auth.uid() or public.is_admin())));
create policy stops_admin_write on public.ride_stops for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists ride_bookings_passenger_insert on public.ride_bookings;
drop policy if exists ride_bookings_participant_update on public.ride_bookings;
drop policy if exists ride_bookings_participant_or_admin on public.ride_bookings;
create policy ride_bookings_participant_or_admin on public.ride_bookings for select using (passenger_id = auth.uid() or exists (select 1 from public.rides r where r.id = ride_id and r.driver_id = auth.uid()) or public.is_admin());
create policy ride_bookings_admin_write on public.ride_bookings for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists booking_history_authorized on public.booking_status_history;
drop policy if exists booking_history_participant_insert on public.booking_status_history;
create policy booking_history_authorized on public.booking_status_history for select using (changed_by = auth.uid() or public.is_admin() or exists (select 1 from public.ride_bookings b where b.id = ride_booking_id and b.passenger_id = auth.uid()) or exists (select 1 from public.ride_bookings b join public.rides r on r.id = b.ride_id where b.id = ride_booking_id and r.driver_id = auth.uid()));
create policy booking_history_admin_write on public.booking_status_history for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists notifications_admin_insert on public.notifications;
create policy notifications_admin_write on public.notifications for insert with check (public.is_admin());

drop policy if exists reviews_reviewer_insert on public.reviews;
drop policy if exists reviews_reviewer_update_or_admin on public.reviews;
create policy reviews_admin_write on public.reviews for all using (public.is_admin()) with check (public.is_admin());

alter table public.app_settings enable row level security;
alter table public.route_locations enable row level security;
create policy app_settings_admin_read on public.app_settings for select using (public.is_admin());
create policy app_settings_admin_write on public.app_settings for all using (public.is_admin()) with check (public.is_admin());
create policy route_locations_public_read on public.route_locations for select using (active = true or public.is_admin());
create policy route_locations_admin_write on public.route_locations for all using (public.is_admin()) with check (public.is_admin());

create or replace function public.create_ride(
  p_origin text, p_destination text, p_departure_at timestamptz, p_total_seats integer,
  p_price_per_seat numeric, p_description text default null, p_vehicle_id uuid default null,
  p_pickup_point jsonb default null, p_dropoff_point jsonb default null, p_stops jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_ride_id uuid;
  v_origin_id uuid;
  v_destination_id uuid;
  v_stop jsonb;
  v_index integer := 0;
begin
  if auth.uid() is null or not public.has_role(auth.uid(), 'service_provider') or not public.is_approved_provider(auth.uid()) then
    raise exception 'Only an approved service provider can create a ride';
  end if;
  if p_departure_at <= timezone('utc', now()) then raise exception 'Departure must be in the future'; end if;
  if lower(trim(p_origin)) = lower(trim(p_destination)) then raise exception 'Origin and destination must be different'; end if;
  if p_total_seats < 1 or p_total_seats > 20 then raise exception 'Seats must be between 1 and 20'; end if;
  if p_price_per_seat < 0 then raise exception 'Fare cannot be negative'; end if;
  select id into v_origin_id from public.route_locations where lower(name) = lower(trim(p_origin)) and active = true;
  select id into v_destination_id from public.route_locations where lower(name) = lower(trim(p_destination)) and active = true;
  if v_origin_id is null or v_destination_id is null then raise exception 'This route location is not configured'; end if;
  if p_vehicle_id is not null and not exists (select 1 from public.vehicles where id = p_vehicle_id and provider_id = auth.uid() and status = 'approved') then
    raise exception 'Select one of your approved vehicles';
  end if;
  insert into public.rides (driver_id, vehicle_id, origin, destination, route_origin_id, route_destination_id, departure_at, total_seats, available_seats, price_per_seat, description, pickup_point, dropoff_point, status)
  values (auth.uid(), p_vehicle_id, trim(p_origin), trim(p_destination), v_origin_id, v_destination_id, p_departure_at, p_total_seats, p_total_seats, p_price_per_seat, nullif(trim(p_description), ''), p_pickup_point, p_dropoff_point, 'draft')
  returning id into v_ride_id;
  for v_stop in select value from jsonb_array_elements(coalesce(p_stops, '[]'::jsonb)) loop
    insert into public.ride_stops (ride_id, stop_order, name, latitude, longitude, estimated_at)
    values (v_ride_id, v_index, trim(v_stop->>'name'), nullif(v_stop->>'latitude', '')::numeric, nullif(v_stop->>'longitude', '')::numeric, nullif(v_stop->>'estimated_at', '')::timestamptz);
    v_index := v_index + 1;
  end loop;
  return v_ride_id;
end; $$;

create or replace function public.publish_ride(p_ride_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype;
begin
  select * into v_ride from public.rides where id = p_ride_id for update;
  if v_ride.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if not public.is_approved_provider(auth.uid()) then raise exception 'Your provider verification is not approved'; end if;
  if v_ride.status <> 'draft' then raise exception 'Only draft rides can be published'; end if;
  if v_ride.departure_at <= timezone('utc', now()) then raise exception 'Departure must be in the future'; end if;
  if v_ride.vehicle_id is not null and not exists (select 1 from public.vehicles where id = v_ride.vehicle_id and provider_id = auth.uid() and status = 'approved') then raise exception 'The selected vehicle is not approved'; end if;
  update public.rides set status = case when available_seats = 0 then 'full' else 'published' end, published_at = timezone('utc', now()) where id = p_ride_id;
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
  update public.rides set origin=trim(p_origin), destination=trim(p_destination), route_origin_id=v_origin_id, route_destination_id=v_destination_id, departure_at=p_departure_at, total_seats=p_total_seats, available_seats=p_total_seats - (v_ride.total_seats - v_ride.available_seats), price_per_seat=p_price_per_seat, description=nullif(trim(p_description), ''), vehicle_id=p_vehicle_id, pickup_point=p_pickup_point, dropoff_point=p_dropoff_point, status=case when status = 'draft' then 'draft' else 'published' end where id=p_ride_id;
  delete from public.ride_stops where ride_id = p_ride_id;
  for v_stop in select value from jsonb_array_elements(coalesce(p_stops, '[]'::jsonb)) loop
    insert into public.ride_stops (ride_id, stop_order, name, latitude, longitude, estimated_at)
    values (p_ride_id, v_index, trim(v_stop->>'name'), nullif(v_stop->>'latitude', '')::numeric, nullif(v_stop->>'longitude', '')::numeric, nullif(v_stop->>'estimated_at', '')::timestamptz);
    v_index := v_index + 1;
  end loop;
  return p_ride_id;
end; $$;

create or replace function public.cancel_ride(p_ride_id uuid, p_reason text) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_booking public.ride_bookings%rowtype; v_from text; v_late boolean;
begin
  if nullif(trim(p_reason), '') is null then raise exception 'A cancellation reason is required'; end if;
  select * into v_ride from public.rides where id = p_ride_id for update;
  if v_ride.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if v_ride.status in ('completed', 'cancelled') then raise exception 'This ride cannot be cancelled'; end if;
  v_late := v_ride.departure_at < timezone('utc', now()) + make_interval(mins => public.ride_setting_int('ride_free_cancellation_minutes', 60));
  update public.rides set status='cancelled', cancelled_at=timezone('utc', now()), cancellation_reason=trim(p_reason), cancellation_by=auth.uid(), late_cancellation=v_late where id=p_ride_id;
  for v_booking in select * from public.ride_bookings where ride_id=p_ride_id and status in ('requested','accepted','awaiting_payment','confirmed') for update loop
    v_from := v_booking.status::text;
    if v_booking.status in ('accepted','awaiting_payment','confirmed') then update public.rides set available_seats = least(total_seats, available_seats + v_booking.seats_requested) where id=p_ride_id; end if;
    update public.ride_bookings set status='cancelled_by_driver', cancelled_at=timezone('utc', now()), cancelled_by=auth.uid(), cancellation_reason=trim(p_reason), late_cancellation=v_late, hold_expires_at=null where id=v_booking.id;
    perform public.record_ride_booking_event(v_booking.id, v_from, 'cancelled_by_driver', p_reason);
  end loop;
  return p_ride_id;
end; $$;

create or replace function public.search_published_rides(
  p_origin text default null, p_destination text default null, p_date date default null,
  p_max_fare numeric default null, p_departure_from time default null, p_departure_to time default null,
  p_min_seats integer default 1, p_sort text default 'earliest', p_page integer default 1, p_page_size integer default 10
) returns table (
  id uuid, origin text, destination text, departure_at timestamptz, available_seats smallint, total_seats smallint,
  price_per_seat numeric, description text, driver_name text, driver_avatar_url text,
  driver_verification_status public.verification_status, driver_rating numeric, driver_completed_trips integer,
  vehicle jsonb, total_count bigint
) language sql stable security definer set search_path = public as $$
  select r.id, r.origin, r.destination, r.departure_at, r.available_seats, r.total_seats, r.price_per_seat, r.description,
    p.full_name, p.avatar_url, dp.verification_status, coalesce(dp.rating_average, 0), coalesce(dp.completed_trips, 0),
    case when v.id is null then null else jsonb_build_object('id', v.id, 'make', v.make, 'model', v.model, 'year', v.year, 'color', v.color, 'seats', v.seats) end,
    count(*) over ()
  from public.rides r
  join public.profiles p on p.id = r.driver_id
  left join public.driver_profiles dp on dp.user_id = r.driver_id
  left join public.vehicles v on v.id = r.vehicle_id
  where r.status in ('published', 'full') and r.departure_at > timezone('utc', now())
    and (p_origin is null or lower(r.origin) = lower(trim(p_origin)))
    and (p_destination is null or lower(r.destination) = lower(trim(p_destination)))
    and (p_date is null or r.departure_at::date = p_date)
    and (p_max_fare is null or r.price_per_seat <= p_max_fare)
    and (p_departure_from is null or r.departure_at::time >= p_departure_from)
    and (p_departure_to is null or r.departure_at::time <= p_departure_to)
    and r.available_seats >= greatest(coalesce(p_min_seats, 1), 0)
  order by case when p_sort = 'cheapest' then r.price_per_seat end asc nulls last, r.departure_at asc
  limit greatest(least(coalesce(p_page_size, 10), 50), 1)
  offset greatest(coalesce(p_page - 1, 0), 0) * greatest(least(coalesce(p_page_size, 10), 50), 1);
$$;

create or replace function public.get_ride_detail(p_ride_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_result jsonb; v_visible boolean;
begin
  select exists(select 1 from public.rides r where r.id=p_ride_id and (r.status in ('published','full','in_progress','completed') or r.driver_id=auth.uid() or public.is_admin())) into v_visible;
  if not v_visible then raise exception 'Ride not found'; end if;
  select jsonb_build_object(
    'ride', to_jsonb(r) - 'driver_id' - 'vehicle_id',
    'driver', jsonb_build_object('id', p.id, 'full_name', p.full_name, 'avatar_url', p.avatar_url, 'verification_status', dp.verification_status, 'rating_average', coalesce(dp.rating_average,0), 'completed_trips', coalesce(dp.completed_trips,0)),
    'vehicle', case when v.id is null then null else jsonb_build_object('id',v.id,'make',v.make,'model',v.model,'year',v.year,'color',v.color,'seats',v.seats) end,
    'stops', coalesce((select jsonb_agg(to_jsonb(s) order by s.stop_order) from public.ride_stops s where s.ride_id=r.id), '[]'::jsonb)
  ) into v_result
  from public.rides r join public.profiles p on p.id=r.driver_id left join public.driver_profiles dp on dp.user_id=r.driver_id left join public.vehicles v on v.id=r.vehicle_id where r.id=p_ride_id;
  return v_result;
end; $$;

create or replace function public.request_ride_booking(p_ride_id uuid, p_seats integer, p_policy_accepted boolean) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_existing public.ride_bookings%rowtype; v_booking uuid;
begin
  if auth.uid() is null then raise exception 'You must be logged in'; end if;
  if not p_policy_accepted then raise exception 'You must accept the cancellation policy'; end if;
  if p_seats < 1 then raise exception 'Request at least one seat'; end if;
  select * into v_ride from public.rides where id=p_ride_id for update;
  if v_ride.id is null then raise exception 'Ride not found'; end if;
  if v_ride.driver_id = auth.uid() then raise exception 'You cannot request your own ride'; end if;
  if v_ride.status not in ('published','full') or v_ride.departure_at <= timezone('utc', now()) then raise exception 'This ride is not accepting requests'; end if;
  if p_seats > v_ride.available_seats then raise exception 'Not enough seats available'; end if;
  select * into v_existing from public.ride_bookings where ride_id=p_ride_id and passenger_id=auth.uid() and status in ('requested','accepted','awaiting_payment','confirmed') limit 1;
  if v_existing.id is not null then raise exception 'You already have an active booking for this ride'; end if;
  insert into public.ride_bookings (ride_id, passenger_id, seats_requested, amount, status, policy_accepted_at)
  values (p_ride_id, auth.uid(), p_seats, v_ride.price_per_seat*p_seats, 'requested', timezone('utc', now())) returning id into v_booking;
  perform public.record_ride_booking_event(v_booking, null, 'requested', 'Seat request received');
  perform public.notify_ride_user(v_ride.driver_id, 'ride_request', 'New ride request', 'Someone requested seats on your ride.', '/provider/bookings/' || p_ride_id::text);
  return v_booking;
end; $$;

create or replace function public.driver_respond_ride_booking(p_booking_id uuid, p_accept boolean, p_reason text default null) returns public.ride_booking_status language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_from text; v_hold timestamptz;
begin
  select r.* into v_ride from public.rides r join public.ride_bookings b on b.ride_id=r.id where b.id=p_booking_id for update;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  if v_booking.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Booking not found or not your ride'; end if;
  if v_booking.status <> 'requested' then raise exception 'Only requested bookings can be accepted or rejected'; end if;
  v_from := v_booking.status::text;
  if not p_accept then
    update public.ride_bookings set status='rejected', cancelled_at=timezone('utc', now()), cancellation_reason=nullif(trim(p_reason), '') where id=p_booking_id;
    perform public.record_ride_booking_event(p_booking_id, v_from, 'rejected', p_reason);
    return 'rejected';
  end if;
  if v_ride.available_seats < v_booking.seats_requested then raise exception 'Not enough seats remain'; end if;
  v_hold := timezone('utc', now()) + make_interval(mins => public.ride_setting_int('ride_hold_minutes', 15));
  update public.rides set available_seats=available_seats-v_booking.seats_requested, status=case when available_seats-v_booking.seats_requested=0 then 'full' else status end where id=v_ride.id;
  update public.ride_bookings set status='accepted', hold_expires_at=v_hold, accepted_at=timezone('utc', now()) where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, v_from, 'accepted', 'Seats are temporarily held');
  update public.ride_bookings set status='awaiting_payment' where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, 'accepted', 'awaiting_payment', 'Payment is not connected in Phase 2; waiting for the sandbox confirmation step');
  return 'awaiting_payment';
end; $$;

create or replace function public.expire_unpaid_ride_holds() returns integer language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_count integer := 0; v_ride public.rides%rowtype;
begin
  for v_booking in select * from public.ride_bookings where status='awaiting_payment' and hold_expires_at is not null and hold_expires_at < timezone('utc', now()) order by hold_expires_at for update skip locked loop
    select * into v_ride from public.rides where id=v_booking.ride_id for update;
    update public.rides set available_seats=least(total_seats, available_seats+v_booking.seats_requested), status=case when status='full' then 'published' else status end where id=v_ride.id;
    update public.ride_bookings set status='expired', hold_expires_at=null where id=v_booking.id;
    perform public.record_ride_booking_event(v_booking.id, 'awaiting_payment', 'expired', 'The temporary seat hold expired');
    v_count := v_count + 1;
  end loop;
  return v_count;
end; $$;

create or replace function public.dev_confirm_ride_booking(p_booking_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype;
begin
  if not public.is_admin() or not public.dev_ride_confirmation_enabled() then raise exception 'Sandbox confirmation is disabled; no real payment was processed'; end if;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  if v_booking.status <> 'awaiting_payment' then raise exception 'Only awaiting-payment bookings can be sandbox-confirmed'; end if;
  update public.ride_bookings set status='confirmed', paid_at=timezone('utc', now()), hold_expires_at=null where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, 'awaiting_payment', 'confirmed', 'DEV-ONLY sandbox confirmation; no real payment was processed');
  return p_booking_id;
end; $$;

create or replace function public.cancel_ride_booking(p_booking_id uuid, p_reason text) returns public.ride_booking_status language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_to public.ride_booking_status; v_late boolean; v_from text;
begin
  if nullif(trim(p_reason), '') is null then raise exception 'A cancellation reason is required'; end if;
  select r.* into v_ride from public.rides r join public.ride_bookings b on b.ride_id=r.id where b.id=p_booking_id for update;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  if v_booking.id is null then raise exception 'Booking not found'; end if;
  if v_booking.passenger_id <> auth.uid() and v_ride.driver_id <> auth.uid() then raise exception 'You cannot cancel this booking'; end if;
  if v_booking.status not in ('requested','accepted','awaiting_payment','confirmed') then raise exception 'This booking is not cancellable'; end if;
  v_from := v_booking.status::text;
  v_late := v_ride.departure_at < timezone('utc', now()) + make_interval(mins => public.ride_setting_int('ride_free_cancellation_minutes', 60));
  v_to := case when v_ride.driver_id = auth.uid() then 'cancelled_by_driver' else 'cancelled_by_passenger' end;
  if v_booking.status in ('accepted','awaiting_payment','confirmed') then update public.rides set available_seats=least(total_seats, available_seats+v_booking.seats_requested), status=case when status='full' then 'published' else status end where id=v_ride.id; end if;
  update public.ride_bookings set status=v_to, cancelled_at=timezone('utc', now()), cancelled_by=auth.uid(), cancellation_reason=trim(p_reason), late_cancellation=v_late, hold_expires_at=null where id=p_booking_id;
  if v_to = 'cancelled_by_driver' and v_late then update public.driver_profiles set reliability_cancellations=reliability_cancellations+1 where user_id=v_ride.driver_id; end if;
  perform public.record_ride_booking_event(p_booking_id, v_from, v_to::text, p_reason);
  return v_to;
end; $$;

create or replace function public.start_ride(p_ride_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_confirmed integer; v_booking_id uuid;
begin
  select * into v_ride from public.rides where id=p_ride_id for update;
  if v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if v_ride.status not in ('published','full') then raise exception 'Ride cannot be started from its current status'; end if;
  if timezone('utc', now()) < v_ride.departure_at - make_interval(mins => public.ride_setting_int('ride_start_window_minutes', 30)) then raise exception 'The departure window has not opened'; end if;
  select count(*) into v_confirmed from public.ride_bookings where ride_id=p_ride_id and status='confirmed';
  if v_confirmed < 1 then raise exception 'At least one confirmed passenger is required'; end if;
  update public.rides set status='in_progress', started_at=timezone('utc', now()) where id=p_ride_id;
  for v_booking_id in select id from public.ride_bookings where ride_id=p_ride_id and status='confirmed' loop
    perform public.record_ride_booking_event(v_booking_id, 'confirmed', 'confirmed', 'Trip started');
  end loop;
  return p_ride_id;
end; $$;

create or replace function public.get_passenger_completion_otp(p_booking_id uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_otp text; v_expires timestamptz;
begin
  select * into v_booking from public.ride_bookings where id=p_booking_id;
  select * into v_ride from public.rides where id=v_booking.ride_id;
  if v_booking.passenger_id <> auth.uid() or v_ride.status <> 'in_progress' or v_booking.status <> 'confirmed' then raise exception 'Completion code is not available'; end if;
  v_otp := lpad(floor(random()*1000000)::int::text, 6, '0');
  v_expires := timezone('utc', now()) + make_interval(mins => public.ride_setting_int('ride_completion_otp_minutes', 30));
  update public.ride_bookings set completion_otp_hash=encode(digest(v_otp, 'sha256'), 'hex'), completion_otp_expires_at=v_expires, completion_otp_attempts=0 where id=p_booking_id;
  return jsonb_build_object('otp', v_otp, 'expires_at', v_expires);
end; $$;

create or replace function public.driver_confirm_passenger_dropoff(p_booking_id uuid, p_otp text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_max integer;
begin
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  select * into v_ride from public.rides where id=v_booking.ride_id for update;
  if v_ride.driver_id <> auth.uid() or v_booking.status <> 'confirmed' or v_ride.status <> 'in_progress' then raise exception 'Passenger drop-off cannot be confirmed'; end if;
  v_max := public.ride_setting_int('ride_completion_otp_attempts', 5);
  if v_booking.completion_otp_hash is null or v_booking.completion_otp_expires_at < timezone('utc', now()) then return jsonb_build_object('ok', false, 'reason', 'expired'); end if;
  if v_booking.completion_otp_attempts >= v_max then return jsonb_build_object('ok', false, 'reason', 'attempt_limit'); end if;
  if encode(digest(trim(p_otp), 'sha256'), 'hex') <> v_booking.completion_otp_hash then
    update public.ride_bookings set completion_otp_attempts=completion_otp_attempts+1 where id=p_booking_id;
    return jsonb_build_object('ok', false, 'reason', 'invalid', 'attempts_left', greatest(v_max - v_booking.completion_otp_attempts - 1, 0));
  end if;
  update public.ride_bookings set driver_confirmed_at=timezone('utc', now()), completion_otp_hash=null, completion_otp_expires_at=null where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, 'confirmed', 'confirmed', 'Driver confirmed passenger drop-off with OTP');
  return jsonb_build_object('ok', true);
end; $$;

create or replace function public.passenger_confirm_ride_completion(p_booking_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype;
begin
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  select * into v_ride from public.rides where id=v_booking.ride_id for update;
  if v_booking.passenger_id <> auth.uid() or v_booking.status <> 'confirmed' or v_booking.driver_confirmed_at is null then raise exception 'Driver drop-off confirmation is required first'; end if;
  update public.ride_bookings set status='completed', passenger_confirmed_at=timezone('utc', now()), completed_at=timezone('utc', now()) where id=p_booking_id;
  update public.driver_profiles set completed_trips=completed_trips+1 where user_id=v_ride.driver_id;
  perform public.record_ride_booking_event(p_booking_id, 'confirmed', 'completed', 'Passenger confirmed completion');
  return p_booking_id;
end; $$;

create or replace function public.complete_ride(p_ride_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_blocked integer;
begin
  select * into v_ride from public.rides where id=p_ride_id for update;
  if v_ride.driver_id <> auth.uid() or v_ride.status <> 'in_progress' then raise exception 'Ride cannot be completed'; end if;
  select count(*) into v_blocked from public.ride_bookings where ride_id=p_ride_id and status='confirmed' and driver_confirmed_at is null;
  if v_blocked > 0 then raise exception 'All confirmed passengers must be completed or marked no-show'; end if;
  update public.rides set status='completed', completed_at=timezone('utc', now()) where id=p_ride_id;
  return p_ride_id;
end; $$;

create or replace function public.mark_ride_no_show(p_booking_id uuid, p_reason text) returns uuid language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype;
begin
  if nullif(trim(p_reason), '') is null then raise exception 'A no-show reason is required'; end if;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  select * into v_ride from public.rides where id=v_booking.ride_id for update;
  if v_ride.driver_id <> auth.uid() or v_booking.status <> 'confirmed' or v_ride.status <> 'in_progress' then raise exception 'Passenger cannot be marked no-show now'; end if;
  update public.ride_bookings set status='no_show', cancellation_reason=trim(p_reason), completed_at=timezone('utc', now()) where id=p_booking_id;
  perform public.record_ride_booking_event(p_booking_id, 'confirmed', 'no_show', p_reason);
  return p_booking_id;
end; $$;

create or replace function public.submit_ride_review(p_booking_id uuid, p_reviewee_id uuid, p_rating integer, p_body text default null) returns uuid language plpgsql security definer set search_path = public as $$
declare v_booking public.ride_bookings%rowtype; v_ride public.rides%rowtype; v_review uuid;
begin
  if p_rating < 1 or p_rating > 5 then raise exception 'Rating must be between 1 and 5'; end if;
  select * into v_booking from public.ride_bookings where id=p_booking_id;
  select * into v_ride from public.rides where id=v_booking.ride_id;
  if v_booking.status <> 'completed' or (auth.uid() <> v_booking.passenger_id and auth.uid() <> v_ride.driver_id) then raise exception 'Reviews are only available to completed participants'; end if;
  if auth.uid() = v_booking.passenger_id and p_reviewee_id <> v_ride.driver_id then raise exception 'Passenger reviews must target the driver'; end if;
  if auth.uid() = v_ride.driver_id and p_reviewee_id <> v_booking.passenger_id then raise exception 'Driver reviews must target the passenger'; end if;
  insert into public.reviews (reviewer_id, reviewee_id, ride_booking_id, rating, body) values (auth.uid(), p_reviewee_id, p_booking_id, p_rating, nullif(trim(p_body), '')) returning id into v_review;
  if p_reviewee_id = v_ride.driver_id then
    update public.driver_profiles dp set rating_count=rating_count+1, rating_average=round(((rating_average*rating_count)+p_rating)/(rating_count+1), 2) where dp.user_id=p_reviewee_id;
  end if;
  perform public.notify_ride_user(p_reviewee_id, 'review_received', 'You received a ride review', 'A completed ride participant left you a review.', '/notifications');
  return v_review;
exception when unique_violation then raise exception 'You already reviewed this completed ride in that direction';
end; $$;

create or replace function public.report_ride_review(p_review_id uuid, p_reason text, p_details text default null) returns uuid language plpgsql security definer set search_path = public as $$
declare v_review public.reviews%rowtype; v_report uuid;
begin
  select * into v_review from public.reviews where id=p_review_id;
  if v_review.reviewer_id <> auth.uid() and v_review.reviewee_id <> auth.uid() then raise exception 'You cannot report this review'; end if;
  insert into public.reports (reporter_id, review_id, reported_user_id, reason, details) values (auth.uid(), p_review_id, v_review.reviewee_id, trim(p_reason), nullif(trim(p_details), '')) returning id into v_report;
  return v_report;
end; $$;

create or replace function public.get_ride_booking_detail(p_booking_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_result jsonb; v_allowed boolean;
begin
  select exists(select 1 from public.ride_bookings b join public.rides r on r.id=b.ride_id where b.id=p_booking_id and (b.passenger_id=auth.uid() or r.driver_id=auth.uid() or public.is_admin())) into v_allowed;
  if not v_allowed then raise exception 'Booking not found'; end if;
  select jsonb_build_object('booking',to_jsonb(b)-'completion_otp_hash','ride',to_jsonb(r)-'driver_id','driver',jsonb_build_object('id',p.id,'full_name',p.full_name,'avatar_url',p.avatar_url,'rating_average',coalesce(dp.rating_average,0)),'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at) from public.booking_status_history h where h.ride_booking_id=b.id),'[]'::jsonb)) into v_result
  from public.ride_bookings b join public.rides r on r.id=b.ride_id join public.profiles p on p.id=r.driver_id left join public.driver_profiles dp on dp.user_id=r.driver_id where b.id=p_booking_id;
  return v_result;
end; $$;

create or replace function public.get_provider_ride_requests(p_ride_id uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('booking',to_jsonb(b)-'completion_otp_hash','passenger',jsonb_build_object('id',p.id,'full_name',p.full_name,'avatar_url',p.avatar_url),'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at) from public.booking_status_history h where h.ride_booking_id=b.id),'[]'::jsonb)) order by b.created_at desc),'[]'::jsonb)
  from public.ride_bookings b join public.rides r on r.id=b.ride_id join public.profiles p on p.id=b.passenger_id where b.ride_id=p_ride_id and r.driver_id=auth.uid();
$$;

create or replace function public.mark_notification_read(p_notification_id uuid) returns uuid language sql security definer set search_path = public as $$
  update public.notifications set read_at=coalesce(read_at, timezone('utc', now())) where id=p_notification_id and user_id=auth.uid() returning id;
$$;

-- Recommended Supabase setup after applying this migration:
-- 1. Enable Realtime for public.notifications in Database > Replication.
-- 2. Schedule select cron.schedule('connect-attock-expire-ride-holds', '* * * * *', $$select public.expire_unpaid_ride_holds();$$);
--    only after pg_cron is enabled in the project and the owner has reviewed the shared database implications.
-- 3. Set app_settings.dev_ride_confirmation_enabled to true only in a non-production sandbox and only for admin testing.
