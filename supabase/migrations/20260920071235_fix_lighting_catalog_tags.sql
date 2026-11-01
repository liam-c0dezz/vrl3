-- Correct the substring collision where "indoor lighting" matched the
-- earlier "door" keyword before the lighting classifier ran.
update public.estimator_cost_items
set
  object_key = 'lighting',
  trade = 'electrical',
  updated_at = now()
where catalog_version = 'repair-2026-q3'
  and residential_eligible
  and object_key = 'door'
  and (
    lower(category || ' ' || description) like '%lighting%' or
    lower(category || ' ' || description) like '%light fixture%' or
    lower(category || ' ' || description) like '%luminaire%'
  );
