-- Connect Attock ride search timezone fix. Run after 202611110001_stabilization.sql.
-- Additive only: do not edit earlier migrations.
-- datetime-local inputs are normalized by the client to timestamptz; search dates/times
-- are interpreted in the business timezone used by passengers and providers.

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
  from public.rides r
  join public.profiles p on p.id=r.driver_id
  left join public.driver_profiles dp on dp.user_id=r.driver_id
  left join public.vehicles v on v.id=r.vehicle_id
  where r.status in ('published','full')
    and r.departure_at > timezone('utc', now())
    and (p_origin is null or lower(trim(r.origin)) = lower(trim(p_origin)))
    and (p_destination is null or lower(trim(r.destination)) = lower(trim(p_destination)))
    and (p_date is null or (r.departure_at at time zone 'Asia/Karachi')::date = p_date)
    and (p_max_fare is null or r.price_per_seat <= p_max_fare)
    and (p_departure_from is null or (r.departure_at at time zone 'Asia/Karachi')::time >= p_departure_from)
    and (p_departure_to is null or (r.departure_at at time zone 'Asia/Karachi')::time <= p_departure_to)
    and r.available_seats >= greatest(coalesce(p_min_seats,1),0)
  order by case when p_sort='cheapest' then r.price_per_seat end asc nulls last,r.departure_at asc
  limit greatest(least(coalesce(p_page_size,10),50),1)
  offset greatest(coalesce(p_page-1,0),0)*greatest(least(coalesce(p_page_size,10),50),1);
$$;
grant execute on function public.search_published_rides(text,text,date,numeric,time,time,integer,text,integer,integer) to anon, authenticated;
