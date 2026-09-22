-- Trusted Device Experience
--
-- This forward-only migration preserves all existing device credentials,
-- employee sessions, setup codes, and RPC signatures. It expands only the
-- non-destructive device-management permissions needed by center managers and
-- adds stable error codes for client recovery UX.

create or replace function public.bsb_list_active_employees(p_device_token text)
returns table(id uuid, organization_id uuid, display_name text, role public.bsb_employee_role, active boolean)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_device public.authorized_devices;
begin
  v_device := public.bsb_device(p_device_token);
  if v_device.id is null then
    raise exception using errcode='BSB01', message='Device access removed';
  end if;
  update public.authorized_devices set last_seen_at=now() where authorized_devices.id=v_device.id;
  return query select e.id,e.organization_id,e.display_name,e.role,e.active from public.employees e
    where e.organization_id=v_device.organization_id and e.active order by e.display_name;
end $$;

create or replace function public.bsb_owner_list_devices(p_session_token text)
returns table(id uuid, display_name text, active boolean, last_seen_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_employee public.employees;
begin
  v_employee:=public.bsb_session_employee(p_session_token);
  if v_employee.id is null or v_employee.role not in ('OWNER','MANAGER') then
    raise exception 'Owner or Manager access required';
  end if;
  return query select d.id,d.display_name,d.active,d.last_seen_at,d.created_at
    from public.authorized_devices d
    where d.organization_id=v_employee.organization_id
    order by d.display_name;
end $$;

create or replace function public.bsb_owner_create_device_enrollment(p_session_token text,p_device_name text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_employee public.employees; c text; x public.device_enrollment_codes;
begin
  v_employee:=public.bsb_session_employee(p_session_token);
  if v_employee.id is null or v_employee.role not in ('OWNER','MANAGER') then
    raise exception 'Owner or Manager access required';
  end if;
  if btrim(p_device_name)='' then raise exception 'Device name is required'; end if;
  c:=upper(substr(encode(extensions.gen_random_bytes(10),'hex'),1,16));
  insert into public.device_enrollment_codes(organization_id,device_name,code_hash,expires_at,created_by)
    values(v_employee.organization_id,btrim(p_device_name),encode(extensions.digest(c,'sha256'),'hex'),now()+interval '15 minutes',v_employee.id)
    returning * into x;
  return jsonb_build_object('code',substr(c,1,8)||'-'||substr(c,9,8),'expires_at',x.expires_at,'device_name',x.device_name);
end $$;

create or replace function public.bsb_redeem_device_enrollment(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare c text:=upper(replace(btrim(p_code),'-','')); x public.device_enrollment_codes; d public.authorized_devices; token text;
begin
  if c !~ '^[0-9A-F]{16}$' then
    raise exception using errcode='BSB02', message='Setup code unavailable';
  end if;
  select * into x from public.device_enrollment_codes
    where code_hash=encode(extensions.digest(c,'sha256'),'hex') for update;
  if x.id is null or x.used_at is not null or x.expires_at<=now() then
    raise exception using errcode='BSB02', message='Setup code unavailable';
  end if;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.authorized_devices(organization_id,display_name,token_hash,active)
    values(x.organization_id,x.device_name,encode(extensions.digest(token,'sha256'),'hex'),true)
    returning * into d;
  update public.device_enrollment_codes set used_at=now() where id=x.id;
  return jsonb_build_object('device_token',token,'device_name',d.display_name);
end $$;

-- Existing grants and signatures are intentionally retained. Device removal
-- remains in bsb_owner_set_device_active and remains OWNER-only.
