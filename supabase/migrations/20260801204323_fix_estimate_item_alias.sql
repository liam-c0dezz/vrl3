-- Remove the PL/pgSQL item-variable/table-alias collision in the atomic
-- estimate insert. PostgreSQL correctly rejects the ambiguous reference.

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
  exclusions jsonb;
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

  exclusions := coalesce(p_estimate -> 'exclusions', '[]'::jsonb);

  if jsonb_array_length(exclusions) > 50
    or exists (
      select 1
      from jsonb_array_elements(exclusions) exclusion(value)
      where jsonb_typeof(exclusion.value) <> 'string'
        or length(exclusion.value #>> '{}') > 1000
    ) then
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
    coalesce(nullif(btrim(item_row.value ->> 'category'), ''), 'Other'),
    btrim(item_row.value ->> 'name'),
    (item_row.value ->> 'quantity')::numeric,
    coalesce(nullif(btrim(item_row.value ->> 'unit_label'), ''), 'EA'),
    (item_row.value ->> 'unit_price')::numeric,
    (item_row.value ->> 'total')::numeric,
    nullif(btrim(item_row.value ->> 'source'), ''),
    nullif(btrim(item_row.value ->> 'url'), ''),
    nullif(btrim(item_row.value ->> 'description'), ''),
    coalesce((item_row.value ->> 'on_hand')::boolean, false)
  from jsonb_array_elements(p_items) item_row(value);

  return new_estimate_id;
end;
$$;



;
