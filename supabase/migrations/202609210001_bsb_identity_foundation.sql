create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if not exists (
    select 1 from pg_extension e join pg_namespace n on n.oid=e.extnamespace
    where e.extname='pgcrypto' and n.nspname='extensions'
  ) then
    raise exception 'pgcrypto must be installed in the extensions schema';
  end if;
end $$;

do $$ begin
  create type public.bsb_employee_role as enum ('OWNER', 'MANAGER', 'EMPLOYEE');
exception when duplicate_object then null;
end $$;

create table if not exists public.organizations (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.employees (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  pin_hash text not null,
  role public.bsb_employee_role not null default 'EMPLOYEE',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, display_name)
);

create table if not exists public.authorized_devices (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  display_name text not null,
  token_hash text not null unique,
  active boolean not null default true,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.employee_terminal_sessions (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  token_hash text not null unique,
  employee_id uuid not null references public.employees(id) on delete cascade,
  device_id uuid not null references public.authorized_devices(id) on delete cascade,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.organizations enable row level security;
alter table public.employees enable row level security;
alter table public.authorized_devices enable row level security;
alter table public.employee_terminal_sessions enable row level security;
revoke all on public.organizations, public.employees, public.authorized_devices, public.employee_terminal_sessions from anon, authenticated;

create or replace function public.bsb_device(p_token text)
returns public.authorized_devices
language sql security definer stable set search_path = public, pg_temp
as $$ select d.* from public.authorized_devices d where d.active and d.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') limit 1 $$;
revoke all on function public.bsb_device(text) from public, anon, authenticated;

create or replace function public.bsb_session_employee(p_token text)
returns public.employees
language sql security definer stable set search_path = public, pg_temp
as $$
  select e.* from public.employee_terminal_sessions s
  join public.employees e on e.id = s.employee_id
  join public.authorized_devices d on d.id = s.device_id
  where s.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and s.revoked_at is null
    and s.expires_at > now() and e.active and d.active limit 1
$$;
revoke all on function public.bsb_session_employee(text) from public, anon, authenticated;

create or replace function public.bsb_list_active_employees(p_device_token text)
returns table(id uuid, organization_id uuid, display_name text, role public.bsb_employee_role, active boolean)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_device public.authorized_devices;
begin
  v_device := public.bsb_device(p_device_token);
  if v_device.id is null then raise exception 'Unauthorized device'; end if;
  update public.authorized_devices set last_seen_at=now() where authorized_devices.id=v_device.id;
  return query select e.id,e.organization_id,e.display_name,e.role,e.active from public.employees e
    where e.organization_id=v_device.organization_id and e.active order by e.display_name;
end $$;

create or replace function public.bsb_verify_employee_pin(p_device_token text, p_employee_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_device public.authorized_devices; v_employee public.employees; v_token text; v_expires timestamptz;
begin
  if p_pin !~ '^\d{4}$' then raise exception 'Invalid credentials'; end if;
  v_device := public.bsb_device(p_device_token);
  if v_device.id is null then raise exception 'Unauthorized device'; end if;
  select * into v_employee from public.employees e where e.id=p_employee_id and e.organization_id=v_device.organization_id and e.active;
  if v_employee.id is null or extensions.crypt(p_pin,v_employee.pin_hash)<>v_employee.pin_hash then
    perform pg_sleep(0.15); raise exception 'Invalid credentials';
  end if;
  v_token := encode(extensions.gen_random_bytes(32),'hex'); v_expires := now()+interval '12 hours';
  insert into public.employee_terminal_sessions(token_hash,employee_id,device_id,expires_at)
    values(encode(extensions.digest(v_token,'sha256'),'hex'),v_employee.id,v_device.id,v_expires);
  return jsonb_build_object('session_token',v_token,'expires_at',v_expires,'employee',jsonb_build_object(
    'id',v_employee.id,'organization_id',v_employee.organization_id,'display_name',v_employee.display_name,'role',v_employee.role,'active',v_employee.active));
end $$;

create or replace function public.bsb_owner_list_employees(p_session_token text)
returns table(id uuid, organization_id uuid, display_name text, role public.bsb_employee_role, active boolean)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_owner public.employees;
begin
  v_owner:=public.bsb_session_employee(p_session_token);
  if v_owner.id is null or v_owner.role<>'OWNER' then raise exception 'Owner access required'; end if;
  return query select e.id,e.organization_id,e.display_name,e.role,e.active from public.employees e where e.organization_id=v_owner.organization_id order by e.display_name;
end $$;

create or replace function public.bsb_owner_save_employee(p_session_token text, p_employee_id uuid, p_display_name text, p_role public.bsb_employee_role, p_active boolean, p_pin text default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_owner public.employees; v_employee public.employees;
begin
  v_owner:=public.bsb_session_employee(p_session_token);
  if v_owner.id is null or v_owner.role<>'OWNER' then raise exception 'Owner access required'; end if;
  if btrim(p_display_name)='' then raise exception 'Display name is required'; end if;
  if p_pin is not null and p_pin !~ '^\d{4}$' then raise exception 'PIN must be exactly 4 digits'; end if;
  if p_employee_id is null then
    if p_pin is null then raise exception 'PIN is required'; end if;
    insert into public.employees(organization_id,display_name,pin_hash,role,active)
      values(v_owner.organization_id,btrim(p_display_name),extensions.crypt(p_pin,extensions.gen_salt('bf',10)),p_role,p_active) returning * into v_employee;
  else
    select * into v_employee from public.employees e
      where e.id=p_employee_id and e.organization_id=v_owner.organization_id
      for update;
    if v_employee.id is null then raise exception 'Employee not found'; end if;
    -- Lock the current active owners before evaluating a change that removes an
    -- owner. This keeps concurrent owner edits from both passing the check.
    if v_employee.active and v_employee.role='OWNER' and (not p_active or p_role<>'OWNER') then
      perform 1 from public.employees e
        where e.organization_id=v_owner.organization_id and e.active and e.role='OWNER'
        for update;
      if not exists (
        select 1 from public.employees e
        where e.organization_id=v_owner.organization_id and e.active and e.role='OWNER' and e.id<>p_employee_id
      ) then
        raise exception 'Organization must have at least one active owner.';
      end if;
    end if;
    update public.employees set display_name=btrim(p_display_name),role=p_role,active=p_active,
      pin_hash=case when p_pin is null then pin_hash else extensions.crypt(p_pin,extensions.gen_salt('bf',10)) end,updated_at=now()
      where id=p_employee_id and organization_id=v_owner.organization_id returning * into v_employee;
    if not p_active then update public.employee_terminal_sessions set revoked_at=now() where employee_id=v_employee.id and revoked_at is null; end if;
  end if;
  return jsonb_build_object('id',v_employee.id,'organization_id',v_employee.organization_id,'display_name',v_employee.display_name,'role',v_employee.role,'active',v_employee.active);
end $$;

grant execute on function public.bsb_list_active_employees(text) to anon;
grant execute on function public.bsb_verify_employee_pin(text,uuid,text) to anon;
grant execute on function public.bsb_owner_list_employees(text) to anon;
grant execute on function public.bsb_owner_save_employee(text,uuid,text,public.bsb_employee_role,boolean,text) to anon;

insert into public.organizations(name,slug) values('Blue Springs Bowl','blue-springs-bowl') on conflict(slug) do nothing;
