-- Slice 5 follow-up: expose persisted lifecycle milestones to the shared UI.
-- This changes only the existing shared-state read contract; it does not alter sessions.

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
    'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'type',type,'status',status,'startedAt',started_at,'endedAt',ended_at,'checkedOutAt',checked_out_at,'reopenedAt',reopened_at,'createdAt',created_at,'updatedAt',updated_at,'data',data,'version',version,'voidedAt',voided_at,'voidedBy',voided_by,'voidedByName',voided_by_name,'voidCategory',void_category,'voidNote',void_note,'preVoidStatus',pre_void_status,'reinstatedAt',reinstated_at,'reinstatedBy',reinstated_by,'reinstatedByName',reinstated_by_name,'reinstatementNote',reinstatement_note)) from public.open_play_sessions where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'laneAssignments',coalesce((select jsonb_agg(jsonb_build_object('id',id,'sessionId',session_id,'laneNumber',lane_number,'startedAt',started_at,'billingStartedAt',billing_started_at,'billingGroupId',billing_group_id,'billableStartedAt',billable_started_at,'endedAt',ended_at,'endReason',end_reason,'downOverrideConfirmed',down_override_confirmed)) from public.open_play_lane_assignments where night_id=coalesce(v_open,v_previous)),'[]'::jsonb),
    'activity',coalesce((select jsonb_agg(jsonb_build_object('id',id,'nightId',night_id,'occurredAt',occurred_at,'type',type,'sessionId',session_id,'laneNumbers',lane_numbers,'summary',summary,'employeeId',performed_by,'employeeName',performed_by_name,'deviceId',device_id,'details',details) order by occurred_at desc) from (select * from public.open_play_activity where night_id=v_activity_night order by occurred_at desc limit 200) a),'[]'::jsonb)
  );
end $$;

grant execute on function public.bsb_get_open_play_state(text,text) to anon;
