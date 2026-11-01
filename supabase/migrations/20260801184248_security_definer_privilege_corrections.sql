-- Remove explicit anonymous grants retained from the project's older Data API
-- defaults. These functions authenticate with auth.uid(), but they should not
-- be exposed to unauthenticated callers at all.
revoke all on function public.create_estimate_with_items(uuid, jsonb, jsonb)
  from public, anon;
grant execute on function public.create_estimate_with_items(uuid, jsonb, jsonb)
  to authenticated;

revoke all on function public.upsert_invoice_with_items(jsonb, jsonb)
  from public, anon;
grant execute on function public.upsert_invoice_with_items(jsonb, jsonb)
  to authenticated;

revoke all on function public.delete_current_user_account()
  from public, anon;
grant execute on function public.delete_current_user_account()
  to authenticated;
;
