-- Keep the Close Night safety check, but apply payment completeness only to
-- non-void sessions. A VOIDED session is resolved regardless of the lifecycle
-- state retained for reinstatement or any pre-void payment payload.

create or replace function public.bsb_close_night(p_session_token text,p_device_token text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v public.bsb_open_play_actor_context;
  n public.business_nights;
  unresolved_count integer;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select * into n from public.business_nights where organization_id=v.organization_id and status='OPEN' for update;
  if n.id is null then raise exception 'There is no open night'; end if;

  select count(*)::integer into unresolved_count
  from public.open_play_sessions s
  where s.night_id=n.id
    and s.status<>'VOIDED'
    and (
      s.status<>'COMPLETED'
      or (
        s.type='OPEN_BOWLING'
        and (not (s.data->'pricing' ? 'chargedTotalCents') or s.data->'pricing'->'chargedTotalCents'='null'::jsonb)
      )
    );

  if unresolved_count>0 then
    raise exception '% session%s still need resolution', unresolved_count, case when unresolved_count=1 then '' else 's' end;
  end if;

  update public.business_nights set status='CLOSED',closed_at=now(),closed_by=v.employee_id,updated_at=now() where id=n.id returning * into n;
  perform public.bsb_open_play_log_actor(v,n.id,null,'NIGHT_CLOSED','{}','Closed night','{}');
  return jsonb_build_object('id',n.id);
end $$;

grant execute on function public.bsb_close_night(text,text) to anon;
