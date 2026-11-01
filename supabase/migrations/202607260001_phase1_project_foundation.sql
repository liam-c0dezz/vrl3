-- Phase 1: one company-owned project record connects clients, properties,
-- estimates, invoices, and documents.
--
-- The existing public.jobs table remains the plumbing price-book catalog.
-- Customer jobs are represented by public.projects.

create extension if not exists pgcrypto;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_user_id)
);

create table if not exists public.organization_members (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create index if not exists organization_members_user_id_idx
  on public.organization_members(user_id);

create or replace function public.is_organization_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members membership
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_organization_admin(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members membership
    where membership.organization_id = target_organization_id
      and membership.user_id = (select auth.uid())
      and membership.role in ('owner', 'admin')
  );
$$;

create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select membership.organization_id
  from public.organization_members membership
  where membership.user_id = (select auth.uid())
  order by membership.created_at
  limit 1;
$$;

revoke all on function public.is_organization_member(uuid) from public;
revoke all on function public.is_organization_admin(uuid) from public;
revoke all on function public.current_organization_id() from public;
grant execute on function public.is_organization_member(uuid) to authenticated;
grant execute on function public.is_organization_admin(uuid) to authenticated;
grant execute on function public.current_organization_id() to authenticated;

-- Give every existing account a personal company. This preserves account
-- isolation while allowing organization/team support without a later rewrite.
insert into public.organizations (name, owner_user_id)
select
  coalesce(
    nullif(user_record.raw_user_meta_data ->> 'company_name', ''),
    nullif(user_record.raw_user_meta_data ->> 'full_name', ''),
    nullif(split_part(user_record.email, '@', 1), ''),
    'My Company'
  ),
  user_record.id
from auth.users user_record
where not exists (
  select 1
  from public.organizations organization
  where organization.owner_user_id = user_record.id
);

insert into public.organization_members (organization_id, user_id, role)
select organization.id, organization.owner_user_id, 'owner'
from public.organizations organization
on conflict (organization_id, user_id) do update set role = excluded.role;

create or replace function public.handle_new_user_organization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_organization_id uuid;
begin
  insert into public.organizations (name, owner_user_id)
  values (
    coalesce(
      nullif(new.raw_user_meta_data ->> 'company_name', ''),
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(split_part(new.email, '@', 1), ''),
      'My Company'
    ),
    new.id
  )
  on conflict (owner_user_id) do update set owner_user_id = excluded.owner_user_id
  returning id into new_organization_id;

  insert into public.organization_members (organization_id, user_id, role)
  values (new_organization_id, new.id, 'owner')
  on conflict (organization_id, user_id) do update set role = excluded.role;

  return new;
end;
$$;

drop trigger if exists create_organization_after_signup on auth.users;
create trigger create_organization_after_signup
  after insert on auth.users
  for each row execute function public.handle_new_user_organization();

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null default public.current_organization_id()
    references public.organizations(id) on delete cascade,
  name text not null,
  company text not null default '',
  email text not null default '',
  phone text not null default '',
  address text not null default '',
  referral_source text not null default '',
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists clients_organization_id_idx
  on public.clients(organization_id);
create index if not exists clients_email_idx
  on public.clients(organization_id, lower(email));

create table if not exists public.properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null default public.current_organization_id()
    references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  label text not null default '',
  address_line1 text not null,
  address_line2 text not null default '',
  city text not null default '',
  state text not null default '',
  postal_code text not null default '',
  notes text not null default '',
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists properties_organization_id_idx
  on public.properties(organization_id);
create index if not exists properties_client_id_idx
  on public.properties(client_id);

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null default public.current_organization_id()
    references public.organizations(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  property_id uuid references public.properties(id) on delete set null,
  project_number text not null,
  title text not null,
  status text not null default 'Lead',
  price numeric(14,2) not null default 0,
  address text,
  assignee_user_id uuid references auth.users(id) on delete set null,
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_number)
);

create index if not exists projects_organization_id_idx
  on public.projects(organization_id);
create index if not exists projects_client_id_idx
  on public.projects(client_id);
create index if not exists projects_property_id_idx
  on public.projects(property_id);
create index if not exists projects_status_idx
  on public.projects(organization_id, status);

-- Connect the existing estimate tables to the canonical customer project.
alter table public.estimates
  add column if not exists organization_id uuid references public.organizations(id) on delete cascade,
  add column if not exists estimate_number text,
  add column if not exists status text not null default 'Draft',
  alter column user_id set default auth.uid();

alter table public.estimate_items
  add column if not exists organization_id uuid references public.organizations(id) on delete cascade,
  alter column user_id set default auth.uid();

update public.estimates estimate
set organization_id = membership.organization_id
from public.organization_members membership
where estimate.organization_id is null
  and estimate.user_id = membership.user_id;

update public.estimate_items item
set
  organization_id = estimate.organization_id,
  project_id = estimate.project_id,
  user_id = coalesce(item.user_id, estimate.user_id)
from public.estimates estimate
where item.estimate_id = estimate.id
  and (
    item.organization_id is distinct from estimate.organization_id
    or item.project_id is distinct from estimate.project_id
    or item.user_id is null
  );

create index if not exists estimates_organization_id_idx
  on public.estimates(organization_id);
create index if not exists estimates_project_id_idx
  on public.estimates(project_id);
create index if not exists estimate_items_organization_id_idx
  on public.estimate_items(organization_id);
create index if not exists estimate_items_project_id_idx
  on public.estimate_items(project_id);

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'estimates_project_id_fkey'
      and conrelid = 'public.estimates'::regclass
  ) then
    alter table public.estimates
      add constraint estimates_project_id_fkey
      foreign key (project_id) references public.projects(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'estimate_items_project_id_fkey'
      and conrelid = 'public.estimate_items'::regclass
  ) then
    alter table public.estimate_items
      add constraint estimate_items_project_id_fkey
      foreign key (project_id) references public.projects(id) on delete cascade;
  end if;
end;
$$;

create or replace function public.sync_estimate_parent_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_organization_id uuid;
begin
  if new.project_id is not null then
    select project.organization_id
    into parent_organization_id
    from public.projects project
    where project.id = new.project_id;

    if parent_organization_id is null then
      raise exception 'Unknown project_id';
    end if;
    new.organization_id := parent_organization_id;
  elsif new.organization_id is null and new.user_id is not null then
    select membership.organization_id
    into new.organization_id
    from public.organization_members membership
    where membership.user_id = new.user_id
    order by membership.created_at
    limit 1;
  end if;

  return new;
end;
$$;

drop trigger if exists sync_estimate_parent_fields_trigger on public.estimates;
create trigger sync_estimate_parent_fields_trigger
  before insert or update of project_id, organization_id, user_id
  on public.estimates
  for each row execute function public.sync_estimate_parent_fields();

create or replace function public.sync_estimate_item_parent_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select estimate.organization_id, estimate.project_id, estimate.user_id
  into new.organization_id, new.project_id, new.user_id
  from public.estimates estimate
  where estimate.id = new.estimate_id;

  if new.organization_id is null then
    raise exception 'Estimate must belong to an organization';
  end if;

  return new;
end;
$$;

drop trigger if exists sync_estimate_item_parent_fields_trigger on public.estimate_items;
create trigger sync_estimate_item_parent_fields_trigger
  before insert or update of estimate_id
  on public.estimate_items
  for each row execute function public.sync_estimate_item_parent_fields();

create table if not exists public.invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null default public.current_organization_id()
    references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  client_id uuid references public.clients(id) on delete set null,
  estimate_id uuid references public.estimates(id) on delete set null,
  invoice_number text not null,
  title text not null default '',
  description text not null default '',
  status text not null default 'Draft',
  due_date text not null default 'On completion',
  subtotal numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  tax_percent numeric(7,4) not null default 0,
  tax_amount numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  cover_transaction_fees boolean not null default false,
  terms_and_conditions text not null default '',
  created_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, invoice_number)
);

create index if not exists invoices_organization_id_idx
  on public.invoices(organization_id);
create index if not exists invoices_project_id_idx
  on public.invoices(project_id);
create index if not exists invoices_client_id_idx
  on public.invoices(client_id);
create index if not exists invoices_status_idx
  on public.invoices(organization_id, status);

create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null default public.current_organization_id()
    references public.organizations(id) on delete cascade,
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  title text not null,
  quantity numeric(12,3) not null default 1,
  unit_price numeric(14,2) not null default 0,
  unit text not null default 'EA',
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists invoice_items_invoice_id_idx
  on public.invoice_items(invoice_id);
create index if not exists invoice_items_organization_id_idx
  on public.invoice_items(organization_id);

create or replace function public.sync_invoice_child_organization()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  select invoice.organization_id
  into new.organization_id
  from public.invoices invoice
  where invoice.id = new.invoice_id;

  if new.organization_id is null then
    raise exception 'Unknown invoice_id';
  end if;

  return new;
end;
$$;

drop trigger if exists sync_invoice_item_organization_trigger on public.invoice_items;
create trigger sync_invoice_item_organization_trigger
  before insert or update of invoice_id
  on public.invoice_items
  for each row execute function public.sync_invoice_child_organization();

create table if not exists public.project_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null default public.current_organization_id()
    references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projects(id) on delete cascade,
  invoice_id uuid references public.invoices(id) on delete set null,
  name text not null,
  storage_path text not null unique,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  category text not null default 'document',
  uploaded_by uuid not null default auth.uid() references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists project_documents_project_id_idx
  on public.project_documents(project_id);
create index if not exists project_documents_organization_id_idx
  on public.project_documents(organization_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists organizations_set_updated_at on public.organizations;
create trigger organizations_set_updated_at before update on public.organizations
  for each row execute function public.set_updated_at();
drop trigger if exists clients_set_updated_at on public.clients;
create trigger clients_set_updated_at before update on public.clients
  for each row execute function public.set_updated_at();
drop trigger if exists properties_set_updated_at on public.properties;
create trigger properties_set_updated_at before update on public.properties
  for each row execute function public.set_updated_at();
drop trigger if exists projects_set_updated_at on public.projects;
create trigger projects_set_updated_at before update on public.projects
  for each row execute function public.set_updated_at();
drop trigger if exists invoices_set_updated_at on public.invoices;
create trigger invoices_set_updated_at before update on public.invoices
  for each row execute function public.set_updated_at();

-- RLS: every company-owned record is available only to organization members.
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.clients enable row level security;
alter table public.properties enable row level security;
alter table public.projects enable row level security;
alter table public.estimates enable row level security;
alter table public.estimate_items enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_items enable row level security;
alter table public.project_documents enable row level security;

drop policy if exists "members can view organizations" on public.organizations;
create policy "members can view organizations"
  on public.organizations for select to authenticated
  using (public.is_organization_member(id));

drop policy if exists "admins can update organizations" on public.organizations;
create policy "admins can update organizations"
  on public.organizations for update to authenticated
  using (public.is_organization_admin(id))
  with check (public.is_organization_admin(id));

drop policy if exists "members can view memberships" on public.organization_members;
create policy "members can view memberships"
  on public.organization_members for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists "admins can manage memberships" on public.organization_members;
create policy "admins can manage memberships"
  on public.organization_members for all to authenticated
  using (public.is_organization_admin(organization_id))
  with check (public.is_organization_admin(organization_id));

drop policy if exists "members can manage clients" on public.clients;
create policy "members can manage clients"
  on public.clients for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "members can manage properties" on public.properties;
create policy "members can manage properties"
  on public.properties for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "members can manage projects" on public.projects;
create policy "members can manage projects"
  on public.projects for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "users can view own estimates" on public.estimates;
drop policy if exists "estimate owner guard" on public.estimates;
drop policy if exists "members can manage estimates" on public.estimates;
create policy "members can manage estimates"
  on public.estimates for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "users can view own estimate items" on public.estimate_items;
drop policy if exists "users can edit own estimate items" on public.estimate_items;
drop policy if exists "users can add own estimate items" on public.estimate_items;
drop policy if exists "users can delete own estimate items" on public.estimate_items;
drop policy if exists "estimate item owner guard" on public.estimate_items;
drop policy if exists "members can manage estimate items" on public.estimate_items;
create policy "members can manage estimate items"
  on public.estimate_items for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "members can manage invoices" on public.invoices;
create policy "members can manage invoices"
  on public.invoices for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "members can manage invoice items" on public.invoice_items;
create policy "members can manage invoice items"
  on public.invoice_items for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

drop policy if exists "members can manage project documents" on public.project_documents;
create policy "members can manage project documents"
  on public.project_documents for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

grant select, insert, update, delete on
  public.organizations,
  public.organization_members,
  public.clients,
  public.properties,
  public.projects,
  public.estimates,
  public.estimate_items,
  public.invoices,
  public.invoice_items,
  public.project_documents
to authenticated;

revoke all on
  public.organizations,
  public.organization_members,
  public.clients,
  public.properties,
  public.projects,
  public.estimates,
  public.estimate_items,
  public.invoices,
  public.invoice_items,
  public.project_documents
from anon;

-- Private project files. Object names are:
--   <organization_uuid>/<project_uuid>/<generated_filename>
insert into storage.buckets (id, name, public, file_size_limit)
values ('project-files', 'project-files', false, 52428800)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit;

create or replace function public.can_access_project_file(object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  path_parts text[];
  path_organization_id uuid;
  path_project_id uuid;
begin
  path_parts := storage.foldername(object_name);
  if coalesce(array_length(path_parts, 1), 0) < 2 then
    return false;
  end if;

  path_organization_id := path_parts[1]::uuid;
  path_project_id := path_parts[2]::uuid;

  return public.is_organization_member(path_organization_id)
    and exists (
      select 1
      from public.projects project
      where project.id = path_project_id
        and project.organization_id = path_organization_id
    );
exception
  when invalid_text_representation then
    return false;
end;
$$;

revoke all on function public.can_access_project_file(text) from public;
grant execute on function public.can_access_project_file(text) to authenticated;

drop policy if exists "members can read project files" on storage.objects;
create policy "members can read project files"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'project-files'
    and public.can_access_project_file(name)
  );

drop policy if exists "members can upload project files" on storage.objects;
create policy "members can upload project files"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'project-files'
    and public.can_access_project_file(name)
  );

drop policy if exists "members can update project files" on storage.objects;
create policy "members can update project files"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'project-files'
    and public.can_access_project_file(name)
  )
  with check (
    bucket_id = 'project-files'
    and public.can_access_project_file(name)
  );

drop policy if exists "members can delete project files" on storage.objects;
create policy "members can delete project files"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'project-files'
    and public.can_access_project_file(name)
  );
