-- Fix PL/pgSQL variable/column and variable/alias collisions that caused every invoice upsert to fail.

create or replace function public.upsert_invoice_with_items(
  p_invoice jsonb,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  target_invoice_id uuid;
  target_project_id uuid;
  project_organization_id uuid;
  supplied_organization_id uuid;
  client_id uuid;
  estimate_id uuid;
  item jsonb;
  item_count integer;
  calculated_subtotal numeric := 0;
  supplied_subtotal numeric;
  discount_amount numeric;
  tax_percent numeric;
  tax_amount numeric;
  supplied_total numeric;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_invoice is null or jsonb_typeof(p_invoice) <> 'object' then
    raise exception using errcode = '22023', message = 'Invoice must be a JSON object';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception using errcode = '22023', message = 'Invoice items must be a JSON array';
  end if;

  target_invoice_id := (p_invoice ->> 'id')::uuid;
  target_project_id := (p_invoice ->> 'project_id')::uuid;
  supplied_organization_id := (p_invoice ->> 'organization_id')::uuid;
  client_id := nullif(p_invoice ->> 'client_id', '')::uuid;
  estimate_id := nullif(p_invoice ->> 'estimate_id', '')::uuid;

  select project.organization_id
  into project_organization_id
  from public.projects project
  where project.id = target_project_id;

  if project_organization_id is null then
    raise exception using errcode = 'P0002', message = 'Project not found';
  end if;
  if supplied_organization_id is distinct from project_organization_id then
    raise exception using errcode = '22023', message = 'Invoice organization does not match its project';
  end if;
  if not public.is_organization_member(project_organization_id) then
    raise exception using errcode = '42501', message = 'Project access denied';
  end if;
  if exists (
    select 1
    from public.invoices invoice
    where invoice.id = target_invoice_id
      and invoice.organization_id <> project_organization_id
  ) then
    raise exception using errcode = '42501', message = 'Invoice access denied';
  end if;
  if client_id is not null and not exists (
    select 1 from public.clients client
    where client.id = client_id
      and client.organization_id = project_organization_id
  ) then
    raise exception using errcode = '22023', message = 'Invoice client does not belong to this organization';
  end if;
  if estimate_id is not null and not exists (
    select 1 from public.estimates estimate
    where estimate.id = estimate_id
      and estimate.organization_id = project_organization_id
      and estimate.project_id = target_project_id
  ) then
    raise exception using errcode = '22023', message = 'Invoice estimate does not belong to this project';
  end if;

  if nullif(btrim(p_invoice ->> 'invoice_number'), '') is null
    or length(p_invoice ->> 'invoice_number') > 100
    or length(coalesce(p_invoice ->> 'title', '')) > 500
    or length(coalesce(p_invoice ->> 'description', '')) > 10000
    or length(coalesce(p_invoice ->> 'status', '')) > 50
    or length(coalesce(p_invoice ->> 'due_date', '')) > 100
    or length(coalesce(p_invoice ->> 'terms_and_conditions', '')) > 10000 then
    raise exception using errcode = '22023', message = 'Invoice text exceeds the allowed length';
  end if;

  item_count := jsonb_array_length(p_items);
  if item_count > 500 then
    raise exception using errcode = '22023', message = 'An invoice cannot contain more than 500 items';
  end if;

  for item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(item) <> 'object' then
      raise exception using errcode = '22023', message = 'Every invoice item must be an object';
    end if;
    perform (item ->> 'id')::uuid;
    if nullif(btrim(item ->> 'title'), '') is null
      or length(item ->> 'title') > 500
      or length(coalesce(item ->> 'unit', '')) > 50 then
      raise exception using errcode = '22023', message = 'Every invoice item needs valid text';
    end if;
    if (item ->> 'quantity')::numeric <= 0
      or (item ->> 'quantity')::numeric > 1000000
      or (item ->> 'unit_price')::numeric < 0
      or (item ->> 'unit_price')::numeric > 1000000000 then
      raise exception using errcode = '22023', message = 'Invoice item amount is outside the allowed range';
    end if;

    calculated_subtotal := calculated_subtotal
      + (item ->> 'quantity')::numeric * (item ->> 'unit_price')::numeric;
  end loop;

  if (
    select count(distinct value ->> 'id')
    from jsonb_array_elements(p_items)
  ) <> item_count then
    raise exception using errcode = '22023', message = 'Invoice item IDs must be unique';
  end if;

  supplied_subtotal := (p_invoice ->> 'subtotal')::numeric;
  discount_amount := (p_invoice ->> 'discount_amount')::numeric;
  tax_percent := (p_invoice ->> 'tax_percent')::numeric;
  tax_amount := (p_invoice ->> 'tax_amount')::numeric;
  supplied_total := (p_invoice ->> 'total')::numeric;

  if supplied_subtotal < 0
    or supplied_subtotal > 1000000000000
    or abs(supplied_subtotal - calculated_subtotal) > 0.05 then
    raise exception using errcode = '22023', message = 'Invoice subtotal does not match its items';
  end if;
  if discount_amount < 0 or discount_amount > supplied_subtotal
    or tax_percent < 0 or tax_percent > 100 then
    raise exception using errcode = '22023', message = 'Invoice discount or tax is outside the allowed range';
  end if;
  if abs(
      tax_amount
      - ((supplied_subtotal - discount_amount) * tax_percent / 100)
    ) > 0.05 then
    raise exception using errcode = '22023', message = 'Invoice tax amount is inconsistent';
  end if;
  if supplied_total < 0
    or supplied_total > 1000000000000
    or abs(
      supplied_total
      - (supplied_subtotal - discount_amount + tax_amount)
    ) > 0.05 then
    raise exception using errcode = '22023', message = 'Invoice total is inconsistent';
  end if;

  insert into public.invoices (
    id,
    organization_id,
    project_id,
    client_id,
    estimate_id,
    invoice_number,
    title,
    description,
    status,
    due_date,
    subtotal,
    discount_amount,
    tax_percent,
    tax_amount,
    total,
    cover_transaction_fees,
    terms_and_conditions,
    created_by
  )
  values (
    target_invoice_id,
    project_organization_id,
    target_project_id,
    client_id,
    estimate_id,
    btrim(p_invoice ->> 'invoice_number'),
    coalesce(btrim(p_invoice ->> 'title'), ''),
    coalesce(p_invoice ->> 'description', ''),
    coalesce(nullif(btrim(p_invoice ->> 'status'), ''), 'Draft'),
    coalesce(nullif(btrim(p_invoice ->> 'due_date'), ''), 'On completion'),
    supplied_subtotal,
    discount_amount,
    tax_percent,
    tax_amount,
    supplied_total,
    coalesce((p_invoice ->> 'cover_transaction_fees')::boolean, false),
    coalesce(p_invoice ->> 'terms_and_conditions', ''),
    caller_id
  )
  on conflict (id) do update
  set
    project_id = excluded.project_id,
    client_id = excluded.client_id,
    estimate_id = excluded.estimate_id,
    invoice_number = excluded.invoice_number,
    title = excluded.title,
    description = excluded.description,
    status = excluded.status,
    due_date = excluded.due_date,
    subtotal = excluded.subtotal,
    discount_amount = excluded.discount_amount,
    tax_percent = excluded.tax_percent,
    tax_amount = excluded.tax_amount,
    total = excluded.total,
    cover_transaction_fees = excluded.cover_transaction_fees,
    terms_and_conditions = excluded.terms_and_conditions;

  delete from public.invoice_items
  where invoice_items.invoice_id = target_invoice_id;

  insert into public.invoice_items (
    id,
    organization_id,
    invoice_id,
    title,
    quantity,
    unit_price,
    unit,
    sort_order
  )
  select
    (item_row.value ->> 'id')::uuid,
    project_organization_id,
    target_invoice_id,
    btrim(item_row.value ->> 'title'),
    (item_row.value ->> 'quantity')::numeric,
    (item_row.value ->> 'unit_price')::numeric,
    coalesce(nullif(btrim(item_row.value ->> 'unit'), ''), 'EA'),
    coalesce((item_row.value ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(p_items) item_row(value);

  return target_invoice_id;
end;
$$;

revoke all on function public.upsert_invoice_with_items(jsonb, jsonb)
  from public, anon;
grant execute on function public.upsert_invoice_with_items(jsonb, jsonb) to authenticated;

;
