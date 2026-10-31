-- Connect Attock Phase 1 foundation
-- Run in the Supabase SQL editor. This migration creates the durable schema and RLS boundary.
-- No service-role key is required by the browser application.

create extension if not exists pgcrypto;

create type public.app_role as enum ('customer', 'service_provider', 'admin');
create type public.account_status as enum ('active', 'deactivated', 'suspended');
create type public.verification_status as enum ('not_submitted', 'pending', 'approved', 'rejected', 'suspended');
create type public.vehicle_status as enum ('pending', 'approved', 'rejected', 'suspended');
create type public.ride_status as enum ('draft', 'published', 'full', 'in_progress', 'completed', 'cancelled');
create type public.ride_booking_status as enum ('requested', 'accepted', 'rejected', 'payment_pending', 'confirmed', 'cancelled', 'completed', 'no_show');
create type public.order_status as enum ('pending', 'accepted', 'shopping_in_progress', 'purchased', 'picked_up', 'on_the_way', 'arrived', 'delivered', 'cancelled', 'disputed');
create type public.cargo_order_status as enum ('requested', 'accepted', 'pickup_pending', 'picked_up', 'in_transit', 'arrived', 'delivered', 'cancelled', 'disputed');
create type public.payment_status as enum ('created', 'pending', 'verified', 'failed', 'refunded', 'partially_refunded');
create type public.document_type as enum ('identity', 'driving_licence', 'vehicle_registration', 'vehicle_image', 'purchase_receipt', 'pickup_proof', 'delivery_proof');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(trim(full_name)) between 2 and 120),
  phone text,
  avatar_url text,
  notification_email boolean not null default true,
  account_status public.account_status not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, role)
);

create table public.driver_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  verification_status public.verification_status not null default 'not_submitted',
  bio text,
  reliability_score numeric(5,2) check (reliability_score between 0 and 100),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.verification_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  document_type public.document_type not null,
  storage_path text not null,
  status public.verification_status not null default 'pending',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, document_type, storage_path)
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.profiles(id) on delete cascade,
  make text not null,
  model text not null,
  year smallint check (year between 1950 and extract(year from now())::smallint + 1),
  color text,
  registration_masked text,
  seats smallint not null check (seats between 1 and 20),
  status public.vehicle_status not null default 'pending',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.rides (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id) on delete restrict,
  vehicle_id uuid references public.vehicles(id) on delete set null,
  origin text not null,
  destination text not null,
  departure_at timestamptz not null,
  intermediate_stops jsonb not null default '[]'::jsonb,
  pickup_point jsonb,
  dropoff_point jsonb,
  total_seats smallint not null check (total_seats > 0 and total_seats <= 20),
  available_seats smallint not null check (available_seats >= 0 and available_seats <= total_seats),
  price_per_seat numeric(12,2) not null check (price_per_seat >= 0),
  description text,
  status public.ride_status not null default 'draft',
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.ride_stops (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  stop_order smallint not null check (stop_order >= 0),
  name text not null,
  latitude numeric(9,6),
  longitude numeric(9,6),
  estimated_at timestamptz,
  unique (ride_id, stop_order)
);

create table public.ride_bookings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete restrict,
  passenger_id uuid not null references public.profiles(id) on delete restrict,
  seats_requested smallint not null check (seats_requested > 0),
  amount numeric(12,2) not null check (amount >= 0),
  status public.ride_booking_status not null default 'requested',
  completion_otp_hash text,
  accepted_at timestamptz,
  paid_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (ride_id, passenger_id)
);

create table public.shopping_offers (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.profiles(id) on delete restrict,
  store_name text not null,
  store_location text not null,
  destination text not null,
  expected_at timestamptz not null,
  capacity numeric(10,2) not null check (capacity > 0),
  shopping_fee numeric(12,2) not null check (shopping_fee >= 0),
  delivery_charge numeric(12,2) not null check (delivery_charge >= 0),
  status text not null default 'published' check (status in ('draft', 'published', 'full', 'completed', 'cancelled')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.shopping_orders (
  id uuid primary key default gen_random_uuid(),
  offer_id uuid not null references public.shopping_offers(id) on delete restrict,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  provider_id uuid not null references public.profiles(id) on delete restrict,
  product_cost numeric(12,2) not null check (product_cost >= 0),
  shopping_fee numeric(12,2) not null check (shopping_fee >= 0),
  delivery_charge numeric(12,2) not null check (delivery_charge >= 0),
  total_amount numeric(12,2) generated always as (product_cost + shopping_fee + delivery_charge) stored,
  instructions text,
  status public.order_status not null default 'pending',
  delivered_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.shopping_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.shopping_orders(id) on delete cascade,
  name text not null,
  quantity numeric(10,2) not null check (quantity > 0),
  unit_price numeric(12,2) check (unit_price >= 0),
  notes text
);

create table public.cargo_offers (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.profiles(id) on delete restrict,
  origin text not null,
  destination text not null,
  departure_at timestamptz not null,
  capacity_weight_kg numeric(10,2) not null check (capacity_weight_kg > 0),
  capacity_volume numeric(12,2),
  vehicle_id uuid references public.vehicles(id) on delete set null,
  status text not null default 'published' check (status in ('draft', 'published', 'full', 'completed', 'cancelled')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.cargo_orders (
  id uuid primary key default gen_random_uuid(),
  tracking_number text not null unique default ('CA-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  offer_id uuid references public.cargo_offers(id) on delete set null,
  sender_id uuid not null references public.profiles(id) on delete restrict,
  provider_id uuid references public.profiles(id) on delete restrict,
  sender_name text not null,
  sender_phone text not null,
  receiver_name text not null,
  receiver_phone text not null,
  pickup_address text not null,
  destination_address text not null,
  weight_kg numeric(10,2) not null check (weight_kg > 0),
  dimensions jsonb,
  category text not null,
  photos jsonb not null default '[]'::jsonb,
  instructions text,
  delivery_mode text not null check (delivery_mode in ('standard', 'doorstep')),
  base_charge numeric(12,2) not null check (base_charge >= 0),
  doorstep_charge numeric(12,2) not null default 0 check (doorstep_charge >= 0),
  total_amount numeric(12,2) generated always as (base_charge + doorstep_charge) stored,
  pickup_otp_hash text,
  delivery_otp_hash text,
  status public.cargo_order_status not null default 'requested',
  picked_up_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  ride_booking_id uuid references public.ride_bookings(id) on delete restrict,
  shopping_order_id uuid references public.shopping_orders(id) on delete restrict,
  cargo_order_id uuid references public.cargo_orders(id) on delete restrict,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'PKR' check (char_length(currency) = 3),
  status public.payment_status not null default 'created',
  provider text not null default 'sandbox',
  idempotency_key text not null unique,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (num_nonnulls(ride_booking_id, shopping_order_id, cargo_order_id) = 1)
);

create table public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete cascade,
  provider_reference text not null unique,
  provider_event_id text unique,
  event_type text not null,
  amount numeric(12,2) not null check (amount >= 0),
  status public.payment_status not null,
  signature_verified boolean not null default false,
  raw_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.refunds (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.payments(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  reason text not null,
  status text not null default 'requested' check (status in ('requested', 'approved', 'processing', 'completed', 'failed', 'rejected')),
  provider_reference text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz
);

create table public.settlements (
  id uuid primary key default gen_random_uuid(),
  provider_id uuid not null references public.profiles(id) on delete restrict,
  period_start date not null,
  period_end date not null,
  gross_amount numeric(12,2) not null default 0 check (gross_amount >= 0),
  commission_amount numeric(12,2) not null default 0 check (commission_amount >= 0),
  net_amount numeric(12,2) not null default 0 check (net_amount >= 0),
  status text not null default 'pending' check (status in ('pending', 'processing', 'paid', 'held', 'failed')),
  paid_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  unique (provider_id, period_start, period_end)
);

create table public.commissions (
  id uuid primary key default gen_random_uuid(),
  settlement_id uuid references public.settlements(id) on delete set null,
  provider_id uuid not null references public.profiles(id) on delete restrict,
  source_type text not null check (source_type in ('ride', 'shopping', 'cargo')),
  source_id uuid not null,
  gross_amount numeric(12,2) not null check (gross_amount >= 0),
  commission_rate numeric(6,4) not null check (commission_rate between 0 and 1),
  commission_amount numeric(12,2) not null check (commission_amount >= 0),
  provider_amount numeric(12,2) not null check (provider_amount >= 0),
  created_at timestamptz not null default timezone('utc', now())
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  reviewee_id uuid not null references public.profiles(id) on delete restrict,
  ride_booking_id uuid references public.ride_bookings(id) on delete restrict,
  shopping_order_id uuid references public.shopping_orders(id) on delete restrict,
  cargo_order_id uuid references public.cargo_orders(id) on delete restrict,
  rating smallint not null check (rating between 1 and 5),
  body text,
  status text not null default 'published' check (status in ('published', 'reported', 'hidden')),
  created_at timestamptz not null default timezone('utc', now()),
  check (num_nonnulls(ride_booking_id, shopping_order_id, cargo_order_id) = 1),
  unique (reviewer_id, ride_booking_id),
  unique (reviewer_id, shopping_order_id),
  unique (reviewer_id, cargo_order_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete restrict,
  review_id uuid references public.reviews(id) on delete cascade,
  reported_user_id uuid references public.profiles(id) on delete restrict,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz
);

create table public.complaints (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles(id) on delete restrict,
  assigned_to uuid references public.profiles(id) on delete set null,
  ride_booking_id uuid references public.ride_bookings(id) on delete set null,
  shopping_order_id uuid references public.shopping_orders(id) on delete set null,
  cargo_order_id uuid references public.cargo_orders(id) on delete set null,
  subject text not null,
  description text not null,
  status text not null default 'open' check (status in ('open', 'investigating', 'resolved', 'closed')),
  created_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  action_url text,
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.location_updates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  ride_booking_id uuid references public.ride_bookings(id) on delete cascade,
  shopping_order_id uuid references public.shopping_orders(id) on delete cascade,
  cargo_order_id uuid references public.cargo_orders(id) on delete cascade,
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  accuracy_m numeric(10,2),
  captured_at timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  check (num_nonnulls(ride_booking_id, shopping_order_id, cargo_order_id) = 1)
);

create table public.booking_status_history (
  id uuid primary key default gen_random_uuid(),
  changed_by uuid references public.profiles(id) on delete set null,
  ride_booking_id uuid references public.ride_bookings(id) on delete cascade,
  shopping_order_id uuid references public.shopping_orders(id) on delete cascade,
  cargo_order_id uuid references public.cargo_orders(id) on delete cascade,
  from_status text,
  to_status text not null,
  note text,
  created_at timestamptz not null default timezone('utc', now()),
  check (num_nonnulls(ride_booking_id, shopping_order_id, cargo_order_id) = 1)
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index profiles_status_idx on public.profiles(account_status);
create index roles_user_idx on public.user_roles(user_id);
create index documents_user_status_idx on public.verification_documents(user_id, status);
create index vehicles_provider_status_idx on public.vehicles(provider_id, status);
create index rides_route_departure_idx on public.rides(origin, destination, departure_at) where status in ('published', 'full');
create index rides_driver_status_idx on public.rides(driver_id, status);
create index ride_bookings_passenger_status_idx on public.ride_bookings(passenger_id, status);
create index ride_bookings_ride_status_idx on public.ride_bookings(ride_id, status);
create index shopping_offers_route_time_idx on public.shopping_offers(store_location, destination, expected_at);
create index shopping_orders_customer_status_idx on public.shopping_orders(customer_id, status);
create index cargo_offers_route_time_idx on public.cargo_offers(origin, destination, departure_at);
create index cargo_orders_sender_status_idx on public.cargo_orders(sender_id, status);
create index cargo_orders_tracking_idx on public.cargo_orders(tracking_number);
create index payments_user_status_idx on public.payments(user_id, status);
create index notifications_user_created_idx on public.notifications(user_id, created_at desc);
create index location_updates_ride_time_idx on public.location_updates(ride_booking_id, captured_at desc);
create index audit_logs_entity_idx on public.audit_logs(entity_type, entity_id, created_at desc);

create or replace function public.set_updated_at() returns trigger language plpgsql security invoker set search_path = public as $$
begin new.updated_at = timezone('utc', now()); return new; end; $$;

create or replace function public.has_role(check_user_id uuid, check_role public.app_role) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.user_roles where user_id = check_user_id and role = check_role);
$$;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select public.has_role(auth.uid(), 'admin');
$$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone) values (new.id, coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), 'Connect Attock member'), new.raw_user_meta_data->>'phone') on conflict (id) do nothing;
  insert into public.user_roles (user_id, role) values (new.id, 'customer') on conflict do nothing;
  return new;
end; $$;

create or replace function public.prevent_protected_status_changes() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and not public.is_admin() then
    if tg_table_name = 'profiles' and new.account_status <> old.account_status and new.account_status <> 'deactivated' then
      raise exception 'Only an admin can suspend or reactivate an account';
    end if;
    if tg_table_name = 'driver_profiles' and (new.verification_status <> old.verification_status or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.rejection_reason is distinct from old.rejection_reason) then
      raise exception 'Only an admin can change provider verification status';
    end if;
    if tg_table_name = 'vehicles' and new.status <> old.status then
      raise exception 'Only an admin can change vehicle approval status';
    end if;
  end if;
  return new;
end; $$;

create or replace function public.is_approved_provider(check_user_id uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.driver_profiles where user_id = check_user_id and verification_status = 'approved');
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create trigger profiles_updated_at before update on public.profiles for each row execute procedure public.set_updated_at();
create trigger profiles_protected_status before update on public.profiles for each row execute procedure public.prevent_protected_status_changes();
create trigger driver_profiles_updated_at before update on public.driver_profiles for each row execute procedure public.set_updated_at();
create trigger driver_profiles_protected_status before update on public.driver_profiles for each row execute procedure public.prevent_protected_status_changes();
create trigger vehicles_updated_at before update on public.vehicles for each row execute procedure public.set_updated_at();
create trigger vehicles_protected_status before update on public.vehicles for each row execute procedure public.prevent_protected_status_changes();
create trigger rides_updated_at before update on public.rides for each row execute procedure public.set_updated_at();
create trigger bookings_updated_at before update on public.ride_bookings for each row execute procedure public.set_updated_at();
create trigger shopping_offers_updated_at before update on public.shopping_offers for each row execute procedure public.set_updated_at();
create trigger shopping_orders_updated_at before update on public.shopping_orders for each row execute procedure public.set_updated_at();
create trigger cargo_offers_updated_at before update on public.cargo_offers for each row execute procedure public.set_updated_at();
create trigger cargo_orders_updated_at before update on public.cargo_orders for each row execute procedure public.set_updated_at();
create trigger payments_updated_at before update on public.payments for each row execute procedure public.set_updated_at();

-- RLS is enabled on every application table. Policies are intentionally restrictive.
alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.driver_profiles enable row level security;
alter table public.verification_documents enable row level security;
alter table public.vehicles enable row level security;
alter table public.rides enable row level security;
alter table public.ride_stops enable row level security;
alter table public.ride_bookings enable row level security;
alter table public.shopping_offers enable row level security;
alter table public.shopping_orders enable row level security;
alter table public.shopping_order_items enable row level security;
alter table public.cargo_offers enable row level security;
alter table public.cargo_orders enable row level security;
alter table public.payments enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.refunds enable row level security;
alter table public.settlements enable row level security;
alter table public.commissions enable row level security;
alter table public.reviews enable row level security;
alter table public.reports enable row level security;
alter table public.complaints enable row level security;
alter table public.notifications enable row level security;
alter table public.location_updates enable row level security;
alter table public.booking_status_history enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select_own_or_admin on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_update_own_or_admin on public.profiles for update using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());
create policy profiles_insert_self on public.profiles for insert with check (id = auth.uid());

create policy roles_select_self_or_admin on public.user_roles for select using (user_id = auth.uid() or public.is_admin());
create policy roles_insert_admin_only on public.user_roles for insert with check (public.is_admin());
create policy roles_update_admin_only on public.user_roles for update using (public.is_admin()) with check (public.is_admin());
create policy roles_delete_admin_only on public.user_roles for delete using (public.is_admin());

create policy driver_profiles_select_owner_or_admin on public.driver_profiles for select using (user_id = auth.uid() or public.is_admin());
create policy driver_profiles_insert_owner on public.driver_profiles for insert with check (user_id = auth.uid() and verification_status = 'not_submitted');
create policy driver_profiles_update_owner_or_admin on public.driver_profiles for update using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());
create policy documents_owner_or_admin on public.verification_documents for select using (user_id = auth.uid() or public.is_admin());
create policy documents_insert_owner on public.verification_documents for insert with check (user_id = auth.uid());
create policy documents_update_admin on public.verification_documents for update using (public.is_admin()) with check (public.is_admin());
create policy vehicles_select_owner_or_approved on public.vehicles for select using (provider_id = auth.uid() or status = 'approved' or public.is_admin());
create policy vehicles_insert_owner on public.vehicles for insert with check (provider_id = auth.uid() and status = 'pending');
create policy vehicles_update_owner_or_admin on public.vehicles for update using (provider_id = auth.uid() or public.is_admin()) with check (provider_id = auth.uid() or public.is_admin());

create policy rides_select_published_or_participant on public.rides for select using (status in ('published', 'full') or driver_id = auth.uid() or public.is_admin());
create policy rides_insert_driver on public.rides for insert with check (driver_id = auth.uid() and public.has_role(auth.uid(), 'service_provider') and public.is_approved_provider(auth.uid()));
create policy rides_update_driver_or_admin on public.rides for update using ((driver_id = auth.uid() and public.is_approved_provider(auth.uid())) or public.is_admin()) with check ((driver_id = auth.uid() and public.is_approved_provider(auth.uid())) or public.is_admin());
create policy stops_select_visible_ride on public.ride_stops for select using (exists (select 1 from public.rides r where r.id = ride_id and (r.status in ('published', 'full') or r.driver_id = auth.uid() or public.is_admin())));
create policy stops_manage_driver_or_admin on public.ride_stops for all using (exists (select 1 from public.rides r where r.id = ride_id and (r.driver_id = auth.uid() or public.is_admin()))) with check (exists (select 1 from public.rides r where r.id = ride_id and (r.driver_id = auth.uid() or public.is_admin())));
create policy ride_bookings_participant_or_admin on public.ride_bookings for select using (passenger_id = auth.uid() or exists (select 1 from public.rides r where r.id = ride_id and r.driver_id = auth.uid()) or public.is_admin());
create policy ride_bookings_passenger_insert on public.ride_bookings for insert with check (passenger_id = auth.uid() and status = 'requested');
create policy ride_bookings_participant_update on public.ride_bookings for update using (passenger_id = auth.uid() or exists (select 1 from public.rides r where r.id = ride_id and r.driver_id = auth.uid()) or public.is_admin()) with check (passenger_id = auth.uid() or exists (select 1 from public.rides r where r.id = ride_id and r.driver_id = auth.uid()) or public.is_admin());

create policy shopping_offers_visible on public.shopping_offers for select using (status = 'published' or provider_id = auth.uid() or public.is_admin());
create policy shopping_offers_provider_manage on public.shopping_offers for all using ((provider_id = auth.uid() and public.is_approved_provider(auth.uid())) or public.is_admin()) with check ((provider_id = auth.uid() and public.is_approved_provider(auth.uid())) or public.is_admin());
create policy shopping_orders_participant on public.shopping_orders for select using (customer_id = auth.uid() or provider_id = auth.uid() or public.is_admin());
create policy shopping_orders_customer_insert on public.shopping_orders for insert with check (customer_id = auth.uid() and status = 'pending');
create policy shopping_orders_participant_update on public.shopping_orders for update using (customer_id = auth.uid() or provider_id = auth.uid() or public.is_admin()) with check (customer_id = auth.uid() or provider_id = auth.uid() or public.is_admin());
create policy shopping_items_participant on public.shopping_order_items for select using (exists (select 1 from public.shopping_orders o where o.id = order_id and (o.customer_id = auth.uid() or o.provider_id = auth.uid() or public.is_admin())));
create policy shopping_items_customer_manage on public.shopping_order_items for all using (exists (select 1 from public.shopping_orders o where o.id = order_id and (o.customer_id = auth.uid() or public.is_admin()))) with check (exists (select 1 from public.shopping_orders o where o.id = order_id and (o.customer_id = auth.uid() or public.is_admin())));

create policy cargo_offers_visible on public.cargo_offers for select using (status = 'published' or provider_id = auth.uid() or public.is_admin());
create policy cargo_offers_provider_manage on public.cargo_offers for all using ((provider_id = auth.uid() and public.is_approved_provider(auth.uid())) or public.is_admin()) with check ((provider_id = auth.uid() and public.is_approved_provider(auth.uid())) or public.is_admin());
create policy cargo_orders_participant on public.cargo_orders for select using (sender_id = auth.uid() or provider_id = auth.uid() or public.is_admin());
create policy cargo_orders_sender_insert on public.cargo_orders for insert with check (sender_id = auth.uid() and status = 'requested');
create policy cargo_orders_participant_update on public.cargo_orders for update using (sender_id = auth.uid() or provider_id = auth.uid() or public.is_admin()) with check (sender_id = auth.uid() or provider_id = auth.uid() or public.is_admin());

create policy payments_owner_or_admin on public.payments for select using (user_id = auth.uid() or public.is_admin());
create policy payments_owner_insert on public.payments for insert with check (user_id = auth.uid() and status = 'created');
create policy payments_admin_update on public.payments for update using (public.is_admin()) with check (public.is_admin());
create policy transactions_owner_or_admin on public.payment_transactions for select using (exists (select 1 from public.payments p where p.id = payment_id and (p.user_id = auth.uid() or public.is_admin())));
create policy transactions_admin_insert on public.payment_transactions for insert with check (public.is_admin());
create policy refunds_owner_or_admin on public.refunds for select using (exists (select 1 from public.payments p where p.id = payment_id and (p.user_id = auth.uid() or public.is_admin())));
create policy refunds_admin_manage on public.refunds for all using (public.is_admin()) with check (public.is_admin());
create policy settlements_provider_or_admin on public.settlements for select using (provider_id = auth.uid() or public.is_admin());
create policy settlements_admin_manage on public.settlements for all using (public.is_admin()) with check (public.is_admin());
create policy commissions_provider_or_admin on public.commissions for select using (provider_id = auth.uid() or public.is_admin());
create policy commissions_admin_manage on public.commissions for all using (public.is_admin()) with check (public.is_admin());

create policy reviews_visible_published_or_involved on public.reviews for select using (status = 'published' or reviewer_id = auth.uid() or reviewee_id = auth.uid() or public.is_admin());
create policy reviews_reviewer_insert on public.reviews for insert with check (reviewer_id = auth.uid());
create policy reviews_reviewer_update_or_admin on public.reviews for update using (reviewer_id = auth.uid() or public.is_admin()) with check (reviewer_id = auth.uid() or public.is_admin());
create policy reports_reporter_or_admin on public.reports for select using (reporter_id = auth.uid() or public.is_admin());
create policy reports_reporter_insert on public.reports for insert with check (reporter_id = auth.uid());
create policy reports_admin_update on public.reports for update using (public.is_admin()) with check (public.is_admin());
create policy complaints_owner_or_admin on public.complaints for select using (created_by = auth.uid() or assigned_to = auth.uid() or public.is_admin());
create policy complaints_owner_insert on public.complaints for insert with check (created_by = auth.uid());
create policy complaints_admin_update on public.complaints for update using (public.is_admin()) with check (public.is_admin());
create policy notifications_owner_or_admin on public.notifications for select using (user_id = auth.uid() or public.is_admin());
create policy notifications_owner_update on public.notifications for update using (user_id = auth.uid() or public.is_admin()) with check (user_id = auth.uid() or public.is_admin());
create policy notifications_admin_insert on public.notifications for insert with check (public.is_admin());
create policy location_updates_authorized on public.location_updates for select using (user_id = auth.uid() or public.is_admin() or exists (select 1 from public.ride_bookings b where b.id = ride_booking_id and b.passenger_id = auth.uid()) or exists (select 1 from public.shopping_orders o where o.id = shopping_order_id and (o.customer_id = auth.uid() or o.provider_id = auth.uid())) or exists (select 1 from public.cargo_orders c where c.id = cargo_order_id and (c.sender_id = auth.uid() or c.provider_id = auth.uid())));
create policy location_updates_owner_insert on public.location_updates for insert with check (user_id = auth.uid());
create policy booking_history_authorized on public.booking_status_history for select using (changed_by = auth.uid() or public.is_admin() or exists (select 1 from public.ride_bookings b where b.id = ride_booking_id and b.passenger_id = auth.uid()) or exists (select 1 from public.shopping_orders o where o.id = shopping_order_id and (o.customer_id = auth.uid() or o.provider_id = auth.uid())) or exists (select 1 from public.cargo_orders c where c.id = cargo_order_id and (c.sender_id = auth.uid() or c.provider_id = auth.uid())));
create policy booking_history_participant_insert on public.booking_status_history for insert with check (public.is_admin());
create policy audit_logs_admin_read on public.audit_logs for select using (public.is_admin());
create policy audit_logs_server_insert on public.audit_logs for insert with check (actor_id = auth.uid() or public.is_admin());

-- Storage bucket policy for sensitive verification documents. Create the bucket as private in the dashboard or via storage API.
-- The application should issue signed URLs only after this user/role check; never make this bucket public.
