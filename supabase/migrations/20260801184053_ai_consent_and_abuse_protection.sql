-- EasyBid AI consent, quota, concurrency, and idempotency enforcement.
--
-- The iOS client may display consent state, but only these server-owned
-- records and RPCs authorize an OpenAI request. Rate-limit accounting is
-- atomic and intentionally inaccessible to app clients.

create table if not exists public.ai_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_granted boolean not null,
  consent_version text not null,
  app_version text,
  granted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ai_consents_version_length
    check (char_length(consent_version) between 1 and 100),
  constraint ai_consents_app_version_length
    check (app_version is null or char_length(app_version) between 1 and 50),
  constraint ai_consents_timestamps_match_state
    check (
      (is_granted and granted_at is not null and revoked_at is null)
      or
      (not is_granted and revoked_at is not null)
    )
);

create table if not exists public.ai_consent_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_granted boolean not null,
  consent_version text not null,
  app_version text,
  occurred_at timestamptz not null default now(),
  constraint ai_consent_events_version_length
    check (char_length(consent_version) between 1 and 100),
  constraint ai_consent_events_app_version_length
    check (app_version is null or char_length(app_version) between 1 and 50)
);

create index if not exists ai_consent_events_user_occurred_idx
  on public.ai_consent_events(user_id, occurred_at desc);

alter table public.ai_consents enable row level security;
alter table public.ai_consent_events enable row level security;

revoke all on table public.ai_consents from public, anon, authenticated;
revoke all on table public.ai_consent_events from public, anon, authenticated;
grant select on table public.ai_consents to authenticated;

drop policy if exists "users can view their AI consent" on public.ai_consents;
create policy "users can view their AI consent"
  on public.ai_consents for select to authenticated
  using (user_id = (select auth.uid()));

create or replace function public.set_ai_consent(
  p_granted boolean,
  p_consent_version text,
  p_app_version text default null
)
returns public.ai_consents
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_version text := btrim(p_consent_version);
  normalized_app_version text := nullif(btrim(p_app_version), '');
  result public.ai_consents;
begin
  if caller_id is null then
    raise exception using errcode = '28000', message = 'Authentication required';
  end if;
  if normalized_version is null
     or char_length(normalized_version) not between 1 and 100 then
    raise exception using errcode = '22023', message = 'Invalid consent version';
  end if;
  if normalized_app_version is not null
     and char_length(normalized_app_version) > 50 then
    raise exception using errcode = '22023', message = 'Invalid app version';
  end if;

  insert into public.ai_consents (
    user_id,
    is_granted,
    consent_version,
    app_version,
    granted_at,
    revoked_at
  ) values (
    caller_id,
    p_granted,
    normalized_version,
    normalized_app_version,
    case when p_granted then now() else null end,
    case when p_granted then null else now() end
  )
  on conflict (user_id) do update set
    is_granted = excluded.is_granted,
    consent_version = excluded.consent_version,
    app_version = excluded.app_version,
    granted_at = case
      when excluded.is_granted then now()
      else public.ai_consents.granted_at
    end,
    revoked_at = case when excluded.is_granted then null else now() end,
    updated_at = now()
  returning * into result;

  insert into public.ai_consent_events (
    user_id,
    is_granted,
    consent_version,
    app_version
  ) values (
    caller_id,
    p_granted,
    normalized_version,
    normalized_app_version
  );

  return result;
end;
$$;

revoke all on function public.set_ai_consent(boolean, text, text)
  from public, anon;
grant execute on function public.set_ai_consent(boolean, text, text)
  to authenticated;

create table if not exists public.ai_service_config (
  id boolean primary key default true check (id),
  is_enabled boolean not null default true,
  per_user_per_minute integer not null default 8
    check (per_user_per_minute between 1 and 1000),
  per_user_per_day integer not null default 75
    check (per_user_per_day between 1 and 100000),
  per_user_per_month integer not null default 1500
    check (per_user_per_month between 1 and 1000000),
  per_ip_per_minute integer not null default 20
    check (per_ip_per_minute between 1 and 10000),
  max_concurrent_per_user integer not null default 1
    check (max_concurrent_per_user between 1 and 20),
  request_lease_seconds integer not null default 180
    check (request_lease_seconds between 30 and 1800),
  max_output_tokens integer not null default 2000
    check (max_output_tokens between 100 and 10000),
  updated_at timestamptz not null default now()
);

insert into public.ai_service_config (id)
values (true)
on conflict (id) do nothing;

create table if not exists public.ai_requests (
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  uses_ai boolean not null,
  status text not null,
  response_body jsonb,
  error_code text,
  lease_expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (user_id, request_id),
  constraint ai_requests_status
    check (status in ('processing', 'succeeded', 'failed')),
  constraint ai_requests_error_code_length
    check (error_code is null or char_length(error_code) between 1 and 100),
  constraint ai_requests_response_size
    check (response_body is null or pg_column_size(response_body) <= 1048576)
);

create index if not exists ai_requests_active_user_idx
  on public.ai_requests(user_id, lease_expires_at)
  where status = 'processing';

create index if not exists ai_requests_cleanup_idx
  on public.ai_requests(created_at);

create table if not exists public.ai_usage_buckets (
  subject_kind text not null check (subject_kind in ('user', 'ip')),
  subject_key text not null check (char_length(subject_key) between 1 and 128),
  bucket_kind text not null check (bucket_kind in ('minute', 'day', 'month')),
  bucket_start timestamptz not null,
  request_count integer not null default 0 check (request_count >= 0),
  updated_at timestamptz not null default now(),
  primary key (subject_kind, subject_key, bucket_kind, bucket_start)
);

create index if not exists ai_usage_buckets_cleanup_idx
  on public.ai_usage_buckets(bucket_start);

alter table public.ai_service_config enable row level security;
alter table public.ai_requests enable row level security;
alter table public.ai_usage_buckets enable row level security;

revoke all on table public.ai_service_config from public, anon, authenticated;
revoke all on table public.ai_requests from public, anon, authenticated;
revoke all on table public.ai_usage_buckets from public, anon, authenticated;

create or replace function public.reserve_ai_request(
  p_user_id uuid,
  p_request_id uuid,
  p_uses_ai boolean,
  p_consent_version text,
  p_ip_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  config public.ai_service_config;
  existing public.ai_requests;
  minute_start timestamptz := date_trunc('minute', now());
  day_start timestamptz := date_trunc('day', now());
  month_start timestamptz := date_trunc('month', now());
  user_key text := p_user_id::text;
  minute_count integer;
  day_count integer;
  month_count integer;
  ip_minute_count integer;
  active_count integer;
begin
  if p_user_id is null or p_request_id is null then
    raise exception using errcode = '22023', message = 'Invalid request identity';
  end if;
  if p_ip_hash is not null and p_ip_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid IP hash';
  end if;

  -- Serialize counters and concurrency decisions for this user.
  perform pg_advisory_xact_lock(hashtextextended(user_key, 913744));

  -- Cached provider responses contain user content. Retain the response for
  -- retry safety for 24 hours, then remove it; keep lightweight accounting
  -- records for no more than 35 days.
  update public.ai_requests
  set response_body = null,
      updated_at = now()
  where user_id = p_user_id
    and response_body is not null
    and completed_at < now() - interval '24 hours';

  -- A crashed or timed-out worker must not leave an idempotency key stuck in
  -- "processing" forever. Expired leases become retryable only with a new
  -- request ID, which avoids two workers charging for the same logical tap.
  update public.ai_requests
  set status = 'failed',
      error_code = 'request_expired',
      completed_at = now(),
      updated_at = now()
  where user_id = p_user_id
    and status = 'processing'
    and lease_expires_at <= now();

  delete from public.ai_requests
  where user_id = p_user_id
    and status <> 'processing'
    and created_at < now() - interval '35 days';

  delete from public.ai_usage_buckets
  where subject_kind = 'user'
    and subject_key = user_key
    and (
      (bucket_kind = 'minute' and bucket_start < now() - interval '2 days')
      or (bucket_kind = 'day' and bucket_start < now() - interval '40 days')
      or (bucket_kind = 'month' and bucket_start < now() - interval '14 months')
    );

  if p_ip_hash is not null then
    delete from public.ai_usage_buckets
    where subject_kind = 'ip'
      and subject_key = p_ip_hash
      and bucket_kind = 'minute'
      and bucket_start < now() - interval '2 days';
  end if;

  select * into config
  from public.ai_service_config
  where id = true
  for update;

  if config.id is null or not config.is_enabled then
    return jsonb_build_object('state', 'disabled');
  end if;

  select * into existing
  from public.ai_requests
  where user_id = p_user_id and request_id = p_request_id;

  if existing.request_id is not null then
    if existing.status = 'succeeded' then
      return jsonb_build_object(
        'state', 'cached',
        'response', existing.response_body
      );
    end if;
    if existing.status = 'processing' then
      return jsonb_build_object('state', 'in_progress');
    end if;
    return jsonb_build_object('state', 'failed');
  end if;

  if p_uses_ai and not exists (
    select 1
    from public.ai_consents consent
    where consent.user_id = p_user_id
      and consent.is_granted
      and consent.consent_version = p_consent_version
      and consent.revoked_at is null
  ) then
    return jsonb_build_object('state', 'consent_required');
  end if;

  select count(*) into active_count
  from public.ai_requests request
  where request.user_id = p_user_id
    and request.status = 'processing'
    and request.lease_expires_at > now();

  if active_count >= config.max_concurrent_per_user then
    return jsonb_build_object('state', 'busy');
  end if;

  select coalesce(sum(request_count), 0)::integer into minute_count
  from public.ai_usage_buckets
  where subject_kind = 'user'
    and subject_key = user_key
    and bucket_kind = 'minute'
    and bucket_start = minute_start;

  if minute_count >= config.per_user_per_minute then
    return jsonb_build_object('state', 'rate_limited', 'scope', 'minute');
  end if;

  if p_ip_hash is not null then
    perform pg_advisory_xact_lock(hashtextextended(p_ip_hash, 913745));
    select coalesce(sum(request_count), 0)::integer into ip_minute_count
    from public.ai_usage_buckets
    where subject_kind = 'ip'
      and subject_key = p_ip_hash
      and bucket_kind = 'minute'
      and bucket_start = minute_start;
    if ip_minute_count >= config.per_ip_per_minute then
      return jsonb_build_object('state', 'rate_limited', 'scope', 'ip');
    end if;
  end if;

  if p_uses_ai then
    select coalesce(sum(request_count), 0)::integer into day_count
    from public.ai_usage_buckets
    where subject_kind = 'user'
      and subject_key = user_key
      and bucket_kind = 'day'
      and bucket_start = day_start;
    if day_count >= config.per_user_per_day then
      return jsonb_build_object('state', 'quota_exceeded', 'scope', 'day');
    end if;

    select coalesce(sum(request_count), 0)::integer into month_count
    from public.ai_usage_buckets
    where subject_kind = 'user'
      and subject_key = user_key
      and bucket_kind = 'month'
      and bucket_start = month_start;
    if month_count >= config.per_user_per_month then
      return jsonb_build_object('state', 'quota_exceeded', 'scope', 'month');
    end if;
  end if;

  insert into public.ai_requests (
    user_id,
    request_id,
    uses_ai,
    status,
    lease_expires_at
  ) values (
    p_user_id,
    p_request_id,
    p_uses_ai,
    'processing',
    now() + make_interval(secs => config.request_lease_seconds)
  );

  insert into public.ai_usage_buckets (
    subject_kind, subject_key, bucket_kind, bucket_start, request_count
  ) values ('user', user_key, 'minute', minute_start, 1)
  on conflict (subject_kind, subject_key, bucket_kind, bucket_start)
  do update set
    request_count = public.ai_usage_buckets.request_count + 1,
    updated_at = now();

  if p_ip_hash is not null then
    insert into public.ai_usage_buckets (
      subject_kind, subject_key, bucket_kind, bucket_start, request_count
    ) values ('ip', p_ip_hash, 'minute', minute_start, 1)
    on conflict (subject_kind, subject_key, bucket_kind, bucket_start)
    do update set
      request_count = public.ai_usage_buckets.request_count + 1,
      updated_at = now();
  end if;

  if p_uses_ai then
    insert into public.ai_usage_buckets (
      subject_kind, subject_key, bucket_kind, bucket_start, request_count
    ) values
      ('user', user_key, 'day', day_start, 1),
      ('user', user_key, 'month', month_start, 1)
    on conflict (subject_kind, subject_key, bucket_kind, bucket_start)
    do update set
      request_count = public.ai_usage_buckets.request_count + 1,
      updated_at = now();
  end if;

  return jsonb_build_object(
    'state', 'granted',
    'max_output_tokens', config.max_output_tokens
  );
end;
$$;

create or replace function public.complete_ai_request(
  p_user_id uuid,
  p_request_id uuid,
  p_response_body jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
begin
  if p_response_body is null or pg_column_size(p_response_body) > 1048576 then
    raise exception using errcode = '22023', message = 'Invalid cached response';
  end if;

  update public.ai_requests
  set status = 'succeeded',
      response_body = p_response_body,
      error_code = null,
      completed_at = now(),
      updated_at = now()
  where user_id = p_user_id
    and request_id = p_request_id
    and status = 'processing';
  get diagnostics changed_count = row_count;
  return changed_count = 1;
end;
$$;

create or replace function public.fail_ai_request(
  p_user_id uuid,
  p_request_id uuid,
  p_error_code text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer;
  normalized_code text := nullif(btrim(p_error_code), '');
begin
  if normalized_code is null or char_length(normalized_code) > 100 then
    normalized_code := 'internal_error';
  end if;

  update public.ai_requests
  set status = 'failed',
      response_body = null,
      error_code = normalized_code,
      completed_at = now(),
      updated_at = now()
  where user_id = p_user_id
    and request_id = p_request_id
    and status = 'processing';
  get diagnostics changed_count = row_count;
  return changed_count = 1;
end;
$$;

create or replace function public.has_current_ai_consent(
  p_user_id uuid,
  p_consent_version text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.ai_consents consent
    where consent.user_id = p_user_id
      and consent.is_granted
      and consent.consent_version = p_consent_version
      and consent.revoked_at is null
  );
$$;

revoke all on function public.reserve_ai_request(uuid, uuid, boolean, text, text)
  from public, anon, authenticated;
revoke all on function public.complete_ai_request(uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.fail_ai_request(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.has_current_ai_consent(uuid, text)
  from public, anon, authenticated;

grant execute on function public.reserve_ai_request(uuid, uuid, boolean, text, text)
  to service_role;
grant execute on function public.complete_ai_request(uuid, uuid, jsonb)
  to service_role;
grant execute on function public.fail_ai_request(uuid, uuid, text)
  to service_role;
grant execute on function public.has_current_ai_consent(uuid, text)
  to service_role;

-- Supabase can retain explicit anon/authenticated EXECUTE grants from older
-- function defaults. Revoke them explicitly instead of relying only on the
-- PostgreSQL PUBLIC role. Membership helpers remain available only to signed-in
-- users because RLS policies call them; share-link creation is also signed-in
-- only. Public portal RPCs below intentionally remain token-gated and public.
revoke all on function public.is_organization_member(uuid)
  from public, anon;
revoke all on function public.is_organization_admin(uuid)
  from public, anon;
revoke all on function public.current_organization_id()
  from public, anon;
revoke all on function public.can_access_project_file(text)
  from public, anon;
revoke all on function public.create_estimate_share_link(uuid)
  from public, anon;

grant execute on function public.is_organization_member(uuid)
  to authenticated;
grant execute on function public.is_organization_admin(uuid)
  to authenticated;
grant execute on function public.current_organization_id()
  to authenticated;
grant execute on function public.can_access_project_file(text)
  to authenticated;
grant execute on function public.create_estimate_share_link(uuid)
  to authenticated;

-- Legacy production drift: this global catalog-setting function is not in a
-- clean migration replay and is not called by the iOS app. If it exists,
-- remove mutable search-path behavior and all client execution privileges.
do $migration$
begin
  if to_regprocedure(
    'public.set_contractor_location(text,text,text)'
  ) is not null then
    execute $definition$
      create or replace function public.set_contractor_location(
        p_zip text,
        p_city text,
        p_state text
      )
      returns table(resolved_wage numeric)
      language plpgsql
      security invoker
      set search_path = ''
      as $body$
      declare
        resolved numeric;
        national_median constant numeric := 30.67;
      begin
        select wage.median_wage into resolved
        from public.state_wage_index wage
        where wage.state_code = upper(p_state);

        resolved := coalesce(resolved, national_median);

        update public.shop_settings
        set location_zip = p_zip,
            location_city = p_city,
            location_state = upper(p_state),
            local_wage = resolved,
            location_set_at = now()
        where id = 1;

        return query select resolved;
      end;
      $body$
    $definition$;

    execute 'revoke all on function public.set_contractor_location(text, text, text) from public, anon, authenticated';
  end if;
end;
$migration$;

-- Internal trigger helpers must not be directly callable over the Data API.
revoke all on function public.handle_new_user_organization()
  from public, anon, authenticated;
revoke all on function public.sync_estimate_parent_fields()
  from public, anon, authenticated;
revoke all on function public.sync_estimate_item_parent_fields()
  from public, anon, authenticated;
revoke all on function public.sync_invoice_child_organization()
  from public, anon, authenticated;
revoke all on function public.set_updated_at()
  from public, anon, authenticated;
revoke all on function public.assign_legacy_estimates_to_first_user()
  from public, anon, authenticated;

-- This helper is only called internally by create_estimate_share_link.
revoke all on function public.build_estimate_portal_snapshot(uuid)
  from public, anon, authenticated;

-- Public portal functions remain token-gated, but bound their execution time.
alter function public.get_public_estimate(text) set statement_timeout = '5s';
alter function public.approve_public_estimate(text, text) set statement_timeout = '5s';
alter function public.request_public_estimate_change(text, text)
  set statement_timeout = '5s';

-- Cover production foreign keys reported by the Supabase advisor. These are
-- additive and reduce slow cascades/joins without changing application data.
create index if not exists clients_created_by_idx
  on public.clients(created_by);
create index if not exists estimate_share_links_created_by_idx
  on public.estimate_share_links(created_by);
create index if not exists invoices_created_by_idx
  on public.invoices(created_by);
create index if not exists invoices_estimate_id_idx
  on public.invoices(estimate_id);
create index if not exists job_materials_material_id_idx
  on public.job_materials(material_id);
do $migration$
begin
  if to_regclass('public.job_question_options') is not null then
    execute 'create index if not exists job_question_options_question_id_idx on public.job_question_options(question_id)';
  end if;
  if to_regclass('public.job_questions') is not null then
    execute 'create index if not exists job_questions_job_id_idx on public.job_questions(job_id)';
  end if;
end;
$migration$;
create index if not exists project_documents_invoice_id_idx
  on public.project_documents(invoice_id);
create index if not exists project_documents_uploaded_by_idx
  on public.project_documents(uploaded_by);
create index if not exists projects_assignee_user_id_idx
  on public.projects(assignee_user_id);
create index if not exists projects_created_by_idx
  on public.projects(created_by);
create index if not exists properties_created_by_idx
  on public.properties(created_by);
;
