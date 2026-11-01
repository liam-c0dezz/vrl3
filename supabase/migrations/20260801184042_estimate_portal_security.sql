-- Bound all anonymous portal inputs and keep public RPC execution short.
-- The share token remains a 256-bit random value; only its SHA-256 hash is
-- stored in the database.

alter table public.estimate_share_links
  add constraint estimate_share_links_token_hash_format
  check (token_hash ~ '^[0-9a-f]{64}$') not valid;

alter table public.estimate_share_links
  add constraint estimate_share_links_approved_by_length
  check (
    approved_by is null
    or char_length(approved_by) between 1 and 120
  ) not valid;

alter table public.estimate_share_links
  add constraint estimate_share_links_change_request_length
  check (
    change_request is null
    or char_length(change_request) between 1 and 4000
  ) not valid;

alter table public.estimate_share_links
  validate constraint estimate_share_links_token_hash_format;

alter table public.estimate_share_links
  validate constraint estimate_share_links_approved_by_length;

alter table public.estimate_share_links
  validate constraint estimate_share_links_change_request_length;

alter function public.get_public_estimate(text)
  set statement_timeout = '5s';

alter function public.approve_public_estimate(text, text)
  set statement_timeout = '5s';

alter function public.request_public_estimate_change(text, text)
  set statement_timeout = '5s';
;
