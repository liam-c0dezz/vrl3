-- Business setup data used by the Getting Started experience. A business
-- belongs to an organization so every member sees the same estimate defaults,
-- branding, rates, and upsells while RLS keeps other organizations out.

create table public.business_profiles (
  organization_id uuid primary key
    references public.organizations(id) on delete cascade,
  business_name text not null default '',
  license_number text not null default '',
  website text not null default '',
  phone text not null default '',
  email text not null default '',
  postal_code text not null default '',
  default_markup_percent numeric(7,4) not null default 20
    check (default_markup_percent between 0 and 300),
  sales_tax_percent numeric(7,4) not null default 0
    check (sales_tax_percent between 0 and 100),
  payment_terms text not null default 'Net 30',
  quote_valid_days smallint not null default 30
    check (quote_valid_days between 1 and 365),
  payment_link text not null default '',
  logo_storage_path text,
  setup_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.business_hourly_rates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 100),
  hourly_rate numeric(12,2) not null check (hourly_rate between 0 and 100000),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index business_hourly_rates_organization_id_idx
  on public.business_hourly_rates (organization_id, sort_order);

create table public.business_upsells (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 120),
  description text not null default '',
  price numeric(14,2) not null check (price between 0 and 10000000),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index business_upsells_organization_id_idx
  on public.business_upsells (organization_id, sort_order);

create trigger business_profiles_set_updated_at
  before update on public.business_profiles
  for each row execute function public.set_updated_at();
create trigger business_hourly_rates_set_updated_at
  before update on public.business_hourly_rates
  for each row execute function public.set_updated_at();
create trigger business_upsells_set_updated_at
  before update on public.business_upsells
  for each row execute function public.set_updated_at();

alter table public.business_profiles enable row level security;
alter table public.business_hourly_rates enable row level security;
alter table public.business_upsells enable row level security;

create policy "members can manage business profiles"
  on public.business_profiles for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

create policy "members can manage business hourly rates"
  on public.business_hourly_rates for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

create policy "members can manage business upsells"
  on public.business_upsells for all to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

grant select, insert, update, delete on
  public.business_profiles,
  public.business_hourly_rates,
  public.business_upsells
to authenticated;

revoke all on
  public.business_profiles,
  public.business_hourly_rates,
  public.business_upsells
from anon;

-- Private organization branding. Object names are
-- <organization_uuid>/logo.png. Upserts need SELECT, INSERT, and UPDATE.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'business-assets',
  'business-assets',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "members can read business assets"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1]
      = (select public.current_organization_id())::text
  );

create policy "members can insert business assets"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1]
      = (select public.current_organization_id())::text
  );

create policy "members can update business assets"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1]
      = (select public.current_organization_id())::text
  )
  with check (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1]
      = (select public.current_organization_id())::text
  );

create policy "members can delete business assets"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'business-assets'
    and (storage.foldername(name))[1]
      = (select public.current_organization_id())::text
  );
;
