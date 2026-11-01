-- Serialize payment writes per project, prevent overpayment, and keep payment
-- ownership/audit fields immutable when a receipt is corrected.

create or replace function public.sync_payment_parent_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  parent_organization_id uuid;
  project_invoice_total numeric;
  other_payment_total numeric;
begin
  if tg_op = 'UPDATE' then
    new.id := old.id;
    new.organization_id := old.organization_id;
    new.project_id := old.project_id;
    new.invoice_id := old.invoice_id;
    new.created_by := old.created_by;
    new.created_at := old.created_at;
  end if;

  select project.organization_id
  into parent_organization_id
  from public.projects project
  where project.id = new.project_id
  for update;

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

  select coalesce(sum(invoice.total), 0)
  into project_invoice_total
  from public.invoices invoice
  where invoice.project_id = new.project_id;

  select coalesce(sum(payment.amount), 0)
  into other_payment_total
  from public.payments payment
  where payment.project_id = new.project_id
    and payment.id <> new.id;

  if project_invoice_total <= 0 then
    raise exception using
      errcode = '22023',
      message = 'A payment requires an invoice balance';
  end if;

  if other_payment_total + new.amount > project_invoice_total + 0.005 then
    raise exception using
      errcode = '22023',
      message = 'Payment exceeds the remaining invoice balance';
  end if;

  new.organization_id := parent_organization_id;
  return new;
end;
$$;

revoke all on function public.sync_payment_parent_fields()
  from public, anon, authenticated;
;
