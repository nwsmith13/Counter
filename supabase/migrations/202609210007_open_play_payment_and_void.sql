-- Slice 5: payment-language activity context and authoritative session void/reinstate.

alter table public.open_play_sessions
  add column if not exists voided_at timestamptz,
  add column if not exists voided_by uuid references public.employees(id) on delete restrict,
  add column if not exists voided_by_name text,
  add column if not exists void_category text,
  add column if not exists void_note text,
  add column if not exists pre_void_status public.bsb_open_play_session_status,
  add column if not exists reinstated_at timestamptz,
  add column if not exists reinstated_by uuid references public.employees(id) on delete restrict,
  add column if not exists reinstated_by_name text,
  add column if not exists reinstatement_note text;

alter table public.open_play_sessions
  add constraint open_play_sessions_void_context check (
    (voided_at is null and voided_by is null and voided_by_name is null and void_category is null and void_note is null and pre_void_status is null)
    or
    (voided_at is not null and voided_by is not null and char_length(btrim(voided_by_name)) > 0
      and void_category in ('ENTERED_BY_MISTAKE','TRAINING_TEST','DUPLICATE','OTHER')
      and char_length(btrim(void_note)) between 3 and 500
      and pre_void_status in ('AWAITING_CLOSE','COMPLETED'))
  ),
  add constraint open_play_sessions_reinstatement_context check (
    (reinstated_at is null and reinstated_by is null and reinstated_by_name is null and reinstatement_note is null)
    or
    (reinstated_at is not null and reinstated_by is not null and char_length(btrim(reinstated_by_name)) > 0
      and char_length(btrim(reinstatement_note)) between 3 and 500)
  );

create or replace function public.bsb_get_open_play_state(p_session_token text, p_device_token text)
returns jsonb language plpgsql security definer stable set search_path = public, pg_temp
as $$
declare v public.bsb_open_play_actor_context; v_open uuid; v_previous uuid; v_activity_night uuid;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  select id into v_open from public.business_nights where organization_id=v.organization_id and status='OPEN';
  select id into v_previous from public.business_nights where organization_id=v.organization_id and status='CLOSED' order by closed_at desc limit 1;
  v_activity_night:=coalesce(v_open,v_previous);
  return jsonb_build_object(
    'settings',(select settings from public.open_play_settings where organization_id=v.organization_id),
    'leagues',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'active',active,'sortOrder',sort_order) order by sort_order) from public.open_play_leagues where organization_id=v.organization_id),'[]'::jsonb),
    'laneConditions',coalesce((select jsonb_agg(jsonb_build_object('laneNumber',lane_number,'condition',condition,'note',note,'updatedAt',updated_at) order by lane_number) from public.open_play_lane_conditions where organization_id=v.organization_id),'[]'::jsonb),
    'currentNight',(select jsonb_build_object('id',id,'businessDate',business_date,'openedAt',opened_at,'closedAt',closed_at,'status',case when status='CLOSED' then 'ARCHIVED' else 'OPEN' end) from public.business_nights where id=v_open),
    'previousNight',(select jsonb_build_object('id',id,'businessDate',business_date,'openedAt',opened_at,'closedAt',closed_at,'status','ARCHIVED') from public.business_nights where id=v_previous),
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'type',type,'status',status,'startedAt',started_at,'endedAt',ended_at,'createdAt',created_at,'updatedAt',updated_at,'data',data,'version',version,'voidedAt',voided_at,'voidedBy',voided_by,'voidedByName',voided_by_name,'voidCategory',void_category,'voidNote',void_note,'preVoidStatus',pre_void_status,'reinstatedAt',reinstated_at,'reinstatedBy',reinstated_by,'reinstatedByName',reinstated_by_name,'reinstatementNote',reinstatement_note)) from public.open_play_sessions where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'laneAssignments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'sessionId',session_id,'laneNumber',lane_number,'startedAt',started_at,'billingStartedAt',billing_started_at,'billingGroupId',billing_group_id,'billableStartedAt',billable_started_at,'endedAt',ended_at,'endReason',end_reason,'downOverrideConfirmed',down_override_confirmed)) from public.open_play_lane_assignments where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'activity',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'occurredAt',occurred_at,'type',type,'sessionId',session_id,'laneNumbers',lane_numbers,'summary',summary,'employeeId',performed_by,'employeeName',performed_by_name,'deviceId',device_id,'details',details) order by occurred_at desc) from (select * from public.open_play_activity where night_id=v_activity_night order by occurred_at desc limit 200) a),'[]'::jsonb)
  );
end $$;

create or replace function public.bsb_end_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[]; label text;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'ACTIVE' then raise exception 'This session is not active'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); with changed as (update public.open_play_lane_assignments set ended_at=now(),ended_by=v.employee_id,end_reason='SESSION_ENDED',updated_at=now() where session_id=s.id and ended_at is null returning lane_number) select coalesce(array_agg(lane_number order by lane_number),'{}') into lanes from changed; update public.open_play_sessions set status='AWAITING_CLOSE',data=p_data,ended_at=now(),ended_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; label:=case when s.type='PRE_POST' then 'Ended '||case when p_data->>'designation'='POST' then 'Post-Bowl' else 'Pre-Bowl' end when s.type='PARTY' then 'Ended Party' else 'Ended Open Bowling' end; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_ENDED',lanes,label,jsonb_build_object('sessionType',s.type,'sessionTypeLabel',case when s.type='PRE_POST' then case when p_data->>'designation'='POST' then 'Post-Bowl' else 'Pre-Bowl' end when s.type='PARTY' then 'Party' else 'Open Bowling' end,'laneHistory',to_jsonb(lanes))); return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_checkout_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_data jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; lanes integer[]; charged integer; calculated integer; note text; label text;
begin v:=public.bsb_open_play_require_actor(p_session_token,p_device_token); select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update; if s.id is null or s.status<>'AWAITING_CLOSE' then raise exception 'End the session before completing it'; end if; if s.version<>p_expected_version then raise exception 'Stale session'; end if; perform public.bsb_open_play_validate_data(s.type,p_data); if s.type='OPEN_BOWLING' and (not (p_data->'pricing' ? 'chargedTotalCents') or p_data->'pricing'->'chargedTotalCents'='null'::jsonb) then raise exception 'Payment amount is required'; end if; select coalesce(array_agg(lane_number order by started_at,created_at,lane_number),'{}') into lanes from public.open_play_lane_assignments where session_id=s.id; charged:=case when s.type='OPEN_BOWLING' then (p_data->'pricing'->>'chargedTotalCents')::integer when s.type='PARTY' then coalesce((p_data->>'partyAmountCents')::integer,0) else null end; calculated:=case when s.type='OPEN_BOWLING' then (p_data->'pricing'->>'calculatedTotalCents')::integer when s.type='PARTY' then charged else null end; note:=case when s.type='OPEN_BOWLING' then nullif(p_data->'pricing'->>'adjustmentNote','') end; update public.open_play_sessions set status='COMPLETED',data=p_data,checked_out_at=now(),checked_out_by=v.employee_id,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s; if s.type='PRE_POST' then label:=case when p_data->>'designation'='POST' then 'Ended Post-Bowl' else 'Ended Pre-Bowl' end; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_COMPLETED',lanes,label,jsonb_build_object('sessionType',s.type,'sessionTypeLabel',case when p_data->>'designation'='POST' then 'Post-Bowl' else 'Pre-Bowl' end,'laneHistory',to_jsonb(lanes))); else label:=case when s.type='PARTY' then 'Payment Complete · Party' else 'Payment Complete · Open Bowling' end; perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'PAYMENT_COMPLETED',lanes,label,jsonb_strip_nulls(jsonb_build_object('sessionType',s.type,'sessionTypeLabel',case when s.type='PARTY' then 'Party' else 'Open Bowling' end,'laneHistory',to_jsonb(lanes),'amountPaidCents',charged,'calculatedTotalCents',calculated,'adjustmentCents',charged-calculated,'adjustmentNote',note))); end if; return jsonb_build_object('id',s.id,'version',s.version); end $$;

create or replace function public.bsb_void_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_category text,p_note text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; employee_name text; lanes integer[]; amount integer; type_label text;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  if v.employee_role='EMPLOYEE' then raise exception 'Manager access required'; end if;
  if p_category not in ('ENTERED_BY_MISTAKE','TRAINING_TEST','DUPLICATE','OTHER') then raise exception 'Select a valid void reason'; end if;
  if char_length(btrim(coalesce(p_note,''))) not between 3 and 500 then raise exception 'A meaningful void note is required'; end if;
  select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update;
  if s.id is null then raise exception 'Session not found'; end if;
  if s.version<>p_expected_version then raise exception 'Stale session'; end if;
  if s.status not in ('AWAITING_CLOSE','COMPLETED') then raise exception 'End the session before voiding it'; end if;
  if exists(select 1 from public.open_play_lane_assignments where session_id=s.id and ended_at is null) then raise exception 'Active lane assignments must be ended before voiding'; end if;
  select display_name into employee_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
  select coalesce(array_agg(lane_number order by started_at,created_at,lane_number),'{}') into lanes from public.open_play_lane_assignments where session_id=s.id;
  type_label:=case when s.type='OPEN_BOWLING' then 'Open Bowling' when s.type='PARTY' then 'Party' else case when s.data->>'designation'='POST' then 'Post-Bowl' else 'Pre-Bowl' end end;
  amount:=case when s.type='OPEN_BOWLING' then coalesce((s.data->'pricing'->>'chargedTotalCents')::integer,(s.data->'pricing'->>'calculatedTotalCents')::integer,0) when s.type='PARTY' then coalesce((s.data->>'partyAmountCents')::integer,0) else 0 end;
  update public.open_play_sessions set status='VOIDED',voided_at=now(),voided_by=v.employee_id,voided_by_name=employee_name,void_category=p_category,void_note=btrim(p_note),pre_void_status=s.status,reinstated_at=null,reinstated_by=null,reinstated_by_name=null,reinstatement_note=null,updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s;
  perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_VOIDED',lanes,'Voided '||type_label,jsonb_build_object('sessionType',s.type,'sessionTypeLabel',type_label,'laneHistory',to_jsonb(lanes),'voidCategory',p_category,'voidNote',btrim(p_note),'excludedAmountCents',amount,'previousStatus',s.pre_void_status));
  return jsonb_build_object('id',s.id,'version',s.version);
end $$;

create or replace function public.bsb_reinstate_session(p_session_token text,p_device_token text,p_session_id uuid,p_expected_version integer,p_note text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$ declare v public.bsb_open_play_actor_context; s public.open_play_sessions; employee_name text; lanes integer[]; type_label text;
begin
  v:=public.bsb_open_play_require_actor(p_session_token,p_device_token);
  if v.employee_role='EMPLOYEE' then raise exception 'Manager access required'; end if;
  if char_length(btrim(coalesce(p_note,''))) not between 3 and 500 then raise exception 'A meaningful reinstatement note is required'; end if;
  select * into s from public.open_play_sessions where id=p_session_id and organization_id=v.organization_id for update;
  if s.id is null or s.status<>'VOIDED' or s.pre_void_status not in ('AWAITING_CLOSE','COMPLETED') then raise exception 'This session cannot be reinstated'; end if;
  if s.version<>p_expected_version then raise exception 'Stale session'; end if;
  if exists(select 1 from public.open_play_lane_assignments where session_id=s.id and ended_at is null) then raise exception 'Voided session has active lane assignments'; end if;
  select display_name into employee_name from public.employees where id=v.employee_id and organization_id=v.organization_id;
  select coalesce(array_agg(lane_number order by started_at,created_at,lane_number),'{}') into lanes from public.open_play_lane_assignments where session_id=s.id;
  type_label:=case when s.type='OPEN_BOWLING' then 'Open Bowling' when s.type='PARTY' then 'Party' else case when s.data->>'designation'='POST' then 'Post-Bowl' else 'Pre-Bowl' end end;
  update public.open_play_sessions set status=s.pre_void_status,reinstated_at=now(),reinstated_by=v.employee_id,reinstated_by_name=employee_name,reinstatement_note=btrim(p_note),updated_at=now(),updated_by=v.employee_id,version=version+1 where id=s.id returning * into s;
  perform public.bsb_open_play_log_actor(v,s.night_id,s.id,'SESSION_REINSTATED',lanes,'Reinstated '||type_label,jsonb_build_object('sessionType',s.type,'sessionTypeLabel',type_label,'laneHistory',to_jsonb(lanes),'reinstatementNote',btrim(p_note),'restoredStatus',s.status));
  return jsonb_build_object('id',s.id,'version',s.version);
end $$;

grant execute on function public.bsb_get_open_play_state(text,text) to anon;
grant execute on function public.bsb_end_session(text,text,uuid,integer,jsonb) to anon;
grant execute on function public.bsb_checkout_session(text,text,uuid,integer,jsonb) to anon;
grant execute on function public.bsb_void_session(text,text,uuid,integer,text,text) to anon;
grant execute on function public.bsb_reinstate_session(text,text,uuid,integer,text) to anon;
