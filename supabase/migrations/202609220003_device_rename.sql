-- The existing bsb_owner_list_devices(text) has a five-column OUT row type.
-- PostgreSQL forbids CREATE OR REPLACE from changing that row type, so preserve
-- the established RPC contract and add a current-aware companion RPC instead.
-- No device credential, terminal session, or access status is changed here.

create or replace function public.bsb_owner_list_devices_with_current(p_session_token text)
returns table(id uuid, display_name text, active boolean, last_seen_at timestamptz, created_at timestamptz, is_current boolean)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_employee public.employees; v_device_id uuid;
begin
  v_employee:=public.bsb_session_employee(p_session_token);
  if v_employee.id is null or v_employee.role not in ('OWNER','MANAGER') then raise exception 'Owner or Manager access required'; end if;
  select device_id into v_device_id from public.employee_terminal_sessions
    where token_hash=encode(extensions.digest(p_session_token,'sha256'),'hex') and revoked_at is null limit 1;
  return query select d.id,d.display_name,d.active,d.last_seen_at,d.created_at,(d.id=v_device_id)
    from public.authorized_devices d where d.organization_id=v_employee.organization_id
    order by d.active desc,d.display_name;
end $$;

create or replace function public.bsb_owner_rename_device(p_session_token text,p_device_id uuid,p_display_name text)
returns table(id uuid, display_name text)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_employee public.employees; v_name text:=btrim(p_display_name);
begin
  v_employee:=public.bsb_session_employee(p_session_token);
  if v_employee.id is null or v_employee.role not in ('OWNER','MANAGER') then raise exception 'Owner or Manager access required'; end if;
  if char_length(v_name) not between 1 and 80 then raise exception 'Device name must be between 1 and 80 characters'; end if;
  return query update public.authorized_devices d set display_name=v_name,updated_at=now()
    where d.id=p_device_id and d.organization_id=v_employee.organization_id returning d.id,d.display_name;
  if not found then raise exception 'Device not found'; end if;
end $$;

grant execute on function public.bsb_owner_rename_device(text,uuid,text) to anon;
grant execute on function public.bsb_owner_list_devices_with_current(text) to anon;
