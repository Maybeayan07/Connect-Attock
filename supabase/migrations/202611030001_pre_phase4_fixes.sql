-- Connect Attock pre-Phase-4 combined fixes.
-- Additive only: run after 202610310001, 202610310002 and 202611010001.
-- Safe for databases where prior migrations are already applied.

-- The old shared trigger function referenced columns that do not exist on every
-- table it protected. These table-specific functions deliberately inspect only
-- columns belonging to their attached table. SQL Editor/service-role sessions
-- and the auth signup trigger are allowed to perform maintenance.
create or replace function public.ca_is_authenticated_user()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and coalesce(auth.role(), '') = 'authenticated';
$$;

create or replace function public.protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.ca_is_authenticated_user() or public.is_admin() then return new; end if;
  if new.account_status is distinct from old.account_status then
    raise exception 'Only an admin or approved server path can change account status';
  end if;
  return new;
end; $$;

create or replace function public.protect_driver_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.ca_is_authenticated_user() or public.is_admin() then return new; end if;
  if new.verification_status is distinct from old.verification_status
     or new.reviewed_by is distinct from old.reviewed_by
     or new.reviewed_at is distinct from old.reviewed_at
     or new.rejection_reason is distinct from old.rejection_reason
     or new.reliability_score is distinct from old.reliability_score
     or new.rating_average is distinct from old.rating_average
     or new.rating_count is distinct from old.rating_count
     or new.completed_trips is distinct from old.completed_trips
     or new.reliability_cancellations is distinct from old.reliability_cancellations then
    raise exception 'Only an admin or approved server path can change provider review fields';
  end if;
  return new;
end; $$;

create or replace function public.protect_vehicle_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.ca_is_authenticated_user() or public.is_admin() then return new; end if;
  if new.status is distinct from old.status then
    raise exception 'Only an admin or approved server path can change vehicle status';
  end if;
  return new;
end; $$;

create or replace function public.protect_role_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.ca_is_authenticated_user() and not public.is_admin() then
    raise exception 'Only an admin or server path can change roles';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end; $$;

drop trigger if exists profiles_protected_status on public.profiles;
drop trigger if exists driver_profiles_protected_status on public.driver_profiles;
drop trigger if exists vehicles_protected_status on public.vehicles;
create trigger profiles_protected_status before update on public.profiles for each row execute function public.protect_profile_fields();
create trigger driver_profiles_protected_status before update on public.driver_profiles for each row execute function public.protect_driver_profile_fields();
create trigger vehicles_protected_status before update on public.vehicles for each row execute function public.protect_vehicle_fields();
drop trigger if exists user_roles_protected_fields on public.user_roles;
create trigger user_roles_protected_fields before update or delete on public.user_roles for each row execute function public.protect_role_fields();
drop function if exists public.prevent_protected_status_changes();

-- A supported server-side path for the user's own deactivation.
create or replace function public.deactivate_my_account()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.profiles set account_status = 'deactivated', updated_at = timezone('utc', now()) where id = auth.uid();
end; $$;
grant execute on function public.deactivate_my_account() to authenticated;

-- Private verification bucket. The bucket is never public.
insert into storage.buckets (id, name, public)
values ('verification-documents', 'verification-documents', false)
on conflict (id) do update set public = false;

drop policy if exists verification_docs_object_owner_insert on storage.objects;
drop policy if exists verification_docs_object_owner_read on storage.objects;
drop policy if exists verification_docs_object_admin_read on storage.objects;
drop policy if exists verification_docs_object_owner_delete on storage.objects;
create policy verification_docs_object_owner_insert on storage.objects for insert to authenticated
with check (
  bucket_id = 'verification-documents'
  and (storage.foldername(name))[1] = auth.uid()::text
  and lower(coalesce(metadata->>'mimetype', '')) in ('image/jpeg','image/png','image/webp','application/pdf')
  and coalesce((metadata->>'size')::bigint, 0) between 1 and 10485760
);
create policy verification_docs_object_owner_read on storage.objects for select to authenticated
using (bucket_id = 'verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);
create policy verification_docs_object_admin_read on storage.objects for select to authenticated
using (bucket_id = 'verification-documents' and public.is_admin());
create policy verification_docs_object_owner_delete on storage.objects for delete to authenticated
using (bucket_id = 'verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);

-- Replace the permissive document policies with status-safe ownership rules.
drop policy if exists documents_insert_owner on public.verification_documents;
drop policy if exists documents_update_admin on public.verification_documents;
create policy documents_insert_owner_safe on public.verification_documents for insert to authenticated
with check (user_id = auth.uid() and status = 'pending' and reviewed_by is null and reviewed_at is null);
create policy documents_update_admin_safe on public.verification_documents for update to authenticated
using (public.is_admin()) with check (public.is_admin());

create or replace function public.submit_provider_verification()
returns public.verification_status language plpgsql security definer set search_path = public as $$
declare v_status public.verification_status; v_count integer;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select verification_status into v_status from public.driver_profiles where user_id = auth.uid() for update;
  if not found then
    insert into public.driver_profiles(user_id) values (auth.uid());
    v_status := 'not_submitted';
  end if;
  if v_status not in ('not_submitted','rejected') then return v_status; end if;
  select count(*) into v_count from public.verification_documents where user_id = auth.uid() and status = 'pending' and document_type in ('identity','driving_licence','vehicle_registration','vehicle_image');
  if v_count < 4 then raise exception 'Upload identity, driving licence, vehicle registration and vehicle image before submitting'; end if;
  update public.driver_profiles set verification_status = 'pending', reviewed_by = null, reviewed_at = null, rejection_reason = null, updated_at = timezone('utc', now()) where user_id = auth.uid();
  update public.verification_documents set status = 'pending', reviewed_by = null, reviewed_at = null, rejection_reason = null where user_id = auth.uid();
  return 'pending';
end; $$;
grant execute on function public.submit_provider_verification() to authenticated;

create or replace function public.admin_review_provider(p_provider_id uuid, p_approve boolean, p_reason text default null)
returns public.verification_status language plpgsql security definer set search_path = public as $$
declare v_status public.verification_status; v_action text;
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;
  if p_approve then
    v_status := 'approved'; v_action := 'provider.approved';
  else
    if nullif(trim(p_reason), '') is null then raise exception 'A rejection reason is required'; end if;
    v_status := 'rejected'; v_action := 'provider.rejected';
  end if;
  update public.driver_profiles set verification_status=v_status, reviewed_by=auth.uid(), reviewed_at=timezone('utc', now()), rejection_reason=case when p_approve then null else trim(p_reason) end, updated_at=timezone('utc', now()) where user_id=p_provider_id;
  if not found then raise exception 'Provider profile not found'; end if;
  update public.verification_documents set status=v_status, reviewed_by=auth.uid(), reviewed_at=timezone('utc', now()), rejection_reason=case when p_approve then null else trim(p_reason) end where user_id=p_provider_id;
  if p_approve then insert into public.user_roles(user_id, role) values (p_provider_id, 'service_provider') on conflict do nothing; end if;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), v_action, 'driver_profile', p_provider_id, jsonb_build_object('reason', p_reason));
  perform public.notify_ride_user(p_provider_id, case when p_approve then 'provider_approved' else 'provider_rejected' end, case when p_approve then 'Provider verification approved' else 'Provider verification needs changes' end, case when p_approve then 'You can now manage rides and vehicles.' else coalesce(trim(p_reason), 'Please review and resubmit your documents.') end, '/provider/verification');
  return v_status;
end; $$;
grant execute on function public.admin_review_provider(uuid, boolean, text) to authenticated;

create or replace function public.admin_review_vehicle(p_vehicle_id uuid, p_approve boolean, p_reason text default null)
returns public.vehicle_status language plpgsql security definer set search_path = public as $$
declare v_status public.vehicle_status; v_provider uuid;
begin
  if not public.is_admin() then raise exception 'Admin role required'; end if;
  if not p_approve and nullif(trim(p_reason), '') is null then raise exception 'A rejection reason is required'; end if;
  v_status := case when p_approve then 'approved' else 'rejected' end;
  update public.vehicles set status=v_status, updated_at=timezone('utc', now()) where id=p_vehicle_id returning provider_id into v_provider;
  if v_provider is null then raise exception 'Vehicle not found'; end if;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata) values (auth.uid(), case when p_approve then 'vehicle.approved' else 'vehicle.rejected' end, 'vehicle', p_vehicle_id, jsonb_build_object('reason', p_reason));
  perform public.notify_ride_user(v_provider, 'vehicle_reviewed', 'Vehicle review updated', case when p_approve then 'Your vehicle is approved for ride publishing.' else coalesce(trim(p_reason), 'Your vehicle was not approved.') end, '/provider/vehicles');
  return v_status;
end; $$;
grant execute on function public.admin_review_vehicle(uuid, boolean, text) to authenticated;

-- Prevent direct role inserts/deletes even if a policy is accidentally widened later.
revoke insert, update, delete on public.user_roles from authenticated;

-- Provider verification review reads remain admin-only through existing RLS.
