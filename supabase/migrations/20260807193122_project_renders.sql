-- Project-scoped AI remodel renders. Source and generated images live in the
-- existing private `project-files` bucket under
-- <organization>/<project>/renders/<render>/... . The storage policies already
-- validate the first two path segments against project membership.

create table public.project_renders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  original_image_path text not null,
  current_image_path text not null,
  accepted_image_path text,
  initial_prompt text not null check (char_length(initial_prompt) between 1 and 2000),
  status text not null default 'draft' check (status in ('draft', 'accepted')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  constraint accepted_render_has_image check (
    status <> 'accepted' or accepted_image_path is not null
  )
);

create table public.render_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  render_id uuid not null references public.project_renders(id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null check (char_length(content) between 1 and 2000),
  image_path text,
  created_at timestamptz not null default now()
);

alter table public.invoices
  add column render_id uuid references public.project_renders(id) on delete set null,
  add column include_render boolean not null default false,
  add constraint included_invoice_render_is_linked check (
    not include_render or render_id is not null
  );

create index project_renders_project_created_idx
  on public.project_renders(project_id, created_at desc);
create index project_renders_project_accepted_idx
  on public.project_renders(project_id, accepted_at desc)
  where status = 'accepted';
create index render_messages_render_created_idx
  on public.render_messages(render_id, created_at);
create index invoices_render_id_idx
  on public.invoices(render_id)
  where render_id is not null;

drop trigger if exists project_renders_set_updated_at on public.project_renders;
create trigger project_renders_set_updated_at
before update on public.project_renders
for each row execute function public.set_updated_at();

create or replace function public.validate_invoice_render_link()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.render_id is null then
    new.include_render := false;
    return new;
  end if;

  if not exists (
    select 1
    from public.project_renders render
    where render.id = new.render_id
      and render.project_id = new.project_id
      and render.organization_id = new.organization_id
      and render.status = 'accepted'
      and render.accepted_image_path is not null
  ) then
    raise exception using
      errcode = '23514',
      message = 'Invoice render must be an accepted render from the same project';
  end if;
  return new;
end;
$$;

drop trigger if exists invoices_validate_render_link on public.invoices;
create trigger invoices_validate_render_link
before insert or update of render_id, include_render, project_id, organization_id
on public.invoices
for each row execute function public.validate_invoice_render_link();

revoke all on function public.validate_invoice_render_link() from public, anon, authenticated;

alter table public.project_renders enable row level security;
alter table public.render_messages enable row level security;

-- Mobile clients can read render history. Mutations are deliberately kept in
-- the render-service Edge Function so paths, acceptance state, and AI request
-- accounting cannot be forged by a client.
create policy "members can read project renders"
  on public.project_renders for select to authenticated
  using (public.is_organization_member(organization_id));

create policy "members can read render messages"
  on public.render_messages for select to authenticated
  using (public.is_organization_member(organization_id));

-- New public-schema tables are no longer automatically exposed through the
-- Data API. Grant only the read access used by the iOS app explicitly.
revoke all on table public.project_renders from public, anon, authenticated;
revoke all on table public.render_messages from public, anon, authenticated;
grant select on table public.project_renders to authenticated;
grant select on table public.render_messages to authenticated;
grant select, insert, update, delete on table public.project_renders to service_role;
grant select, insert, update, delete on table public.render_messages to service_role;

comment on table public.project_renders is
  'Private project before/after renders generated through render-service.';
comment on column public.invoices.include_render is
  'Whether the linked accepted project render is included in the client invoice.';
;
