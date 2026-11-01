-- Preparation is not delivery. Preserve existing public approval capabilities.
alter table public.estimates add column if not exists appearance jsonb;
alter table public.estimates add constraint estimates_appearance_valid check (
  appearance is null or (
    jsonb_typeof(appearance) = 'object'
    and coalesce(appearance->>'accent', 'blue') in ('blue', 'black', 'gray', 'green')
    and char_length(coalesce(appearance->>'businessName', '')) <= 120
  )
);
alter table public.estimate_share_links add column if not exists sent_at timestamptz;
alter table public.estimate_share_links drop constraint estimate_share_links_status_check;
alter table public.estimate_share_links add constraint estimate_share_links_status_check
  check (status in ('prepared', 'sent', 'viewed', 'approved', 'changes_requested', 'revoked'));

create or replace function public.build_estimate_portal_snapshot(p_estimate_id uuid)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'estimate', jsonb_build_object(
      'id', estimate.id,
      'number', coalesce(estimate.estimate_number, 'EST-' || upper(left(estimate.id::text, 8))),
      'title', coalesce(estimate.title, project.title, 'Estimate'),
      'status', coalesce(estimate.status, 'Draft'),
      'issued_at', estimate.created_at,
      'subtotal', coalesce(estimate.subtotal, 0),
      'markup_percent', coalesce(estimate.markup_pct, 0),
      'markup_amount', coalesce(estimate.markup_amount, 0),
      'contingency_amount', coalesce(estimate.contingency_amount, 0),
      'total', coalesce(estimate.total, 0),
      'work_plan', coalesce(estimate.work_plan, '[]'::jsonb),
      'notes', coalesce(estimate.notes, ''),
      'appearance', coalesce(estimate.appearance, '{}'::jsonb),
      'exclusions', coalesce(to_jsonb(estimate.exclusions), '[]'::jsonb),
      'payment_terms', coalesce(estimate.payment_terms, '')
    ),
    'project', jsonb_build_object(
      'id', project.id,
      'number', project.project_number,
      'title', project.title,
      'address', coalesce(project.address, '')
    ),
    'client', jsonb_build_object(
      'name', coalesce(client.name, 'Client'),
      'company', coalesce(client.company, '')
    ),
    'business', jsonb_build_object(
      'name', organization.name
    ),
    'media', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', media.id,
          'kind', media.kind,
          'display_name', media.display_name
        )
        order by media.sort_order, media.created_at
      )
      from public.estimate_media media
      where media.estimate_id = estimate.id
    ), '[]'::jsonb)
  )
  from public.estimates estimate
  join public.projects project on project.id = estimate.project_id
  join public.organizations organization on organization.id = estimate.organization_id
  left join public.clients client on client.id = project.client_id
  where estimate.id = p_estimate_id;
$$;

revoke all on function public.build_estimate_portal_snapshot(uuid)
  from public, anon, authenticated;


create or replace function public.create_estimate_share_link(p_estimate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  estimate_record record;
  raw_token text;
  snapshot_value jsonb;
  share_id uuid;
begin
  select estimate.id, estimate.project_id, estimate.organization_id
  into estimate_record
  from public.estimates estimate
  where estimate.id = p_estimate_id
    and public.is_organization_member(estimate.organization_id);

  if estimate_record.id is null then
    raise exception 'Estimate not found';
  end if;

  snapshot_value := public.build_estimate_portal_snapshot(p_estimate_id);
  if snapshot_value is null then
    raise exception 'Estimate is missing its project';
  end if;

  raw_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.estimate_share_links (
    estimate_id,
    project_id,
    organization_id,
    token_hash,
    snapshot,
    status,
    created_by
  )
  values (
    p_estimate_id,
    estimate_record.project_id,
    estimate_record.organization_id,
    encode(extensions.digest(raw_token, 'sha256'), 'hex'),
    snapshot_value,
    'prepared',
    auth.uid()
  )
  returning id into share_id;

  return jsonb_build_object(
    'share_id', share_id,
    'token', raw_token,
    'expires_at', now() + interval '30 days'
  );
end;
$$;

create or replace function public.confirm_estimate_share_sent(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
set statement_timeout = '5s'
as $$
declare
  link public.estimate_share_links%rowtype;
begin
  if auth.uid() is null or p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid send confirmation';
  end if;
  select * into link from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and public.is_organization_member(organization_id)
    and status <> 'revoked' and expires_at > now();
  if link.id is null then raise exception 'Estimate link unavailable'; end if;
  -- Serialize confirmations for the same estimate, preserving approvals and views.
  perform id from public.estimates where id = link.estimate_id for update;
  select * into link from public.estimate_share_links where id = link.id for update;
  if link.status = 'revoked' then raise exception 'Estimate link unavailable'; end if;
  if link.sent_at is not null then return; end if;
  update public.estimate_share_links
    set status = case when status = 'prepared' then 'sent' else status end, sent_at = now(), updated_at = now()
    where id = link.id;
  -- Do not invalidate a previously delivered link when a replacement is only prepared.
  update public.estimate_share_links set status = 'revoked', updated_at = now()
    where estimate_id = link.estimate_id and id <> link.id
      and status in ('sent', 'viewed', 'changes_requested');
  update public.estimates set status = 'Sent' where id = link.estimate_id
    and lower(coalesce(status, 'draft')) not in ('approved', 'accepted', 'won', 'viewed');
  update public.projects set status = 'Sent', updated_at = now() where id = link.project_id
    and lower(coalesce(status, 'draft')) not in ('approved', 'accepted', 'won');
end;
$$;
revoke all on function public.confirm_estimate_share_sent(text) from public, anon;
grant execute on function public.confirm_estimate_share_sent(text) to authenticated;

create or replace function public.get_public_estimate(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '5s'
as $$
declare
  share_record public.estimate_share_links%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select *
  into share_record
  from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status <> 'revoked'
    and expires_at > now();

  if share_record.id is null then
    return null;
  end if;

  update public.estimate_share_links
  set
    status = case when status in ('sent', 'prepared') then 'viewed' else status end,
    first_viewed_at = coalesce(first_viewed_at, now()),
    last_viewed_at = now(),
    updated_at = now()
  where id = share_record.id;

  if share_record.status in ('sent', 'prepared') then
    update public.estimates
    set status = 'Viewed'
    where id = share_record.estimate_id
      and status = 'Sent';
  end if;

  return share_record.snapshot || jsonb_build_object(
    'share', jsonb_build_object(
      'status', case when share_record.status in ('sent', 'prepared') then 'viewed' else share_record.status end,
      'expires_at', share_record.expires_at,
      'approved_at', share_record.approved_at,
      'approved_by', share_record.approved_by,
      'change_request', share_record.change_request
    )
  );
end;
$$;
