-- Only the server's service role can invoke this transaction. Existing customer
-- and cost tables are preserved. The request, draft and estimate commit together.
create or replace function public.residential_estimator_save_draft(
  p_user_id uuid, p_draft_id uuid, p_revision integer, p_request_id uuid,
  p_estimate jsonb, p_items jsonb, p_response jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  draft public.smart_service_drafts%rowtype;
  new_estimate_id uuid;
  response jsonb;
begin
  if current_user <> 'service_role' then
    raise exception using errcode = '42501', message = 'Server role required';
  end if;
  select * into draft from public.smart_service_drafts
    where id = p_draft_id and user_id = p_user_id for update;
  if not found then
    raise exception using errcode = '42501', message = 'Draft access denied';
  end if;
  if not exists (select 1 from public.organization_members m
    where m.organization_id = draft.organization_id and m.user_id = p_user_id)
    or not exists (select 1 from public.projects p
      where p.id = draft.project_id and p.organization_id = draft.organization_id) then
    raise exception using errcode = '42501', message = 'Project access denied';
  end if;
  if not public.has_current_ai_consent(p_user_id, '2026-07-31')
    or not exists (select 1 from public.ai_service_config where is_enabled) then
    raise exception using errcode = '42501', message = 'AI consent or service availability changed';
  end if;
  perform 1 from public.ai_requests where user_id = p_user_id
    and request_id = p_request_id and status = 'processing' for update;
  if not found then
    raise exception using errcode = '40001', message = 'No active request reservation';
  end if;
  if draft.status = 'completed' and draft.plan ? 'response' then
    response := draft.plan -> 'response';
    if not public.complete_ai_request(p_user_id, p_request_id, response) then
      raise exception using errcode = '40001', message = 'Request completion failed';
    end if;
    return response;
  end if;
  if draft.revision <> p_revision or draft.status <> 'ready'
    or draft.plan ->> 'engine' is distinct from 'residential-estimator-2026-09-25'
    or coalesce((draft.plan #>> '{report,unpricedLineCount}')::integer, -1) <> 0
    or coalesce((draft.plan #>> '{report,pricedLineCount}')::integer, 0) <= 0
    or jsonb_array_length(coalesce(draft.plan #> '{report,conflicts}', '[]'::jsonb)) <> 0 then
    raise exception using errcode = '40001', message = 'Draft not ready or revision changed';
  end if;
  -- The service already verified this user via Auth. Scope the existing save RPC
  -- to that verified identity; neither clients nor user_metadata can choose it.
  perform set_config('request.jwt.claim.sub', p_user_id::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub',p_user_id,'role','service_role')::text, true);
  new_estimate_id := public.create_estimate_proposal_with_items(draft.project_id, p_estimate, p_items);
  response := p_response || jsonb_build_object('estimate_id', new_estimate_id);
  update public.smart_service_drafts set status = 'completed', estimate_id = new_estimate_id,
    plan = plan || jsonb_build_object('response', response), updated_at = now()
    where id = p_draft_id and user_id = p_user_id;
  if not public.complete_ai_request(p_user_id, p_request_id, response) then
    raise exception using errcode = '40001', message = 'Request completion failed';
  end if;
  return response;
end;
$function$;
revoke all on function public.residential_estimator_save_draft(uuid,uuid,integer,uuid,jsonb,jsonb,jsonb) from public, anon, authenticated;
grant execute on function public.residential_estimator_save_draft(uuid,uuid,integer,uuid,jsonb,jsonb,jsonb) to service_role;
