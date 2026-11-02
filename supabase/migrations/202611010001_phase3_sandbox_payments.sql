-- Connect Attock Phase 3: sandbox-only ride payments
-- Additive migration. Run after 202610310001_phase1_foundation.sql and 202610310002_phase2_ride_sharing.sql.
-- No card data, secrets or raw credential-bearing payloads are stored here.

alter type public.payment_status add value if not exists 'under_review';
alter type public.payment_status add value if not exists 'expired';

alter table public.payments
  add column if not exists payer_id uuid references public.profiles(id) on delete restrict,
  add column if not exists service_type text,
  add column if not exists service_id uuid,
  add column if not exists provider_reference text,
  add column if not exists checkout_url text,
  add column if not exists expires_at timestamptz,
  add column if not exists succeeded_at timestamptz,
  add column if not exists failed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists commission_rate_snapshot numeric(8,6),
  add column if not exists commission_fixed_snapshot numeric(12,2) not null default 0,
  add column if not exists platform_fee numeric(12,2) not null default 0,
  add column if not exists under_review_reason text;

update public.payments set payer_id = user_id where payer_id is null;
update public.payments set service_type = case when ride_booking_id is not null then 'ride' when shopping_order_id is not null then 'shopping' when cargo_order_id is not null then 'cargo' end where service_type is null;
update public.payments set service_id = coalesce(ride_booking_id, shopping_order_id, cargo_order_id) where service_id is null;

alter table public.payments alter column payer_id set not null;
alter table public.payments alter column service_type set not null;
alter table public.payments alter column service_id set not null;
alter table public.payments drop constraint if exists payments_service_check;
alter table public.payments add constraint payments_service_check check (service_type in ('ride','shopping','cargo'));
alter table public.payments drop constraint if exists payments_amount_nonnegative;
alter table public.payments add constraint payments_amount_nonnegative check (amount >= 0 and platform_fee >= 0 and commission_fixed_snapshot >= 0);

alter table public.payment_transactions
  alter column provider_reference drop not null,
  add column if not exists transaction_type text not null default 'event',
  add column if not exists payload_hash text,
  add column if not exists occurred_at timestamptz;

alter table public.refunds
  add column if not exists requested_by uuid references public.profiles(id),
  add column if not exists processed_by uuid references public.profiles(id),
  add column if not exists payment_provider_reference text;
alter table public.refunds drop constraint if exists refunds_status_check;
alter table public.refunds add constraint refunds_status_check check (status in ('requested','approved','processing','processed','completed','rejected','failed'));

alter table public.settlements
  add column if not exists ride_booking_id uuid references public.ride_bookings(id) on delete restrict,
  add column if not exists payment_id uuid references public.payments(id) on delete restrict,
  add column if not exists settlement_reference text,
  add column if not exists eligible_at timestamptz,
  add column if not exists held_reason text;
alter table public.settlements drop constraint if exists settlements_status_check;
alter table public.settlements add constraint settlements_status_check check (status in ('pending','eligible','processing','paid','held','disputed','failed'));

alter table public.commissions
  add column if not exists service_type text,
  add column if not exists fixed_amount numeric(12,2) not null default 0,
  add column if not exists currency text not null default 'PKR',
  add column if not exists rate_snapshot numeric(8,6);
update public.commissions set service_type = source_type, fixed_amount = 0, rate_snapshot = commission_rate where service_type is null;

create table if not exists public.payment_commission_settings (
  id uuid primary key default gen_random_uuid(),
  service_type text not null unique check (service_type in ('ride','shopping','cargo')),
  percentage_rate numeric(8,6) not null default 0.10 check (percentage_rate between 0 and 1),
  fixed_amount numeric(12,2) not null default 0 check (fixed_amount >= 0),
  currency text not null default 'PKR' check (currency = 'PKR'),
  active boolean not null default true,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default timezone('utc', now())
);
insert into public.payment_commission_settings(service_type, percentage_rate, fixed_amount)
values ('ride', 0.10, 0), ('shopping', 0.10, 0), ('cargo', 0.10, 0)
on conflict (service_type) do nothing;

create unique index if not exists payments_service_idempotency_key_idx on public.payments(service_type, service_id, idempotency_key);
create unique index if not exists payments_one_active_service_idx on public.payments(service_type, service_id) where status in ('created','pending','succeeded','under_review');
create unique index if not exists settlements_one_ride_booking_idx on public.settlements(ride_booking_id) where ride_booking_id is not null;
create index if not exists payments_payer_created_idx on public.payments(payer_id, created_at desc);
create index if not exists payments_provider_reference_idx on public.payments(provider_reference);
create index if not exists refunds_payment_status_idx on public.refunds(payment_id, status);
create index if not exists settlements_provider_status_idx on public.settlements(provider_id, status, created_at desc);

create or replace function public.payment_setting_num(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::numeric from public.app_settings where key=p_key), p_default);
$$;

create or replace function public.payment_is_admin(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.user_roles where user_id=p_user_id and role='admin');
$$;

create or replace function public.payment_append_only_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  raise exception 'Payment transaction ledger rows are append-only';
end; $$;

drop trigger if exists payment_transactions_no_update on public.payment_transactions;
create trigger payment_transactions_no_update before update or delete on public.payment_transactions for each row execute function public.payment_append_only_guard();

create or replace function public.payment_create_checkout(
  p_booking_id uuid,
  p_payer_id uuid,
  p_idempotency_key text,
  p_provider text
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_booking public.ride_bookings%rowtype;
  v_ride public.rides%rowtype;
  v_existing public.payments%rowtype;
  v_setting public.payment_commission_settings%rowtype;
  v_payment public.payments%rowtype;
  v_platform_fee numeric(12,2) := 0;
  v_expiry timestamptz;
begin
  if auth.role() <> 'service_role' then raise exception 'Payment creation is server-only'; end if;
  select * into v_booking from public.ride_bookings where id=p_booking_id for update;
  if not found or v_booking.passenger_id <> p_payer_id then raise exception 'Booking is not owned by the payer'; end if;
  select * into v_ride from public.rides where id=v_booking.ride_id;
  if v_booking.status <> 'awaiting_payment' then raise exception 'Booking is not awaiting sandbox payment'; end if;
  if v_booking.hold_expires_at is null or v_booking.hold_expires_at <= timezone('utc', now()) then raise exception 'The seat hold has expired'; end if;
  select * into v_existing from public.payments where service_type='ride' and service_id=p_booking_id and status in ('created','pending','succeeded','under_review') order by created_at desc limit 1 for update;
  if found then return jsonb_build_object('payment_id', v_existing.id, 'status', v_existing.status, 'amount', v_existing.amount, 'currency', v_existing.currency, 'provider', v_existing.provider, 'checkout_url', v_existing.checkout_url, 'expires_at', v_existing.expires_at, 'idempotent', true); end if;
  select * into v_setting from public.payment_commission_settings where service_type='ride' and active=true;
  v_expiry := least(v_booking.hold_expires_at, timezone('utc', now()) + interval '15 minutes');
  insert into public.payments(user_id, payer_id, ride_booking_id, service_type, service_id, amount, currency, status, provider, idempotency_key, commission_rate_snapshot, commission_fixed_snapshot, platform_fee, expires_at)
  values (p_payer_id, p_payer_id, p_booking_id, 'ride', p_booking_id, v_booking.amount, 'PKR', 'created', p_provider, p_idempotency_key, coalesce(v_setting.percentage_rate,0.10), coalesce(v_setting.fixed_amount,0), v_platform_fee, v_expiry)
  returning * into v_payment;
  insert into public.payment_transactions(payment_id, provider_reference, event_type, transaction_type, amount, status, signature_verified, raw_metadata, occurred_at)
  values (v_payment.id, 'checkout:' || v_payment.id, 'checkout_created', 'attempt', v_payment.amount, 'created', false, jsonb_build_object('service_type','ride','booking_id',p_booking_id), timezone('utc', now()));
  return jsonb_build_object('payment_id', v_payment.id, 'status', v_payment.status, 'amount', v_payment.amount, 'currency', v_payment.currency, 'provider', v_payment.provider, 'expires_at', v_payment.expires_at, 'idempotent', false);
end; $$;

create or replace function public.payment_process_webhook(
  p_provider text,
  p_provider_event_id text,
  p_payment_id uuid,
  p_provider_reference text,
  p_event_type text,
  p_event_status text,
  p_amount numeric,
  p_currency text,
  p_signature_verified boolean,
  p_payload_hash text,
  p_safe_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_payment public.payments%rowtype;
  v_booking public.ride_bookings%rowtype;
  v_ride public.rides%rowtype;
  v_tx public.payment_transactions%rowtype;
  v_status public.payment_status;
  v_refund_exists boolean;
begin
  if auth.role() <> 'service_role' then raise exception 'Webhook processing is server-only'; end if;
  if not p_signature_verified then raise exception 'Signature must be verified before processing'; end if;
  if p_provider_event_id is null or length(trim(p_provider_event_id)) < 8 then raise exception 'Provider event ID is required'; end if;
  select * into v_tx from public.payment_transactions where provider_event_id=p_provider_event_id;
  if found then return jsonb_build_object('duplicate', true, 'payment_id', v_tx.payment_id, 'status', 'ignored'); end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found then raise exception 'Payment not found'; end if;
  insert into public.payment_transactions(payment_id, provider_reference, provider_event_id, event_type, transaction_type, amount, status, signature_verified, raw_metadata, payload_hash, occurred_at)
  values (v_payment.id, coalesce(p_provider_reference, 'event') || ':event:' || p_provider_event_id, p_provider_event_id, p_event_type, 'webhook', coalesce(p_amount, v_payment.amount), case when p_event_status='succeeded' then 'succeeded' when p_event_status='failed' then 'failed' when p_event_status='cancelled' then 'cancelled' else 'under_review' end, true, coalesce(p_safe_metadata,'{}'::jsonb), p_payload_hash, timezone('utc', now()));
  if p_currency <> v_payment.currency or p_amount <> v_payment.amount then
    update public.payments set status='under_review', under_review_reason='Webhook amount or currency mismatch', provider_reference=coalesce(p_provider_reference, provider_reference), updated_at=timezone('utc', now()) where id=v_payment.id;
    perform public.notify_ride_user(v_payment.payer_id, 'payment_under_review', 'Payment needs review', 'The payment provider returned an amount or currency mismatch. No booking confirmation was granted.', '/payments');
    return jsonb_build_object('under_review', true, 'reason', 'amount_or_currency_mismatch');
  end if;
  if p_event_status='succeeded' then
    select * into v_booking from public.ride_bookings where id=v_payment.ride_booking_id for update;
    select * into v_ride from public.rides where id=v_booking.ride_id;
    if v_booking.status <> 'awaiting_payment' or v_booking.hold_expires_at is null or v_booking.hold_expires_at <= timezone('utc', now()) then
      update public.payments set status='under_review', under_review_reason='Successful payment arrived after booking hold expiry', provider_reference=p_provider_reference, updated_at=timezone('utc', now()) where id=v_payment.id;
      select exists(select 1 from public.refunds where payment_id=v_payment.id and status in ('requested','approved','processing')) into v_refund_exists;
      if not v_refund_exists then insert into public.refunds(payment_id, amount, reason, status, requested_by) values (v_payment.id, v_payment.amount, 'Successful payment received after seat hold expiry; automatic refund review required', 'requested', v_payment.payer_id); end if;
      perform public.notify_ride_user(v_payment.payer_id, 'payment_under_review', 'Payment received after hold expiry', 'Your payment is under review and a refund request was created. The expired seat was not confirmed.', '/payments');
      return jsonb_build_object('under_review', true, 'reason', 'hold_expired');
    end if;
    update public.payments set status='succeeded', succeeded_at=timezone('utc', now()), provider_reference=p_provider_reference, updated_at=timezone('utc', now()) where id=v_payment.id;
    update public.ride_bookings set status='confirmed', paid_at=timezone('utc', now()), updated_at=timezone('utc', now()) where id=v_booking.id;
    perform public.record_ride_booking_event(v_booking.id, 'awaiting_payment', 'confirmed', 'Sandbox payment verified by webhook');
    perform public.notify_ride_user(v_booking.passenger_id, 'payment_confirmed', 'Sandbox payment confirmed', 'Your ride booking is confirmed. This was a sandbox payment; no real money moved.', '/bookings/'||v_booking.id);
    perform public.notify_ride_user(v_ride.driver_id, 'payment_confirmed', 'Passenger payment confirmed', 'A passenger payment was verified and the seat is now permanently held.', '/provider/bookings/'||v_ride.id);
    return jsonb_build_object('confirmed', true, 'payment_id', v_payment.id);
  elsif p_event_status='failed' then
    v_status := 'failed';
  elsif p_event_status='cancelled' then
    v_status := 'cancelled';
  else
    v_status := 'under_review';
  end if;
  update public.payments set status=v_status, failed_at=case when v_status='failed' then timezone('utc', now()) else failed_at end, cancelled_at=case when v_status='cancelled' then timezone('utc', now()) else cancelled_at end, provider_reference=coalesce(p_provider_reference, provider_reference), updated_at=timezone('utc', now()) where id=v_payment.id;
  perform public.notify_ride_user(v_payment.payer_id, case when v_status='failed' then 'payment_failed' else 'payment_cancelled' end, case when v_status='failed' then 'Sandbox payment failed' else 'Sandbox payment cancelled' end, 'The seat hold remains available while it has not expired. You may retry payment.', '/bookings/'||v_payment.ride_booking_id);
  return jsonb_build_object('processed', true, 'status', v_status);
exception when unique_violation then
  return jsonb_build_object('duplicate', true, 'status', 'ignored');
end; $$;

create or replace function public.payment_request_refund(p_payment_id uuid, p_amount numeric, p_reason text, p_requested_by uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_payment public.payments%rowtype; v_refunded numeric; v_refund uuid;
begin
  if auth.role() <> 'service_role' then raise exception 'Refund requests are server-only'; end if;
  select * into v_payment from public.payments where id=p_payment_id for update;
  if not found or v_payment.status not in ('succeeded','under_review','partially_refunded') then raise exception 'Payment is not refundable'; end if;
  select coalesce(sum(amount),0) into v_refunded from public.refunds where payment_id=p_payment_id and status in ('requested','approved','processing','processed','completed');
  if p_amount <= 0 or p_amount > v_payment.amount - v_refunded then raise exception 'Refund exceeds the remaining paid amount'; end if;
  insert into public.refunds(payment_id, amount, reason, status, requested_by) values (p_payment_id, p_amount, trim(p_reason), 'requested', p_requested_by) returning id into v_refund;
  update public.payments set status='under_review', updated_at=timezone('utc', now()) where id=p_payment_id;
  return v_refund;
end; $$;

create or replace function public.payment_process_refund(p_refund_id uuid, p_admin_id uuid, p_provider_reference text, p_success boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_refund public.refunds%rowtype; v_payment public.payments%rowtype; v_total numeric;
begin
  if auth.role() <> 'service_role' or not public.payment_is_admin(p_admin_id) then raise exception 'Admin refund processing required'; end if;
  select * into v_refund from public.refunds where id=p_refund_id for update;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  if p_success then
    update public.refunds set status='processed', processed_by=p_admin_id, processed_at=timezone('utc', now()), payment_provider_reference=p_provider_reference where id=v_refund.id;
    select coalesce(sum(amount),0) into v_total from public.refunds where payment_id=v_payment.id and status in ('processed','completed');
    update public.payments set status=case when v_total >= v_payment.amount then 'refunded' else 'partially_refunded' end, updated_at=timezone('utc', now()) where id=v_payment.id;
    perform public.notify_ride_user(v_payment.payer_id, 'refund_processed', 'Sandbox refund processed', 'Your sandbox refund was recorded. No real money moved.', '/payments');
  else
    update public.refunds set status='failed', processed_by=p_admin_id, processed_at=timezone('utc', now()), payment_provider_reference=p_provider_reference where id=v_refund.id;
    perform public.notify_ride_user(v_payment.payer_id, 'refund_failed', 'Refund needs attention', 'The sandbox provider did not complete the refund. Support review is required.', '/payments');
  end if;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata) values (p_admin_id, case when p_success then 'payment.refund_processed' else 'payment.refund_failed' end, 'refund', v_refund.id, jsonb_build_object('payment_id', v_payment.id, 'amount', v_refund.amount));
  return jsonb_build_object('refund_id', v_refund.id, 'success', p_success);
end; $$;

create or replace function public.payment_on_booking_cancel()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_payment public.payments%rowtype; v_exists boolean;
begin
  if new.status in ('cancelled_by_driver','cancelled_by_passenger') and old.status <> new.status then
    select * into v_payment from public.payments where ride_booking_id=new.id and status='succeeded' order by created_at desc limit 1 for update;
    if found then
      select exists(select 1 from public.refunds where payment_id=v_payment.id and status in ('requested','approved','processing','processed','completed')) into v_exists;
      if not v_exists then insert into public.refunds(payment_id, amount, reason, status, requested_by) values (v_payment.id, v_payment.amount, case when new.status='cancelled_by_driver' then 'Automatic refund request: driver cancelled confirmed booking' else 'Automatic refund request: passenger cancelled a paid booking; apply disclosed cancellation policy' end, 'requested', new.passenger_id); end if;
      update public.payments set status='under_review', under_review_reason='Cancellation refund request pending review', updated_at=timezone('utc', now()) where id=v_payment.id;
      perform public.notify_ride_user(new.passenger_id, 'refund_requested', 'Refund request created', 'Your paid booking was cancelled and a sandbox refund request was recorded for review.', '/payments');
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists payment_booking_cancel_refund on public.ride_bookings;
create trigger payment_booking_cancel_refund after update of status on public.ride_bookings for each row execute function public.payment_on_booking_cancel();

create or replace function public.payment_on_booking_completed()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_payment public.payments%rowtype; v_ride public.rides%rowtype; v_rate numeric; v_fixed numeric; v_commission numeric; v_net numeric; v_settlement uuid;
begin
  if new.status='completed' and old.status <> 'completed' then
    select * into v_payment from public.payments where ride_booking_id=new.id and status in ('succeeded','partially_refunded') order by created_at desc limit 1;
    if found then
      select * into v_ride from public.rides where id=new.ride_id;
      v_rate := coalesce(v_payment.commission_rate_snapshot,0.10); v_fixed := coalesce(v_payment.commission_fixed_snapshot,0);
      v_commission := round((v_payment.amount * v_rate) + v_fixed, 2); v_net := greatest(v_payment.amount - v_commission, 0);
      insert into public.commissions(settlement_id, provider_id, source_type, source_id, service_type, gross_amount, commission_rate, rate_snapshot, fixed_amount, commission_amount, provider_amount, currency)
      values (null, v_ride.driver_id, 'ride', new.id, 'ride', v_payment.amount, v_rate, v_rate, v_fixed, v_commission, v_net, v_payment.currency)
      on conflict do nothing;
      insert into public.settlements(provider_id, ride_booking_id, payment_id, period_start, period_end, gross_amount, commission_amount, net_amount, status, eligible_at)
      values (v_ride.driver_id, new.id, v_payment.id, current_date, current_date, v_payment.amount, v_commission, v_net, 'eligible', timezone('utc', now()))
      on conflict (ride_booking_id) do update set status='eligible', eligible_at=timezone('utc', now()), gross_amount=excluded.gross_amount, commission_amount=excluded.commission_amount, net_amount=excluded.net_amount;
      select id into v_settlement from public.settlements where ride_booking_id=new.id;
      update public.commissions set settlement_id=v_settlement where source_type='ride' and source_id=new.id and settlement_id is null;
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists payment_booking_completed_settlement on public.ride_bookings;
create trigger payment_booking_completed_settlement after update of status on public.ride_bookings for each row execute function public.payment_on_booking_completed();

create or replace function public.payment_mark_settlement_paid(p_settlement_id uuid, p_admin_id uuid, p_reference text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_settlement public.settlements%rowtype;
begin
  if auth.role() <> 'service_role' or not public.payment_is_admin(p_admin_id) then raise exception 'Admin settlement action required'; end if;
  select * into v_settlement from public.settlements where id=p_settlement_id for update;
  if not found or v_settlement.status <> 'eligible' then raise exception 'Settlement is not eligible for payout'; end if;
  update public.settlements set status='paid', settlement_reference=trim(p_reference), paid_at=timezone('utc', now()) where id=p_settlement_id;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata) values (p_admin_id, 'settlement.marked_paid', 'settlement', p_settlement_id, jsonb_build_object('reference', trim(p_reference), 'amount', v_settlement.net_amount));
  perform public.notify_ride_user(v_settlement.provider_id, 'settlement_paid', 'Sandbox settlement recorded', 'Your provider settlement was marked paid manually. No real payout was made.', '/provider/earnings');
  return p_settlement_id;
end; $$;

-- The old development confirmation function is no longer callable by browser roles.
revoke execute on function public.dev_confirm_ride_booking(uuid) from public, anon, authenticated, service_role;

-- Strict browser-facing policies: reads only; all writes use server-side Edge Functions/RPCs.
drop policy if exists payments_owner_insert on public.payments;
drop policy if exists payments_admin_update on public.payments;
drop policy if exists transactions_admin_insert on public.payment_transactions;
drop policy if exists refunds_admin_manage on public.refunds;
drop policy if exists settlements_admin_manage on public.settlements;
drop policy if exists commissions_admin_manage on public.commissions;

create policy payment_commission_settings_admin_read on public.payment_commission_settings for select using (public.is_admin());
create policy payment_commission_settings_admin_update on public.payment_commission_settings for update using (public.is_admin()) with check (public.is_admin());
create policy payment_commission_settings_admin_insert on public.payment_commission_settings for insert with check (public.is_admin());
create policy payment_commission_settings_admin_delete on public.payment_commission_settings for delete using (public.is_admin());

create policy payment_transactions_admin_insert_service_only on public.payment_transactions for insert with check (auth.role() = 'service_role');
create policy refunds_owner_or_admin_insert_service_only on public.refunds for insert with check (auth.role() = 'service_role');
create policy refunds_owner_or_admin_update_service_only on public.refunds for update using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create policy settlements_admin_update_service_only on public.settlements for update using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create policy commissions_admin_insert_service_only on public.commissions for insert with check (auth.role() = 'service_role');

revoke insert, update, delete on public.payments from anon, authenticated;
revoke insert, update, delete on public.payment_transactions from anon, authenticated;
revoke insert, update, delete on public.refunds from anon, authenticated;
revoke insert, update, delete on public.settlements from anon, authenticated;
revoke insert, update, delete on public.commissions from anon, authenticated;

alter table public.payment_commission_settings enable row level security;

create or replace function public.payment_commission_settings_audit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
    values (auth.uid(), 'payment.commission_settings_updated', 'payment_commission_settings', new.id,
      jsonb_build_object('service_type', new.service_type, 'percentage_rate', new.percentage_rate, 'fixed_amount', new.fixed_amount));
  end if;
  return new;
end; $$;

drop trigger if exists payment_commission_settings_audit_trigger on public.payment_commission_settings;
create trigger payment_commission_settings_audit_trigger after update on public.payment_commission_settings for each row execute function public.payment_commission_settings_audit();
