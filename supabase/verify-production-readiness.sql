-- Open Play Book production readiness verification (READ ONLY).
-- Run manually in the BSB Operations Supabase SQL Editor after taking a backup.
-- This script performs catalog/data reads only and returns PASS/FAIL rows.

with
required_tables(name) as (values
  ('organizations'),('employees'),('authorized_devices'),('employee_terminal_sessions'),
  ('device_enrollment_codes'),('business_nights'),('open_play_settings'),
  ('open_play_leagues'),('open_play_sessions'),('open_play_lane_assignments'),
  ('open_play_lane_conditions'),('open_play_activity')
),
required_columns(table_name,column_name) as (values
  ('organizations','slug'),('employees','role'),('employees','active'),
  ('authorized_devices','token_hash'),('authorized_devices','active'),
  ('employee_terminal_sessions','expires_at'),('employee_terminal_sessions','revoked_at'),
  ('device_enrollment_codes','code_hash'),('device_enrollment_codes','expires_at'),('device_enrollment_codes','used_at'),
  ('business_nights','status'),('open_play_settings','settings'),('open_play_leagues','sort_order'),
  ('open_play_sessions','status'),('open_play_sessions','version'),('open_play_sessions','checked_out_at'),
  ('open_play_sessions','voided_at'),('open_play_sessions','void_category'),('open_play_sessions','pre_void_status'),
  ('open_play_sessions','reinstated_at'),('open_play_lane_assignments','billable_started_at'),
  ('open_play_lane_assignments','billing_group_id'),('open_play_activity','performed_by_name'),
  ('open_play_activity','device_id'),('open_play_activity','details')
),
browser_rpcs(signature) as (values
  ('bsb_list_active_employees(text)'),('bsb_verify_employee_pin(text,uuid,text)'),
  ('bsb_owner_list_employees(text)'),('bsb_owner_save_employee(text,uuid,text,bsb_employee_role,boolean,text)'),
  ('bsb_owner_list_devices(text)'),('bsb_owner_create_device_enrollment(text,text)'),
  ('bsb_redeem_device_enrollment(text)'),('bsb_owner_set_device_active(text,uuid,boolean)'),
  ('bsb_get_open_play_state(text,text)'),('bsb_open_night(text,text)'),
  ('bsb_start_session(text,text,bsb_open_play_session_type,jsonb,integer[],integer[])'),
  ('bsb_edit_session(text,text,uuid,integer,jsonb,timestamp with time zone)'),
  ('bsb_add_lane(text,text,uuid,integer,boolean)'),('bsb_move_lane(text,text,uuid,integer,integer,boolean)'),
  ('bsb_release_lane(text,text,uuid,integer)'),('bsb_start_billing_now(text,text,uuid,integer)'),
  ('bsb_end_session(text,text,uuid,integer,jsonb)'),('bsb_checkout_session(text,text,uuid,integer,jsonb)'),
  ('bsb_reopen_session(text,text,uuid,integer,jsonb)'),('bsb_void_session(text,text,uuid,integer,text,text)'),
  ('bsb_reinstate_session(text,text,uuid,integer,text)'),
  ('bsb_set_lane_condition(text,text,integer,bsb_open_play_lane_condition,text)'),
  ('bsb_close_night(text,text)'),('bsb_save_open_play_settings(text,text,jsonb)'),
  ('bsb_save_open_play_league(text,text,uuid,text,boolean,integer)')
),
internal_helpers(signature) as (values
  ('bsb_device(text)'),('bsb_session_employee(text)'),('bsb_open_play_actor(text,text)'),
  ('bsb_open_play_require_actor(text,text)'),('bsb_open_play_assert_money(jsonb,text,boolean)'),
  ('bsb_open_play_validate_data(bsb_open_play_session_type,jsonb)'),
  ('bsb_open_play_log(uuid,uuid,uuid,text,integer[],text,uuid)'),
  ('bsb_open_play_log_actor(bsb_open_play_actor_context,uuid,uuid,text,integer[],text,jsonb)')
),
enum_expectations(type_name, expected) as (values
  ('bsb_employee_role','EMPLOYEE,MANAGER,OWNER'),
  ('bsb_open_play_night_status','CLOSED,OPEN'),
  ('bsb_open_play_session_type','OPEN_BOWLING,PARTY,PRE_POST'),
  ('bsb_open_play_session_status','ACTIVE,AWAITING_CLOSE,COMPLETED,VOIDED'),
  ('bsb_open_play_lane_condition','AVAILABLE,DOWN,WATCH'),
  ('bsb_open_play_lane_end_reason','MOVED,RELEASED,SESSION_ENDED')
),
checks as (
  select '01 required tables' check_name,
    not exists(select 1 from required_tables r where to_regclass('public.'||r.name) is null) ok,
    coalesce((select string_agg(name,', ') from required_tables r where to_regclass('public.'||r.name) is null),'all present') detail
  union all
  select '02 required columns',
    not exists(select 1 from required_columns r left join information_schema.columns c on c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name where c.column_name is null),
    coalesce((select string_agg(r.table_name||'.'||r.column_name,', ') from required_columns r left join information_schema.columns c on c.table_schema='public' and c.table_name=r.table_name and c.column_name=r.column_name where c.column_name is null),'all present')
  union all
  select '03 enum values',
    not exists(select 1 from enum_expectations x left join (select t.typname, string_agg(e.enumlabel,',' order by e.enumlabel) actual from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' group by t.typname) a on a.typname=x.type_name where a.actual is distinct from x.expected),
    coalesce((select string_agg(x.type_name||' expected ['||x.expected||'] got ['||coalesce(a.actual,'missing')||']','; ') from enum_expectations x left join (select t.typname, string_agg(e.enumlabel,',' order by e.enumlabel) actual from pg_type t join pg_enum e on e.enumtypid=t.oid join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' group by t.typname) a on a.typname=x.type_name where a.actual is distinct from x.expected),'all match')
  union all
  select '04 RLS enabled',
    not exists(select 1 from required_tables r left join pg_class c on c.oid=to_regclass('public.'||r.name) where not coalesce(c.relrowsecurity,false)),
    coalesce((select string_agg(r.name,', ') from required_tables r left join pg_class c on c.oid=to_regclass('public.'||r.name) where not coalesce(c.relrowsecurity,false)),'enabled on all required tables')
  union all
  select '05 direct browser table writes/reads restricted',
    not exists(select 1 from required_tables r where coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'DELETE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'DELETE'),false)),
    coalesce((select string_agg(r.name,', ') from required_tables r where coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('anon',to_regclass('public.'||r.name),'DELETE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'SELECT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'INSERT'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'UPDATE'),false) or coalesce(has_table_privilege('authenticated',to_regclass('public.'||r.name),'DELETE'),false)),'no direct browser table privileges')
  union all
  select '06 browser RPCs exist and anon can execute',
    not exists(select 1 from browser_rpcs r where to_regprocedure('public.'||r.signature) is null or not coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),
    coalesce((select string_agg(signature,', ') from browser_rpcs r where to_regprocedure('public.'||r.signature) is null or not coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),'all callable')
  union all
  select '07 internal helpers not browser callable',
    not exists(select 1 from internal_helpers r where to_regprocedure('public.'||r.signature) is null or coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false) or coalesce(has_function_privilege('authenticated',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),
    coalesce((select string_agg(signature,', ') from internal_helpers r where to_regprocedure('public.'||r.signature) is null or coalesce(has_function_privilege('anon',to_regprocedure('public.'||r.signature),'EXECUTE'),false) or coalesce(has_function_privilege('authenticated',to_regprocedure('public.'||r.signature),'EXECUTE'),false)),'all present and restricted')
  union all
  select '08 Blue Springs Bowl organization', count(*)=1, count(*)||' matching organization row(s)' from public.organizations where slug='blue-springs-bowl'
  union all
  select '09 active OWNER', count(*)>=1, count(*)||' active owner(s)' from public.employees e join public.organizations o on o.id=e.organization_id where o.slug='blue-springs-bowl' and e.active and e.role='OWNER'
  union all
  select '10 active authorized device', count(*)>=1, count(*)||' active authorized device(s)' from public.authorized_devices d join public.organizations o on o.id=d.organization_id where o.slug='blue-springs-bowl' and d.active
)
select check_name, case when ok then 'PASS' else 'FAIL' end status, detail
from checks order by check_name;
