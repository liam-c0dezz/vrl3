-- Project-level payment receipts used by the dashboard. A payment is kept as
-- its own record so partial payments can be added and corrected without
-- changing the immutable invoice total.

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id) on delete cascade,
  project_id uuid not null
    references public.projects(id) on delete cascade,
  invoice_id uuid
    references public.invoices(id) on delete set null,
  amount numeric(14,2) not null
    check (amount > 0 and amount <= 1000000000000),
  method text not null
    check (
      method in (
        'Cash', 'Check', 'Zelle', 'Square', 'Apple Pay', 'Venmo',
        'Credit card', 'Bank transfer', 'Other'
      )
    ),
  received_at timestamptz not null default now(),
  created_by uuid not null default auth.uid()
    references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payments_organization_id_idx
  on public.payments(organization_id);
create index if not exists payments_project_id_received_at_idx
  on public.payments(project_id, received_at desc);
create index if not exists payments_invoice_id_idx
  on public.payments(invoice_id);
create index if not exists payments_created_by_idx
  on public.payments(created_by);

create or replace function public.sync_payment_parent_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_organization_id uuid;
begin
  select project.organization_id
  into parent_organization_id
  from public.projects project
  where project.id = new.project_id;

  if parent_organization_id is null then
    raise exception 'Unknown project_id';
  end if;

  if new.invoice_id is not null and not exists (
    select 1
    from public.invoices invoice
    where invoice.id = new.invoice_id
      and invoice.project_id = new.project_id
      and invoice.organization_id = parent_organization_id
  ) then
    raise exception 'Invoice does not belong to this project';
  end if;

  new.organization_id := parent_organization_id;
  return new;
end;
$$;

revoke all on function public.sync_payment_parent_fields()
  from public, anon, authenticated;

drop trigger if exists payments_sync_parent_fields on public.payments;
create trigger payments_sync_parent_fields
  before insert or update of project_id, invoice_id, organization_id
  on public.payments
  for each row execute function public.sync_payment_parent_fields();

drop trigger if exists payments_set_updated_at on public.payments;
create trigger payments_set_updated_at
  before update on public.payments
  for each row execute function public.set_updated_at();

alter table public.payments enable row level security;

drop policy if exists "members can view payments" on public.payments;
create policy "members can view payments"
  on public.payments for select to authenticated
  using (public.is_organization_member(organization_id));

drop policy if exists "members can create payments" on public.payments;
create policy "members can create payments"
  on public.payments for insert to authenticated
  with check (
    public.is_organization_member(organization_id)
    and created_by = auth.uid()
  );

drop policy if exists "members can update payments" on public.payments;
create policy "members can update payments"
  on public.payments for update to authenticated
  using (public.is_organization_member(organization_id))
  with check (public.is_organization_member(organization_id));

grant select, insert, update on public.payments to authenticated;
revoke all on public.payments from anon;

comment on table public.payments is
  'Partial and completed payments received for project invoices.';
;
