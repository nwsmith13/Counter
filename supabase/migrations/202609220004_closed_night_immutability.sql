-- Closed-night immutability and Close Night serialization barrier.
--
-- Every write to a session or lane assignment locks the owning business-night
-- row before it is allowed to proceed. bsb_close_night already locks that same
-- row before evaluating unresolved sessions. PostgreSQL therefore serializes a
-- concurrent mutation and close in one of two safe orders: the mutation holds
-- the night lock and Close Night observes its committed result, or Close Night
-- closes first and the waiting mutation receives BSB03.

create or replace function public.bsb_open_play_require_open_night_for_row()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_night_id uuid;
  v_night public.business_nights;
begin
  v_night_id := case when tg_op = 'DELETE' then old.night_id else new.night_id end;

  select * into v_night
  from public.business_nights
  where id = v_night_id
  for update;

  if v_night.id is null then
    raise exception using errcode='BSB03', message='This night has already been closed. Past sessions can no longer be changed.';
  end if;

  if v_night.status <> 'OPEN' then
    raise exception using errcode='BSB03', message='This night has already been closed. Past sessions can no longer be changed.';
  end if;

  -- Prevent a write from moving an existing row between nights. The application
  -- has no supported cross-night session or assignment transfer operation.
  if tg_op = 'UPDATE' and new.night_id is distinct from old.night_id then
    raise exception using errcode='BSB03', message='Sessions and lane assignments cannot be moved between business nights.';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end
$$;

revoke all on function public.bsb_open_play_require_open_night_for_row() from public, anon, authenticated;

drop trigger if exists bsb_open_play_sessions_open_night_barrier on public.open_play_sessions;
create trigger bsb_open_play_sessions_open_night_barrier
before insert or update or delete on public.open_play_sessions
for each row execute function public.bsb_open_play_require_open_night_for_row();

drop trigger if exists bsb_open_play_lane_assignments_open_night_barrier on public.open_play_lane_assignments;
create trigger bsb_open_play_lane_assignments_open_night_barrier
before insert or update or delete on public.open_play_lane_assignments
for each row execute function public.bsb_open_play_require_open_night_for_row();

-- Reopen is an operational correction within the currently open night. VOIDED
-- is intentionally excluded: reinstate is the only supported way to restore a
-- voided session, and the trigger above independently rejects closed nights.
create or replace function public.bsb_reopen_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v public.bsb_open_play_actor_context;
  s public.open_play_sessions;
  lanes integer[];
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select * into s from public.open_play_sessions
    where id=p_session_id and organization_id=v.organization_id
    for update;
  if s.id is null or s.status not in ('AWAITING_CLOSE','COMPLETED') then
    raise exception 'This session cannot be reopened';
  end if;
  if s.version<>p_expected_version then raise exception 'Stale session'; end if;
  perform public.bsb_open_play_validate_data(s.type,p_data);
  with changed as (
    update public.open_play_lane_assignments
    set ended_at=null,ended_by=null,end_reason=null,updated_at=now()
    where session_id=s.id and end_reason='SESSION_ENDED'
    returning lane_number
  )
  select coalesce(array_agg(lane_number),'{}') into lanes from changed;
  update public.open_play_sessions
  set status='ACTIVE',data=p_data,ended_at=null,ended_by=null,reopened_at=now(),
      reopened_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1
  where id=s.id returning * into s;
  perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_REOPENED',lanes,
    'Reopened session',jsonb_build_object('correction',true));
  return jsonb_build_object('id',s.id,'version',s.version);
exception when unique_violation then
  raise exception 'Cannot reopen because a lane is now in use';
end
$$;

grant execute on function public.bsb_reopen_session(text,text,uuid,integer,jsonb) to anon;
