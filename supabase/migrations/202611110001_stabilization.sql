-- Connect Attock stabilization pass. Run after all existing migrations.
-- Additive only: do not edit earlier migration files.

update storage.buckets
set public = false,
    allowed_mime_types = array['image/jpeg','image/png','image/webp','application/pdf']::text[],
    file_size_limit = 10485760
where id = 'verification-documents';

insert into public.route_locations (name, slug, latitude, longitude, active) values
 ('Saddar Rawalpindi','saddar-rawalpindi',33.5973,73.0544,true),
 ('Committee Chowk','committee-chowk',33.6261,73.0714,true),
 ('Pirwadhai Bus Terminal','pirwadhai-bus-terminal',33.6445,72.9988,true),
 ('Faizabad Interchange','faizabad-interchange',33.6670,73.0906,true),
 ('Islamabad I-8 Markaz','islamabad-i8-markaz',33.6658,73.0737,true),
 ('Islamabad Blue Area','islamabad-blue-area',33.7182,73.0769,true),
 ('Rawat','rawat',33.4984,73.1903,true),
 ('Kallar Syedan','kallar-syedan',33.4106,73.3802,true),
 ('Gujar Khan','gujar-khan',33.2558,73.3042,true),
 ('Mandra','mandra',33.1181,73.1669,true),
 ('Taxila','taxila',33.7463,72.8397,true),
 ('Wah Cantt','wah-cantt',33.7701,72.7511,true),
 ('Hassan Abdal','hassan-abdal',33.8195,72.6890,true),
 ('Burhan Interchange','burhan-interchange',33.8412,72.5875,true),
 ('Hazro','hazro',33.9098,72.4852,true),
 ('Attock City','attock-city',33.7667,72.3598,true),
 ('Attock Khurd','attock-khurd',33.7680,72.2504,true),
 ('Kamra','kamra',33.7475,72.7422,true),
 ('Fateh Jang','fateh-jang',33.5677,72.6405,true),
 ('New Islamabad Airport','new-islamabad-airport',33.5607,72.8516,true),
 ('Golra Sharif','golra-sharif',33.6857,72.9350,true),
 ('Tarnol','tarnol',33.6731,72.9796,true),
 ('Sihala','sihala',33.5843,73.1815,true),
 ('Kahuta','kahuta',33.5911,73.3874,true),
 ('Murree Road','murree-road',33.6495,73.0778,true),
 ('Chakri','chakri',33.4745,72.9634,true),
 ('Chakwal Road Junction','chakwal-road-junction',33.7707,72.3877,true),
 ('Jand','jand',33.4338,72.0134,true),
 ('Pindigheb','pindigheb',33.2382,72.2648,true),
 ('Nowshera','nowshera',34.0159,72.0088,true),
 ('Peshawar Road Rawalpindi','peshawar-road-rawalpindi',33.6250,73.0203,true),
 ('Saddar Attock','saddar-attock',33.7660,72.3580,true),
 ('Kamra Airbase Gate','kamra-airbase-gate',33.7450,72.7480,true),
 ('Wahdat Colony','wahdat-colony',33.7810,72.7240,true),
 ('Lawrence College Murree','lawrence-college-murree',33.9070,73.3910,true),
 ('Murree Mall Road','murree-mall-road',33.9073,73.3929,true),
 ('Bahria Town Rawalpindi','bahria-town-rawalpindi',33.5428,73.1236,true),
 ('DHA Islamabad','dha-islamabad',33.5485,73.1658,true),
 ('Gulberg Greens','gulberg-greens',33.6093,73.1475,true),
 ('Swan Camp','swan-camp',33.5970,73.1460,true)
on conflict (slug) do update set name=excluded.name, latitude=excluded.latitude, longitude=excluded.longitude, active=true;

create or replace function public.search_route_locations(p_query text default '', p_limit integer default 8)
returns table (id uuid, name text, slug text, latitude numeric, longitude numeric)
language sql stable security definer set search_path = public as $$
  select id, name, slug, latitude, longitude
  from public.route_locations
  where active = true and (nullif(trim(p_query), '') is null or name ilike '%' || trim(p_query) || '%')
  order by case when lower(name) = lower(trim(p_query)) then 0 when name ilike trim(p_query) || '%' then 1 else 2 end, name
  limit greatest(least(coalesce(p_limit, 8), 20), 1);
$$;
grant execute on function public.search_route_locations(text, integer) to anon, authenticated;

create or replace function public.submit_provider_verification()
returns public.verification_status language plpgsql security definer set search_path = public as $$
declare v_status public.verification_status; v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  insert into public.driver_profiles(user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select verification_status into v_status from public.driver_profiles where user_id = auth.uid() for update;
  if v_status not in ('not_submitted','rejected') then return v_status; end if;
  select count(distinct document_type) into v_count
    from public.verification_documents
    where user_id = auth.uid() and status in ('pending','rejected')
      and document_type in ('identity','driving_licence','vehicle_registration','vehicle_image');
  if v_count < 4 then raise exception 'Upload all four required documents before submitting (identity, driving licence, vehicle registration and vehicle image)'; end if;
  update public.driver_profiles
    set verification_status = 'pending'::public.verification_status, reviewed_by = null, reviewed_at = null, rejection_reason = null, updated_at = timezone('utc', now())
    where user_id = auth.uid();
  update public.verification_documents
    set status = 'pending'::public.verification_status, reviewed_by = null, reviewed_at = null, rejection_reason = null
    where user_id = auth.uid() and document_type in ('identity','driving_licence','vehicle_registration','vehicle_image');
  return 'pending'::public.verification_status;
end; $$;
grant execute on function public.submit_provider_verification() to authenticated;

create or replace function public.publish_ride(p_ride_id uuid) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype;
begin
  select * into v_ride from public.rides where id=p_ride_id for update;
  if v_ride.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if not public.is_approved_provider(auth.uid()) then raise exception 'Your provider verification is not approved'; end if;
  if v_ride.status <> 'draft' then raise exception 'Only draft rides can be published'; end if;
  if v_ride.departure_at <= timezone('utc', now()) then raise exception 'Departure must be in the future'; end if;
  if v_ride.vehicle_id is not null and not exists (select 1 from public.vehicles where id=v_ride.vehicle_id and provider_id=auth.uid() and status='approved') then raise exception 'The selected vehicle is not approved'; end if;
  update public.rides set status = (case when available_seats = 0 then 'full' else 'published' end)::public.ride_status, published_at=timezone('utc', now()), updated_at=timezone('utc', now()) where id=p_ride_id;
  return p_ride_id;
end; $$;
grant execute on function public.publish_ride(uuid) to authenticated;

create or replace function public.update_ride(
  p_ride_id uuid, p_origin text, p_destination text, p_departure_at timestamptz, p_total_seats integer,
  p_price_per_seat numeric, p_description text default null, p_vehicle_id uuid default null,
  p_pickup_point jsonb default null, p_dropoff_point jsonb default null, p_stops jsonb default '[]'::jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ride public.rides%rowtype; v_active integer; v_origin_id uuid; v_destination_id uuid; v_stop jsonb; v_index integer := 0; v_status public.ride_status;
begin
  select * into v_ride from public.rides where id=p_ride_id for update;
  if v_ride.id is null or v_ride.driver_id <> auth.uid() then raise exception 'Ride not found or not owned by you'; end if;
  if v_ride.status not in ('draft','published','full') then raise exception 'Only draft, published or full rides can be edited'; end if;
  select count(*) into v_active from public.ride_bookings where ride_id=p_ride_id and status in ('accepted','awaiting_payment','confirmed');
  if v_active > 0 then raise exception 'Ride details cannot be edited while seats are held or confirmed'; end if;
  if p_departure_at <= timezone('utc', now()) then raise exception 'Departure must be in the future'; end if;
  if lower(trim(p_origin)) = lower(trim(p_destination)) then raise exception 'Origin and destination must be different'; end if;
  if p_total_seats < 1 or p_total_seats > 20 or p_total_seats < (v_ride.total_seats - v_ride.available_seats) then raise exception 'Seats cannot be lower than already requested seats'; end if;
  if p_price_per_seat < 0 then raise exception 'Fare cannot be negative'; end if;
  select id into v_origin_id from public.route_locations where lower(name)=lower(trim(p_origin)) and active=true;
  select id into v_destination_id from public.route_locations where lower(name)=lower(trim(p_destination)) and active=true;
  if v_origin_id is null or v_destination_id is null then raise exception 'This route location is not configured'; end if;
  if p_vehicle_id is not null and not exists (select 1 from public.vehicles where id=p_vehicle_id and provider_id=auth.uid() and status='approved') then raise exception 'Select one of your approved vehicles'; end if;
  v_status := case when v_ride.status='full' then 'full'::public.ride_status when v_ride.status='draft' then 'draft'::public.ride_status else 'published'::public.ride_status end;
  update public.rides set origin=trim(p_origin), destination=trim(p_destination), route_origin_id=v_origin_id, route_destination_id=v_destination_id, departure_at=p_departure_at, total_seats=p_total_seats, available_seats=p_total_seats-(v_ride.total_seats-v_ride.available_seats), price_per_seat=p_price_per_seat, description=nullif(trim(p_description),''), vehicle_id=p_vehicle_id, pickup_point=p_pickup_point, dropoff_point=p_dropoff_point, status=v_status, updated_at=timezone('utc',now()) where id=p_ride_id;
  delete from public.ride_stops where ride_id=p_ride_id;
  for v_stop in select value from jsonb_array_elements(coalesce(p_stops,'[]'::jsonb)) loop
    insert into public.ride_stops (ride_id, stop_order, name, latitude, longitude, estimated_at) values (p_ride_id,v_index,trim(v_stop->>'name'),nullif(v_stop->>'latitude','')::numeric,nullif(v_stop->>'longitude','')::numeric,nullif(v_stop->>'estimated_at','')::timestamptz);
    v_index := v_index + 1;
  end loop;
  return p_ride_id;
end; $$;
grant execute on function public.update_ride(uuid,text,text,timestamptz,integer,numeric,text,uuid,jsonb,jsonb,jsonb) to authenticated;

-- The original return shape cannot be altered with CREATE OR REPLACE, so replace
-- the search function with the additive metrics columns.
drop function if exists public.search_published_rides(text,text,date,numeric,time,time,integer,text,integer,integer);
create function public.search_published_rides(
  p_origin text default null, p_destination text default null, p_date date default null, p_max_fare numeric default null,
  p_departure_from time default null, p_departure_to time default null, p_min_seats integer default 1, p_sort text default 'earliest', p_page integer default 1, p_page_size integer default 10
) returns table (
  id uuid, origin text, destination text, departure_at timestamptz, available_seats smallint, total_seats smallint, price_per_seat numeric, description text,
  driver_name text, driver_avatar_url text, driver_verification_status public.verification_status, driver_rating numeric, driver_completed_trips integer, vehicle jsonb, total_count bigint,
  request_count bigint, held_seats bigint, confirmed_seats bigint, status public.ride_status
) language sql stable security definer set search_path=public as $$
  select r.id,r.origin,r.destination,r.departure_at,r.available_seats,r.total_seats,r.price_per_seat,r.description,p.full_name,p.avatar_url,dp.verification_status,coalesce(dp.rating_average,0),coalesce(dp.completed_trips,0),
    case when v.id is null then null else jsonb_build_object('id',v.id,'make',v.make,'model',v.model,'year',v.year,'color',v.color,'seats',v.seats) end,
    count(*) over (),
    (select count(*) from public.ride_bookings b where b.ride_id=r.id and b.status not in ('rejected','cancelled_by_passenger','cancelled_by_driver','expired','cancelled')),
    coalesce((select sum(b.seats_requested) from public.ride_bookings b where b.ride_id=r.id and b.status in ('accepted','awaiting_payment')),0),
    coalesce((select sum(b.seats_requested) from public.ride_bookings b where b.ride_id=r.id and b.status in ('confirmed','completed')),0), r.status
  from public.rides r join public.profiles p on p.id=r.driver_id left join public.driver_profiles dp on dp.user_id=r.driver_id left join public.vehicles v on v.id=r.vehicle_id
  where r.status in ('published','full') and r.departure_at>timezone('utc',now()) and (p_origin is null or lower(r.origin)=lower(trim(p_origin))) and (p_destination is null or lower(r.destination)=lower(trim(p_destination))) and (p_date is null or r.departure_at::date=p_date) and (p_max_fare is null or r.price_per_seat<=p_max_fare) and (p_departure_from is null or r.departure_at::time>=p_departure_from) and (p_departure_to is null or r.departure_at::time<=p_departure_to) and r.available_seats>=greatest(coalesce(p_min_seats,1),0)
  order by case when p_sort='cheapest' then r.price_per_seat end asc nulls last,r.departure_at asc
  limit greatest(least(coalesce(p_page_size,10),50),1) offset greatest(coalesce(p_page-1,0),0)*greatest(least(coalesce(p_page_size,10),50),1);
$$;
grant execute on function public.search_published_rides(text,text,date,numeric,time,time,integer,text,integer,integer) to anon, authenticated;

create or replace function public.get_ride_detail(p_ride_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb; v_visible boolean;
begin
  select exists(select 1 from public.rides r where r.id=p_ride_id and (r.status in ('published','full','in_progress','completed') or r.driver_id=auth.uid() or public.is_admin())) into v_visible;
  if not v_visible then raise exception 'Ride not found'; end if;
  select jsonb_build_object('ride',(to_jsonb(r)-'driver_id'-'vehicle_id') || jsonb_build_object('request_count',(select count(*) from public.ride_bookings b where b.ride_id=r.id and b.status not in ('rejected','cancelled_by_passenger','cancelled_by_driver','expired','cancelled')),'held_seats',coalesce((select sum(b.seats_requested) from public.ride_bookings b where b.ride_id=r.id and b.status in ('accepted','awaiting_payment')),0),'confirmed_seats',coalesce((select sum(b.seats_requested) from public.ride_bookings b where b.ride_id=r.id and b.status in ('confirmed','completed')),0)),'driver',jsonb_build_object('id',p.id,'full_name',p.full_name,'avatar_url',p.avatar_url,'verification_status',dp.verification_status,'rating_average',coalesce(dp.rating_average,0),'completed_trips',coalesce(dp.completed_trips,0)),'vehicle',case when v.id is null then null else jsonb_build_object('id',v.id,'make',v.make,'model',v.model,'year',v.year,'color',v.color,'seats',v.seats) end,'stops',coalesce((select jsonb_agg(to_jsonb(s) order by s.stop_order) from public.ride_stops s where s.ride_id=r.id),'[]'::jsonb)) into v_result
  from public.rides r join public.profiles p on p.id=r.driver_id left join public.driver_profiles dp on dp.user_id=r.driver_id left join public.vehicles v on v.id=r.vehicle_id where r.id=p_ride_id;
  return v_result;
end; $$;
grant execute on function public.get_ride_detail(uuid) to anon, authenticated;

create or replace function public.list_provider_rides() returns setof jsonb language sql stable security definer set search_path=public as $$
  select (to_jsonb(r) || jsonb_build_object('request_count',(select count(*) from public.ride_bookings b where b.ride_id=r.id and b.status not in ('rejected','cancelled_by_passenger','cancelled_by_driver','expired','cancelled')),'held_seats',coalesce((select sum(b.seats_requested) from public.ride_bookings b where b.ride_id=r.id and b.status in ('accepted','awaiting_payment')),0),'confirmed_seats',coalesce((select sum(b.seats_requested) from public.ride_bookings b where b.ride_id=r.id and b.status in ('confirmed','completed')),0))) from public.rides r where r.driver_id=auth.uid() order by r.departure_at desc;
$$;
grant execute on function public.list_provider_rides() to authenticated;
