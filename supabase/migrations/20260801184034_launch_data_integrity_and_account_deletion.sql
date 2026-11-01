-- Launch hardening:
--   1. Persist estimates and invoice line items atomically.
--   2. Delete the current user's relational data and auth account atomically.
--
-- These functions are SECURITY DEFINER because they must perform a complete
-- transaction across RLS-protected tables. Every function derives the caller
-- from auth.uid() and performs its own organization membership checks.

create or replace function public.create_estimate_with_items(
  p_project_id uuid,
  p_estimate jsonb,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  project_organization_id uuid;
  new_estimate_id uuid;
  item jsonb;
  item_count integer;
  calculated_subtotal numeric := 0;
  supplied_subtotal numeric;
  supplied_markup_percent numeric;
  supplied_markup_amount numeric;
  supplied_contingency_percent numeric;
  supplied_contingency_amount numeric;
  supplied_total numeric;
  exclusions text[];
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_estimate is null or jsonb_typeof(p_estimate) <> 'object' then
    raise exception using errcode = '22023', message = 'Estimate must be a JSON object';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception using errcode = '22023', message = 'Estimate items must be a JSON array';
  end if;

  select project.organization_id
  into project_organization_id
  from public.projects project
  where project.id = p_project_id;

  if project_organization_id is null then
    raise exception using errcode = 'P0002', message = 'Project not found';
  end if;
  if not public.is_organization_member(project_organization_id) then
    raise exception using errcode = '42501', message = 'Project access denied';
  end if;

  item_count := jsonb_array_length(p_items);
  if item_count < 1 or item_count > 500 then
    raise exception using errcode = '22023', message = 'An estimate must contain between 1 and 500 items';
  end if;

  for item in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(item) <> 'object' then
      raise exception using errcode = '22023', message = 'Every estimate item must be an object';
    end if;
    if nullif(btrim(item ->> 'name'), '') is null
      or length(item ->> 'name') > 500 then
      raise exception using errcode = '22023', message = 'Every estimate item needs a valid name';
    end if;
    if length(coalesce(item ->> 'category', '')) > 200
      or length(coalesce(item ->> 'unit_label', '')) > 50
      or length(coalesce(item ->> 'source', '')) > 500
      or length(coalesce(item ->> 'url', '')) > 2048
      or length(coalesce(item ->> 'description', '')) > 4000 then
      raise exception using errcode = '22023', message = 'Estimate item text exceeds the allowed length';
    end if;
    if (item ->> 'quantity')::numeric <= 0
      or (item ->> 'quantity')::numeric > 1000000
      or (item ->> 'unit_price')::numeric < 0
      or (item ->> 'unit_price')::numeric > 1000000000
      or (item ->> 'total')::numeric < 0
      or (item ->> 'total')::numeric > 1000000000000 then
      raise exception using errcode = '22023', message = 'Estimate item amount is outside the allowed range';
    end if;
    if abs(
      (item ->> 'total')::numeric
      - round((item ->> 'quantity')::numeric * (item ->> 'unit_price')::numeric, 2)
    ) > 0.02 then
      raise exception using errcode = '22023', message = 'Estimate item total does not match quantity times unit price';
    end if;

    calculated_subtotal := calculated_subtotal + (item ->> 'total')::numeric;
  end loop;

  if nullif(btrim(p_estimate ->> 'title'), '') is null
    or length(p_estimate ->> 'title') > 500 then
    raise exception using errcode = '22023', message = 'Estimate title is invalid';
  end if;
  if length(coalesce(p_estimate ->> 'payment_terms', '')) > 4000
    or length(coalesce(p_estimate ->> 'sanity_check', '')) > 4000 then
    raise exception using errcode = '22023', message = 'Estimate notes exceed the allowed length';
  end if;

  supplied_subtotal := (p_estimate ->> 'subtotal')::numeric;
  supplied_markup_percent := (p_estimate ->> 'markup_percent')::numeric;
  supplied_markup_amount := (p_estimate ->> 'markup_amount')::numeric;
  supplied_contingency_percent := (p_estimate ->> 'contingency_percent')::numeric;
  supplied_contingency_amount := (p_estimate ->> 'contingency_amount')::numeric;
  supplied_total := (p_estimate ->> 'total')::numeric;

  if supplied_subtotal < 0 or supplied_subtotal > 1000000000000
    or abs(supplied_subtotal - calculated_subtotal) > 0.05 then
    raise exception using errcode = '22023', message = 'Estimate subtotal does not match its items';
  end if;
  if supplied_markup_percent < 0 or supplied_markup_percent > 300
    or supplied_contingency_percent < 0 or supplied_contingency_percent > 100 then
    raise exception using errcode = '22023', message = 'Estimate percentage is outside the allowed range';
  end if;
  if abs(
      supplied_markup_amount
      - round(supplied_subtotal * supplied_markup_percent / 100, 2)
    ) > 0.05
    or abs(
      supplied_contingency_amount
      - round(supplied_subtotal * supplied_contingency_percent / 100, 2)
    ) > 0.05 then
    raise exception using errcode = '22023', message = 'Estimate adjustment amount is inconsistent';
  end if;
  if supplied_total < 0
    or supplied_total > 1000000000000
    or abs(
      supplied_total
      - (supplied_subtotal + supplied_markup_amount + supplied_contingency_amount)
    ) > 0.05 then
    raise exception using errcode = '22023', message = 'Estimate total is inconsistent';
  end if;

  if p_estimate ? 'exclusions'
    and p_estimate -> 'exclusions' is not null
    and jsonb_typeof(p_estimate -> 'exclusions') <> 'array' then
    raise exception using errcode = '22023', message = 'Estimate exclusions must be an array';
  end if;

  select coalesce(array_agg(exclusion), '{}'::text[])
  into exclusions
  from jsonb_array_elements_text(
    coalesce(p_estimate -> 'exclusions', '[]'::jsonb)
  ) exclusion;

  if coalesce(array_length(exclusions, 1), 0) > 50
    or exists (select 1 from unnest(exclusions) exclusion where length(exclusion) > 1000) then
    raise exception using errcode = '22023', message = 'Estimate exclusions exceed the allowed size';
  end if;

  insert into public.estimates (
    user_id,
    organization_id,
    project_id,
    title,
    subtotal,
    markup_pct,
    markup_amount,
    contingency_pct,
    contingency_amount,
    total,
    exclusions,
    payment_terms,
    sanity_check
  )
  values (
    caller_id,
    project_organization_id,
    p_project_id,
    btrim(p_estimate ->> 'title'),
    supplied_subtotal,
    supplied_markup_percent,
    supplied_markup_amount,
    supplied_contingency_percent,
    supplied_contingency_amount,
    supplied_total,
    exclusions,
    nullif(btrim(p_estimate ->> 'payment_terms'), ''),
    nullif(btrim(p_estimate ->> 'sanity_check'), '')
  )
  returning id into new_estimate_id;

  insert into public.estimate_items (
    user_id,
    organization_id,
    estimate_id,
    project_id,
    category,
    name,
    quantity,
    unit_label,
    unit_price,
    total,
    source,
    url,
    description,
    on_hand
  )
  select
    caller_id,
    project_organization_id,
    new_estimate_id,
    p_project_id,
    coalesce(nullif(btrim(item ->> 'category'), ''), 'Other'),
    btrim(item ->> 'name'),
    (item ->> 'quantity')::numeric,
    coalesce(nullif(btrim(item ->> 'unit_label'), ''), 'EA'),
    (item ->> 'unit_price')::numeric,
    (item ->> 'total')::numeric,
    nullif(btrim(item ->> 'source'), ''),
    nullif(btrim(item ->> 'url'), ''),
    nullif(btrim(item ->> 'description'), ''),
    coalesce((item ->> 'on_hand')::boolean, false)
  from jsonb_array_elements(p_items) item;

  return new_estimate_id;
end;
$$;

revoke all on function public.create_estimate_with_items(uuid, jsonb, jsonb) from public;
grant execute on function public.create_estimate_with_items(uuid, jsonb, jsonb) to authenticated;

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
  project_id uuid;
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
  project_id := (p_invoice ->> 'project_id')::uuid;
  supplied_organization_id := (p_invoice ->> 'organization_id')::uuid;
  client_id := nullif(p_invoice ->> 'client_id', '')::uuid;
  estimate_id := nullif(p_invoice ->> 'estimate_id', '')::uuid;

  select project.organization_id
  into project_organization_id
  from public.projects project
  where project.id = project_id;

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
      and estimate.project_id = project_id
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
    project_id,
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
    (item ->> 'id')::uuid,
    project_organization_id,
    target_invoice_id,
    btrim(item ->> 'title'),
    (item ->> 'quantity')::numeric,
    (item ->> 'unit_price')::numeric,
    coalesce(nullif(btrim(item ->> 'unit'), ''), 'EA'),
    coalesce((item ->> 'sort_order')::integer, 0)
  from jsonb_array_elements(p_items) item;

  return target_invoice_id;
end;
$$;

revoke all on function public.upsert_invoice_with_items(jsonb, jsonb) from public;
grant execute on function public.upsert_invoice_with_items(jsonb, jsonb) to authenticated;

create or replace function public.delete_current_user_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Serialize deletion against concurrent auth/account operations.
  perform 1
  from auth.users auth_user
  where auth_user.id = caller_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'Account not found';
  end if;

  if exists (
    select 1
    from public.organizations organization
    join public.organization_members membership
      on membership.organization_id = organization.id
    where organization.owner_user_id = caller_id
      and membership.user_id <> caller_id
  ) then
    raise exception using
      errcode = '23503',
      message = 'Transfer or remove the other organization members before deleting the owner account';
  end if;

  -- If team membership is added later, preserve records belonging to another
  -- owner's organization while removing this user's identity references.
  update public.clients record
  set created_by = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.created_by = caller_id
    and organization.owner_user_id <> caller_id;

  update public.properties record
  set created_by = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.created_by = caller_id
    and organization.owner_user_id <> caller_id;

  update public.projects record
  set created_by = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.created_by = caller_id
    and organization.owner_user_id <> caller_id;

  update public.projects record
  set assignee_user_id = null
  where record.assignee_user_id = caller_id;

  update public.estimates record
  set user_id = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.user_id = caller_id
    and organization.owner_user_id <> caller_id;

  update public.estimate_items record
  set user_id = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.user_id = caller_id
    and organization.owner_user_id <> caller_id;

  update public.invoices record
  set created_by = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.created_by = caller_id
    and organization.owner_user_id <> caller_id;

  update public.project_documents record
  set uploaded_by = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.uploaded_by = caller_id
    and organization.owner_user_id <> caller_id;

  update public.estimate_share_links record
  set created_by = organization.owner_user_id
  from public.organizations organization
  where record.organization_id = organization.id
    and record.created_by = caller_id
    and organization.owner_user_id <> caller_id;

  -- A user's personal organization owns its client, project, estimate,
  -- invoice, portal-link, and document metadata. Cascades remove it all.
  delete from public.organizations organization
  where organization.owner_user_id = caller_id;

  delete from public.organization_members membership
  where membership.user_id = caller_id;

  -- Auth identities and sessions cascade from auth.users.
  delete from auth.users auth_user
  where auth_user.id = caller_id;

  if not found then
    raise exception using errcode = 'P0002', message = 'Account not found';
  end if;

  return true;
end;
$$;

revoke all on function public.delete_current_user_account() from public;
grant execute on function public.delete_current_user_account() to authenticated;
;
