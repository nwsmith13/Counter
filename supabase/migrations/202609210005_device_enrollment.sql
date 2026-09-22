create table public.device_enrollment_codes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  device_name text not null check (char_length(btrim(device_name)) between 1 and 80),
  code_hash text not null unique,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_by uuid not null references public.employees(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create index device_enrollment_codes_pending on public.device_enrollment_codes(organization_id, expires_at) where used_at is null;
alter table public.device_enrollment_codes enable row level security;
revoke all on public.device_enrollment_codes from anon, authenticated;

create or replace function public.bsb_owner_list_devices(p_session_token text)
returns table(id uuid, display_name text, active boolean, last_seen_at timestamptz, created_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.employees;
begin v:=public.bsb_session_employee(p_session_token); if v.id is null or v.role<>'OWNER' then raise exception 'Owner access required'; end if;
 return query select d.id,d.display_name,d.active,d.last_seen_at,d.created_at from public.authorized_devices d where d.organization_id=v.organization_id order by d.display_name; end $$;

create or replace function public.bsb_owner_create_device_enrollment(p_session_token text,p_device_name text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.employees; c text; x public.device_enrollment_codes;
begin v:=public.bsb_session_employee(p_session_token); if v.id is null or v.role<>'OWNER' then raise exception 'Owner access required'; end if; if btrim(p_device_name)='' then raise exception 'Device name is required'; end if;
  -- 64 bits, rendered as a 16-character uppercase hex code in two touch-friendly groups.
  c:=upper(substr(encode(extensions.gen_random_bytes(10),'hex'),1,16));
  insert into public.device_enrollment_codes(organization_id,device_name,code_hash,expires_at,created_by) values(v.organization_id,btrim(p_device_name),encode(extensions.digest(c,'sha256'),'hex'),now()+interval '15 minutes',v.id) returning * into x;
  return jsonb_build_object('code',substr(c,1,8)||'-'||substr(c,9,8),'expires_at',x.expires_at,'device_name',x.device_name);
end $$;

create or replace function public.bsb_redeem_device_enrollment(p_code text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare c text:=upper(replace(btrim(p_code),'-','')); x public.device_enrollment_codes; d public.authorized_devices; token text;
begin if c !~ '^[0-9A-F]{16}$' then raise exception 'Invalid or expired setup code'; end if;
  select * into x from public.device_enrollment_codes where code_hash=encode(extensions.digest(c,'sha256'),'hex') for update;
  if x.id is null or x.used_at is not null or x.expires_at<=now() then raise exception 'Invalid or expired setup code'; end if;
  token:=encode(extensions.gen_random_bytes(32),'hex');
  insert into public.authorized_devices(organization_id,display_name,token_hash,active) values(x.organization_id,x.device_name,encode(extensions.digest(token,'sha256'),'hex'),true) returning * into d;
  update public.device_enrollment_codes set used_at=now() where id=x.id;
  return jsonb_build_object('device_token',token,'device_name',d.display_name);
end $$;

create or replace function public.bsb_owner_set_device_active(p_session_token text,p_device_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.employees; d public.authorized_devices;
begin v:=public.bsb_session_employee(p_session_token); if v.id is null or v.role<>'OWNER' then raise exception 'Owner access required'; end if;
 if p_active then raise exception 'Inactive devices must be reauthorized with a new setup code'; end if;
 select * into d from public.authorized_devices where id=p_device_id and organization_id=v.organization_id for update; if d.id is null then raise exception 'Device not found'; end if;
 if not p_active and d.id=(select device_id from public.employee_terminal_sessions where token_hash=encode(extensions.digest(p_session_token,'sha256'),'hex') limit 1) then raise exception 'Use another authorized device to deactivate this device'; end if;
 update public.authorized_devices set active=false,updated_at=now() where id=d.id;
 update public.employee_terminal_sessions set revoked_at=now() where device_id=d.id and revoked_at is null;
end $$;

grant execute on function public.bsb_owner_list_devices(text) to anon;
grant execute on function public.bsb_owner_create_device_enrollment(text,text) to anon;
grant execute on function public.bsb_redeem_device_enrollment(text) to anon;
grant execute on function public.bsb_owner_set_device_active(text,uuid,boolean) to anon;
