-- The authenticated role already has table privileges and every affected
-- table enforces organization-scoped RLS. Running as the caller keeps those
-- policies active throughout the atomic replacement transaction.
alter function public.replace_estimate_with_items(uuid, jsonb, jsonb)
  security invoker;
;
