-- Estimates are now a combined price proposal, detailed work plan, notes, and
-- project media. The AI-generated plan is stored as ordered JSON so a
-- contractor can edit section titles and bullet points without coupling the
-- document structure to the pricing categories.

create or replace function public.is_valid_estimate_work_plan(plan jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  section_value jsonb;
  step_value jsonb;
begin
  if plan is null or jsonb_typeof(plan) <> 'array' or jsonb_array_length(plan) > 24 then
    return false;
  end if;

  for section_value in select value from jsonb_array_elements(plan)
  loop
    if jsonb_typeof(section_value) <> 'object'
      or coalesce(section_value ->> 'id', '') !~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      or nullif(btrim(section_value ->> 'title'), '') is null
      or length(section_value ->> 'title') > 160
      or jsonb_typeof(section_value -> 'steps') <> 'array'
      or jsonb_array_length(section_value -> 'steps') < 1
      or jsonb_array_length(section_value -> 'steps') > 20 then
      return false;
    end if;

    for step_value in select value from jsonb_array_elements(section_value -> 'steps')
    loop
      if jsonb_typeof(step_value) <> 'string'
        or nullif(btrim(step_value #>> '{}'), '') is null
        or length(step_value #>> '{}') > 1000 then
        return false;
      end if;
    end loop;
  end loop;

  return true;
end;
$$;

revoke all on function public.is_valid_estimate_work_plan(jsonb)
  from public, anon, authenticated;
grant execute on function public.is_valid_estimate_work_plan(jsonb)
  to authenticated, service_role;

alter table public.estimates
  add column if not exists work_plan jsonb not null default '[]'::jsonb,
  add column if not exists notes text not null default '';

alter table public.estimates
  drop constraint if exists estimates_work_plan_valid,
  add constraint estimates_work_plan_valid
    check (public.is_valid_estimate_work_plan(work_plan)),
  drop constraint if exists estimates_notes_length,
  add constraint estimates_notes_length
    check (char_length(notes) <= 12000);

create table public.estimate_media (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  estimate_id uuid not null references public.estimates(id) on delete cascade,
  kind text not null check (kind in ('photo', 'floorplan', 'render')),
  display_name text not null check (char_length(display_name) between 1 and 240),
  storage_path text,
  render_id uuid references public.project_renders(id) on delete cascade,
  mime_type text,
  sort_order integer not null default 0 check (sort_order >= 0),
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint estimate_media_source_check check (
    (kind in ('photo', 'floorplan') and storage_path is not null and render_id is null)
    or (kind = 'render' and storage_path is null and render_id is not null)
  )
);

create index estimate_media_estimate_order_idx
  on public.estimate_media(estimate_id, sort_order, created_at);
create index estimate_media_project_idx
  on public.estimate_media(project_id);
create index estimate_media_render_idx
  on public.estimate_media(render_id)
  where render_id is not null;

create or replace function public.sync_estimate_media_parent_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent_record record;
begin
  select estimate.organization_id, estimate.project_id
  into parent_record
  from public.estimates estimate
  where estimate.id = new.estimate_id;

  if parent_record.organization_id is null or parent_record.project_id is null then
    raise exception using errcode = '23503', message = 'Estimate media requires a project estimate';
  end if;

  new.organization_id := parent_record.organization_id;
  new.project_id := parent_record.project_id;

  if new.render_id is not null and not exists (
    select 1
    from public.project_renders render
    where render.id = new.render_id
      and render.organization_id = new.organization_id
      and render.project_id = new.project_id
  ) then
    raise exception using errcode = '23514', message = 'Estimate render must belong to the same project';
  end if;

  return new;
end;
$$;

drop trigger if exists estimate_media_sync_parent on public.estimate_media;
create trigger estimate_media_sync_parent
before insert or update of estimate_id, organization_id, project_id, render_id
on public.estimate_media
for each row execute function public.sync_estimate_media_parent_fields();

revoke all on function public.sync_estimate_media_parent_fields()
  from public, anon, authenticated, service_role;

alter table public.estimate_media enable row level security;

create policy "members can manage estimate media"
  on public.estimate_media for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

revoke all on table public.estimate_media from public, anon, authenticated;
grant select, insert, update, delete on table public.estimate_media to authenticated;
grant select, insert, update, delete on table public.estimate_media to service_role;

-- Wrap the existing validated price transaction so price rows and the work
-- plan are committed or rolled back together.
create or replace function public.create_estimate_proposal_with_items(
  p_project_id uuid,
  p_estimate jsonb,
  p_items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  created_estimate_id uuid;
  supplied_plan jsonb := coalesce(p_estimate -> 'work_plan', '[]'::jsonb);
  supplied_notes text := coalesce(p_estimate ->> 'notes', '');
begin
  if not public.is_valid_estimate_work_plan(supplied_plan) then
    raise exception using errcode = '22023', message = 'Estimate work plan is invalid';
  end if;
  if char_length(supplied_notes) > 12000 then
    raise exception using errcode = '22023', message = 'Estimate notes exceed the allowed length';
  end if;

  created_estimate_id := public.create_estimate_with_items(
    p_project_id,
    p_estimate,
    p_items
  );

  update public.estimates
  set work_plan = supplied_plan,
      notes = supplied_notes
  where id = created_estimate_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Created estimate could not be updated';
  end if;

  return created_estimate_id;
end;
$$;

revoke all on function public.create_estimate_proposal_with_items(uuid, jsonb, jsonb)
  from public, anon;
grant execute on function public.create_estimate_proposal_with_items(uuid, jsonb, jsonb)
  to authenticated;

-- Freeze the complete price-and-plan document into each public share link.
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

comment on column public.estimates.work_plan is
  'Ordered contractor-editable work phases generated with the estimate scope.';
comment on table public.estimate_media is
  'Private photos, floorplans, and project render links selected for an estimate.';
;
