-- Atomically replace the contents of an existing estimate after an AI edit.
-- The caller must be authenticated and belong to the estimate's organization.

create or replace function public.replace_estimate_with_items(
  p_estimate_id uuid,
  p_estimate jsonb,
  p_items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
  estimate_organization_id uuid;
  item_row record;
  item_count integer;
  calculated_subtotal numeric := 0;
  supplied_subtotal numeric;
  supplied_markup_percent numeric;
  supplied_markup_amount numeric;
  supplied_contingency_percent numeric;
  supplied_contingency_amount numeric;
  supplied_total numeric;
  supplied_exclusions jsonb;
begin
  if caller_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_estimate_id is null then
    raise exception using errcode = '22023', message = 'Estimate ID is required';
  end if;
  if p_estimate is null or jsonb_typeof(p_estimate) <> 'object' then
    raise exception using errcode = '22023', message = 'Estimate must be a JSON object';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception using errcode = '22023', message = 'Estimate items must be a JSON array';
  end if;

  select estimate.organization_id
  into estimate_organization_id
  from public.estimates estimate
  where estimate.id = p_estimate_id
  for update;

  if estimate_organization_id is null then
    raise exception using errcode = 'P0002', message = 'Estimate not found';
  end if;
  if not public.is_organization_member(estimate_organization_id) then
    raise exception using errcode = '42501', message = 'Estimate access denied';
  end if;

  item_count := jsonb_array_length(p_items);
  if item_count < 1 or item_count > 500 then
    raise exception using errcode = '22023', message = 'An estimate must contain between 1 and 500 items';
  end if;

  for item_row in select value from jsonb_array_elements(p_items)
  loop
    if jsonb_typeof(item_row.value) <> 'object' then
      raise exception using errcode = '22023', message = 'Every estimate item must be an object';
    end if;
    if nullif(btrim(item_row.value ->> 'name'), '') is null
      or length(item_row.value ->> 'name') > 500 then
      raise exception using errcode = '22023', message = 'Every estimate item needs a valid name';
    end if;
    if length(coalesce(item_row.value ->> 'category', '')) > 200
      or length(coalesce(item_row.value ->> 'unit_label', '')) > 50
      or length(coalesce(item_row.value ->> 'source', '')) > 500
      or length(coalesce(item_row.value ->> 'url', '')) > 2048
      or length(coalesce(item_row.value ->> 'description', '')) > 4000 then
      raise exception using errcode = '22023', message = 'Estimate item text exceeds the allowed length';
    end if;
    if (item_row.value ->> 'quantity')::numeric <= 0
      or (item_row.value ->> 'quantity')::numeric > 1000000
      or (item_row.value ->> 'unit_price')::numeric < 0
      or (item_row.value ->> 'unit_price')::numeric > 1000000000
      or (item_row.value ->> 'total')::numeric < 0
      or (item_row.value ->> 'total')::numeric > 1000000000000 then
      raise exception using errcode = '22023', message = 'Estimate item amount is outside the allowed range';
    end if;
    if abs(
      (item_row.value ->> 'total')::numeric
      - round(
          (item_row.value ->> 'quantity')::numeric
          * (item_row.value ->> 'unit_price')::numeric,
          2
        )
    ) > 0.02 then
      raise exception using errcode = '22023', message = 'Estimate item total is inconsistent';
    end if;
    calculated_subtotal := calculated_subtotal + (item_row.value ->> 'total')::numeric;
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
  if supplied_total < 0 or supplied_total > 1000000000000
    or abs(
      supplied_total
      - (supplied_subtotal + supplied_markup_amount + supplied_contingency_amount)
    ) > 0.05 then
    raise exception using errcode = '22023', message = 'Estimate total is inconsistent';
  end if;

  supplied_exclusions := coalesce(p_estimate -> 'exclusions', '[]'::jsonb);
  if jsonb_typeof(supplied_exclusions) <> 'array'
    or jsonb_array_length(supplied_exclusions) > 50
    or exists (
      select 1
      from jsonb_array_elements(supplied_exclusions) exclusion(value)
      where jsonb_typeof(exclusion.value) <> 'string'
        or length(exclusion.value #>> '{}') > 1000
    ) then
    raise exception using errcode = '22023', message = 'Estimate exclusions exceed the allowed size';
  end if;

  update public.estimates
  set
    title = btrim(p_estimate ->> 'title'),
    subtotal = supplied_subtotal,
    markup_pct = supplied_markup_percent,
    markup_amount = supplied_markup_amount,
    contingency_pct = supplied_contingency_percent,
    contingency_amount = supplied_contingency_amount,
    total = supplied_total,
    exclusions = supplied_exclusions,
    payment_terms = nullif(btrim(p_estimate ->> 'payment_terms'), ''),
    sanity_check = nullif(btrim(p_estimate ->> 'sanity_check'), '')
  where id = p_estimate_id;

  delete from public.estimate_items
  where estimate_id = p_estimate_id;

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
    estimate_organization_id,
    p_estimate_id,
    estimate.project_id,
    coalesce(nullif(btrim(input_item.value ->> 'category'), ''), 'Other'),
    btrim(input_item.value ->> 'name'),
    (input_item.value ->> 'quantity')::numeric,
    coalesce(nullif(btrim(input_item.value ->> 'unit_label'), ''), 'EA'),
    (input_item.value ->> 'unit_price')::numeric,
    (input_item.value ->> 'total')::numeric,
    nullif(btrim(input_item.value ->> 'source'), ''),
    nullif(btrim(input_item.value ->> 'url'), ''),
    nullif(btrim(input_item.value ->> 'description'), ''),
    coalesce((input_item.value ->> 'on_hand')::boolean, false)
  from jsonb_array_elements(p_items) input_item(value)
  cross join public.estimates estimate
  where estimate.id = p_estimate_id;

  return p_estimate_id;
end;
$$;

revoke all on function public.replace_estimate_with_items(uuid, jsonb, jsonb) from public;
revoke all on function public.replace_estimate_with_items(uuid, jsonb, jsonb) from anon;
grant execute on function public.replace_estimate_with_items(uuid, jsonb, jsonb) to authenticated;

-- Keep parent estimate totals synchronized after manual line-item changes.
create or replace function public.sync_estimate_totals_from_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_estimate_id uuid;
  new_subtotal numeric;
begin
  if tg_op = 'DELETE' then
    target_estimate_id := old.estimate_id;
  else
    target_estimate_id := new.estimate_id;
  end if;

  select coalesce(sum(item.total), 0)
  into new_subtotal
  from public.estimate_items item
  where item.estimate_id = target_estimate_id;

  update public.estimates estimate
  set
    subtotal = round(new_subtotal, 2),
    markup_amount = round(new_subtotal * coalesce(estimate.markup_pct, 0) / 100, 2),
    contingency_amount = round(new_subtotal * coalesce(estimate.contingency_pct, 0) / 100, 2),
    total = round(
      new_subtotal
      + (new_subtotal * coalesce(estimate.markup_pct, 0) / 100)
      + (new_subtotal * coalesce(estimate.contingency_pct, 0) / 100),
      2
    )
  where estimate.id = target_estimate_id;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.sync_estimate_totals_from_items() from public;
revoke all on function public.sync_estimate_totals_from_items() from anon;
revoke all on function public.sync_estimate_totals_from_items() from authenticated;
revoke all on function public.sync_estimate_totals_from_items() from service_role;

drop trigger if exists sync_estimate_totals_after_item_change
  on public.estimate_items;
create trigger sync_estimate_totals_after_item_change
  after insert or delete or update of estimate_id, quantity, unit_price, total
  on public.estimate_items
  for each row execute function public.sync_estimate_totals_from_items();
;
