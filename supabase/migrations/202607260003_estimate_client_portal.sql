-- Secure public estimate links and client approval workflow.
create extension if not exists pgcrypto with schema extensions;
create table if not exists public.estimate_share_links (
  id uuid primary key default gen_random_uuid(),
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  token_hash text not null unique,
  snapshot jsonb not null,
  status text not null default 'sent'
    check (status in ('sent', 'viewed', 'approved', 'changes_requested', 'revoked')),
  expires_at timestamptz not null default (now() + interval '30 days'),
  first_viewed_at timestamptz,
  last_viewed_at timestamptz,
  approved_at timestamptz,
  approved_by text,
  change_requested_at timestamptz,
  change_request text,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists estimate_share_links_estimate_id_idx
  on public.estimate_share_links(estimate_id);
create index if not exists estimate_share_links_project_id_idx
  on public.estimate_share_links(project_id);
create index if not exists estimate_share_links_organization_id_idx
  on public.estimate_share_links(organization_id);
alter table public.estimate_share_links enable row level security;
drop policy if exists "members can view estimate share links"
  on public.estimate_share_links;
create policy "members can view estimate share links"
  on public.estimate_share_links
  for select
  to authenticated
  using (public.is_organization_member(organization_id));
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
      'total', coalesce(estimate.total, 0),
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
    'items', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', item.id,
          'category', coalesce(item.category, 'Other'),
          'name', coalesce(item.name, 'Item'),
          'description', coalesce(item.description, ''),
          'quantity', coalesce(item.quantity, 0),
          'unit', coalesce(item.unit_label, ''),
          'unit_price', coalesce(item.unit_price, 0),
          'total', coalesce(item.total, 0)
        )
        order by item.category, item.name
      )
      from public.estimate_items item
      where item.estimate_id = estimate.id
    ), '[]'::jsonb)
  )
  from public.estimates estimate
  join public.projects project on project.id = estimate.project_id
  join public.organizations organization on organization.id = estimate.organization_id
  left join public.clients client on client.id = project.client_id
  where estimate.id = p_estimate_id;
$$;
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

  update public.estimate_share_links
  set status = 'revoked', updated_at = now()
  where estimate_id = p_estimate_id
    and status in ('sent', 'viewed', 'changes_requested');

  insert into public.estimate_share_links (
    estimate_id,
    project_id,
    organization_id,
    token_hash,
    snapshot,
    created_by
  )
  values (
    p_estimate_id,
    estimate_record.project_id,
    estimate_record.organization_id,
    encode(extensions.digest(raw_token, 'sha256'), 'hex'),
    snapshot_value,
    auth.uid()
  )
  returning id into share_id;

  update public.estimates
  set status = 'Sent'
  where id = p_estimate_id;

  update public.projects
  set status = 'Sent', updated_at = now()
  where id = estimate_record.project_id;

  return jsonb_build_object(
    'share_id', share_id,
    'token', raw_token,
    'expires_at', now() + interval '30 days'
  );
end;
$$;
create or replace function public.get_public_estimate(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  share_record public.estimate_share_links%rowtype;
begin
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
    status = case when status = 'sent' then 'viewed' else status end,
    first_viewed_at = coalesce(first_viewed_at, now()),
    last_viewed_at = now(),
    updated_at = now()
  where id = share_record.id;

  if share_record.status = 'sent' then
    update public.estimates
    set status = 'Viewed'
    where id = share_record.estimate_id
      and status = 'Sent';
  end if;

  return share_record.snapshot || jsonb_build_object(
    'share', jsonb_build_object(
      'status', case when share_record.status = 'sent' then 'viewed' else share_record.status end,
      'expires_at', share_record.expires_at,
      'approved_at', share_record.approved_at,
      'approved_by', share_record.approved_by,
      'change_request', share_record.change_request
    )
  );
end;
$$;
create or replace function public.approve_public_estimate(
  p_token text,
  p_approved_by text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  share_record public.estimate_share_links%rowtype;
  signer_name text := nullif(trim(p_approved_by), '');
begin
  if signer_name is null then
    raise exception 'Your name is required';
  end if;

  select *
  into share_record
  from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status in ('sent', 'viewed')
    and expires_at > now()
  for update;

  if share_record.id is null then
    raise exception 'This estimate link is no longer available';
  end if;

  update public.estimate_share_links
  set
    status = 'approved',
    approved_at = now(),
    approved_by = signer_name,
    updated_at = now()
  where id = share_record.id;

  update public.estimates
  set status = 'Approved'
  where id = share_record.estimate_id;

  update public.projects
  set status = 'Approved', updated_at = now()
  where id = share_record.project_id;

  return jsonb_build_object(
    'status', 'approved',
    'approved_by', signer_name,
    'approved_at', now()
  );
end;
$$;
create or replace function public.request_public_estimate_change(
  p_token text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  share_record public.estimate_share_links%rowtype;
  request_message text := nullif(trim(p_message), '');
begin
  if request_message is null then
    raise exception 'Please describe the requested change';
  end if;

  select *
  into share_record
  from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status in ('sent', 'viewed')
    and expires_at > now()
  for update;

  if share_record.id is null then
    raise exception 'This estimate link is no longer available';
  end if;

  update public.estimate_share_links
  set
    status = 'changes_requested',
    change_requested_at = now(),
    change_request = request_message,
    updated_at = now()
  where id = share_record.id;

  update public.estimates
  set status = 'Changes Requested'
  where id = share_record.estimate_id;

  update public.projects
  set status = 'Draft', updated_at = now()
  where id = share_record.project_id;

  return jsonb_build_object(
    'status', 'changes_requested',
    'message', request_message
  );
end;
$$;
revoke all on function public.build_estimate_portal_snapshot(uuid) from public;
revoke all on function public.create_estimate_share_link(uuid) from public;
revoke all on function public.get_public_estimate(text) from public;
revoke all on function public.approve_public_estimate(text, text) from public;
revoke all on function public.request_public_estimate_change(text, text) from public;
grant execute on function public.create_estimate_share_link(uuid) to authenticated;
grant execute on function public.get_public_estimate(text) to anon, authenticated;
grant execute on function public.approve_public_estimate(text, text) to anon, authenticated;
grant execute on function public.request_public_estimate_change(text, text) to anon, authenticated;
