-- Reject malformed or oversized anonymous portal inputs before hashing or
-- querying. The web client already applies the same limits; these checks make
-- the public RPC boundary safe even when called directly.

create or replace function public.get_public_estimate(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '5s'
as $$
declare
  share_record public.estimate_share_links%rowtype;
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select *
  into share_record
  from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status <> 'revoked'
    and expires_at > now();

  if share_record.id is null then
    return null;
  end if;

  update public.estimate_share_links
  set
    status = case when status = 'sent' then 'viewed' else status end,
    first_viewed_at = coalesce(first_viewed_at, now()),
    last_viewed_at = now(),
    updated_at = now()
  where id = share_record.id;

  if share_record.status = 'sent' then
    update public.estimates
    set status = 'Viewed'
    where id = share_record.estimate_id
      and status = 'Sent';
  end if;

  return share_record.snapshot || jsonb_build_object(
    'share', jsonb_build_object(
      'status', case when share_record.status = 'sent' then 'viewed' else share_record.status end,
      'expires_at', share_record.expires_at,
      'approved_at', share_record.approved_at,
      'approved_by', share_record.approved_by,
      'change_request', share_record.change_request
    )
  );
end;
$$;

create or replace function public.approve_public_estimate(
  p_token text,
  p_approved_by text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '5s'
as $$
declare
  share_record public.estimate_share_links%rowtype;
  signer_name text := nullif(trim(p_approved_by), '');
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'This estimate link is no longer available';
  end if;
  if signer_name is null or char_length(signer_name) > 120 then
    raise exception 'Your name is required';
  end if;

  select *
  into share_record
  from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status in ('sent', 'viewed')
    and expires_at > now()
  for update;

  if share_record.id is null then
    raise exception 'This estimate link is no longer available';
  end if;

  update public.estimate_share_links
  set
    status = 'approved',
    approved_at = now(),
    approved_by = signer_name,
    updated_at = now()
  where id = share_record.id;

  update public.estimates
  set status = 'Approved'
  where id = share_record.estimate_id;

  update public.projects
  set status = 'Approved', updated_at = now()
  where id = share_record.project_id;

  return jsonb_build_object(
    'status', 'approved',
    'approved_by', signer_name,
    'approved_at', now()
  );
end;
$$;

create or replace function public.request_public_estimate_change(
  p_token text,
  p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set statement_timeout = '5s'
as $$
declare
  share_record public.estimate_share_links%rowtype;
  request_message text := nullif(trim(p_message), '');
begin
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    raise exception 'This estimate link is no longer available';
  end if;
  if request_message is null or char_length(request_message) > 4000 then
    raise exception 'Please describe the requested change';
  end if;

  select *
  into share_record
  from public.estimate_share_links
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status in ('sent', 'viewed')
    and expires_at > now()
  for update;

  if share_record.id is null then
    raise exception 'This estimate link is no longer available';
  end if;

  update public.estimate_share_links
  set
    status = 'changes_requested',
    change_requested_at = now(),
    change_request = request_message,
    updated_at = now()
  where id = share_record.id;

  update public.estimates
  set status = 'Changes Requested'
  where id = share_record.estimate_id;

  update public.projects
  set status = 'Draft', updated_at = now()
  where id = share_record.project_id;

  return jsonb_build_object(
    'status', 'changes_requested',
    'message', request_message
  );
end;
$$;

revoke all on function public.get_public_estimate(text) from public;
revoke all on function public.approve_public_estimate(text, text) from public;
revoke all on function public.request_public_estimate_change(text, text) from public;

grant execute on function public.get_public_estimate(text)
  to anon, authenticated;
grant execute on function public.approve_public_estimate(text, text)
  to anon, authenticated;
grant execute on function public.request_public_estimate_change(text, text)
  to anon, authenticated;
;
