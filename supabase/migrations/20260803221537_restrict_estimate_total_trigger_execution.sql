-- Trigger functions execute through their trigger and do not need API access.
revoke all on function public.sync_estimate_totals_from_items() from public;
revoke all on function public.sync_estimate_totals_from_items() from anon;
revoke all on function public.sync_estimate_totals_from_items() from authenticated;
revoke all on function public.sync_estimate_totals_from_items() from service_role;
;
