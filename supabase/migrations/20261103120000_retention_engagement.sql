-- Retention: notification preferences, push devices, a push outbox driven by
-- client activity, lifecycle email bookkeeping, engagement analytics, and a
-- pg_cron schedule that calls the `retention-dispatch` edge function.
--
-- Nothing here needs manual setup: the dispatch secret is generated below and
-- shared with the edge function through a service-role-only function.

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;

-- ---------------------------------------------------------------------------
-- Per-user preferences and lifecycle state (written by the app)
-- ---------------------------------------------------------------------------
create table if not exists public.retention_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  timezone text not null default 'America/Denver' check (length(timezone) between 1 and 64),
  language text not null default 'en' check (language in ('en', 'es')),
  preferred_hour smallint not null default 9 check (preferred_hour between 0 and 23),
  quiet_start smallint not null default 21 check (quiet_start between 0 and 23),
  quiet_end smallint not null default 8 check (quiet_end between 0 and 23),
  frequency text not null default 'all' check (frequency in ('all', 'important', 'off')),
  email_opt_in boolean not null default true,
  trial_started_at timestamptz,
  last_active_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.retention_profiles enable row level security;
revoke all on table public.retention_profiles from public, anon, authenticated;
grant select on table public.retention_profiles to authenticated;
grant insert (user_id, timezone, language, preferred_hour, quiet_start, quiet_end, frequency,
              email_opt_in, trial_started_at, last_active_at)
  on table public.retention_profiles to authenticated;
grant update (timezone, language, preferred_hour, quiet_start, quiet_end, frequency,
              email_opt_in, trial_started_at, last_active_at, updated_at)
  on table public.retention_profiles to authenticated;

drop policy if exists "users read own retention profile" on public.retention_profiles;
create policy "users read own retention profile" on public.retention_profiles
  for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists "users insert own retention profile" on public.retention_profiles;
create policy "users insert own retention profile" on public.retention_profiles
  for insert to authenticated with check (user_id = (select auth.uid()));
drop policy if exists "users update own retention profile" on public.retention_profiles;
create policy "users update own retention profile" on public.retention_profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- Push devices (APNs tokens). Registered through RPCs so a token that moves
-- between accounts on the same phone is reassigned instead of rejected.
-- ---------------------------------------------------------------------------
create table if not exists public.push_devices (
  token text primary key check (length(token) between 32 and 512),
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'ios' check (platform in ('ios', 'android')),
  environment text not null default 'production' check (environment in ('sandbox', 'production')),
  bundle_id text not null default '',
  app_version text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_devices_user_id_idx on public.push_devices(user_id);

alter table public.push_devices enable row level security;
revoke all on table public.push_devices from public, anon, authenticated;
grant select on table public.push_devices to authenticated;
drop policy if exists "users read own push devices" on public.push_devices;
create policy "users read own push devices" on public.push_devices
  for select to authenticated using (user_id = (select auth.uid()));

create or replace function public.register_push_device(
  p_token text,
  p_platform text,
  p_environment text,
  p_bundle_id text,
  p_app_version text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) not between 32 and 512 or p_token !~ '^[0-9A-Za-z:_-]+$' then
    raise exception 'invalid push token' using errcode = '22023';
  end if;

  insert into public.push_devices (token, user_id, platform, environment, bundle_id, app_version, updated_at)
  values (
    p_token,
    auth.uid(),
    case when p_platform = 'android' then 'android' else 'ios' end,
    case when p_environment = 'sandbox' then 'sandbox' else 'production' end,
    left(coalesce(p_bundle_id, ''), 200),
    left(coalesce(p_app_version, ''), 40),
    now()
  )
  on conflict (token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        environment = excluded.environment,
        bundle_id = excluded.bundle_id,
        app_version = excluded.app_version,
        updated_at = now();
end;
$$;

create or replace function public.unregister_push_device(p_token text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.push_devices where token = p_token and user_id = auth.uid();
$$;

revoke all on function public.register_push_device(text, text, text, text, text) from public, anon;
revoke all on function public.unregister_push_device(text) from public, anon;
grant execute on function public.register_push_device(text, text, text, text, text) to authenticated;
grant execute on function public.unregister_push_device(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Push outbox (server only) and lifecycle email log (server only)
-- ---------------------------------------------------------------------------
create table if not exists public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('client_viewed', 'client_approved', 'client_changes_requested')),
  data jsonb not null default '{}'::jsonb,
  dedupe_key text not null unique,
  status text not null default 'pending' check (status in ('pending', 'sent', 'skipped', 'failed')),
  variant text,
  send_after timestamptz not null default now(),
  attempts smallint not null default 0,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notification_outbox_pending_idx
  on public.notification_outbox(send_after) where status = 'pending';
alter table public.notification_outbox enable row level security;
revoke all on table public.notification_outbox from public, anon, authenticated;

create table if not exists public.lifecycle_emails (
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('welcome', 'day3_tip', 'trial_ending', 'win_back')),
  sent_at timestamptz not null default now(),
  primary key (user_id, kind)
);
alter table public.lifecycle_emails enable row level security;
revoke all on table public.lifecycle_emails from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Engagement analytics: opt-in rate, push -> open, copy tests
-- ---------------------------------------------------------------------------
create table if not exists public.engagement_events (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  event text not null check (length(event) between 1 and 64),
  properties jsonb not null default '{}'::jsonb check (pg_column_size(properties) <= 2048),
  created_at timestamptz not null default now()
);
create index if not exists engagement_events_event_idx on public.engagement_events(event, created_at);
alter table public.engagement_events enable row level security;
revoke all on table public.engagement_events from public, anon, authenticated;
grant insert (user_id, event, properties) on table public.engagement_events to authenticated;
drop policy if exists "users log own engagement events" on public.engagement_events;
create policy "users log own engagement events" on public.engagement_events
  for insert to authenticated with check (user_id = (select auth.uid()));

-- Read from the SQL editor (not exposed to app users).
create or replace view public.retention_metrics
with (security_invoker = true)
as
with prompts as (
  select
    count(*) filter (where event = 'notification_prompt_shown') as prompts_shown,
    count(*) filter (where event = 'notification_permission' and properties->>'granted' = 'true') as permissions_granted,
    count(*) filter (where event = 'notification_permission') as permission_answers
  from public.engagement_events
  where created_at > now() - interval '30 days'
),
opens as (
  select properties->>'category' as category, coalesce(properties->>'variant', 'a') as variant, count(*) as opens
  from public.engagement_events
  where event = 'notification_open' and created_at > now() - interval '30 days'
  group by 1, 2
),
sends as (
  select coalesce(variant, 'a') as variant, count(*) as sent
  from public.notification_outbox
  where status = 'sent' and sent_at > now() - interval '30 days'
  group by 1
)
select
  'opt_in' as metric, null::text as category, null::text as variant,
  prompts.permissions_granted::numeric as numerator,
  nullif(prompts.permission_answers, 0)::numeric as denominator,
  round(prompts.permissions_granted::numeric / nullif(prompts.permission_answers, 0), 3) as rate
from prompts
union all
select
  'push_open', 'client_activity', sends.variant,
  coalesce(opens.opens, 0)::numeric, sends.sent::numeric,
  round(coalesce(opens.opens, 0)::numeric / nullif(sends.sent, 0), 3)
from sends
left join opens on opens.category = 'client_activity' and opens.variant = sends.variant
union all
select 'local_reminder_opens', opens.category, opens.variant, opens.opens::numeric, null, null
from opens
where opens.category <> 'client_activity';
revoke all on public.retention_metrics from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Private settings shared with the edge function
-- ---------------------------------------------------------------------------
create schema if not exists retention_private;
revoke all on schema retention_private from public, anon, authenticated;

create table if not exists retention_private.settings (
  key text primary key,
  value text not null
);
revoke all on table retention_private.settings from public, anon, authenticated;

insert into retention_private.settings (key, value) values
  ('dispatch_url', 'https://tuykoxmpnmrawrknjikr.supabase.co/functions/v1/retention-dispatch'),
  ('dispatch_secret', encode(extensions.gen_random_bytes(32), 'hex')),
  ('unsubscribe_secret', encode(extensions.gen_random_bytes(32), 'hex'))
on conflict (key) do nothing;

-- Only the edge function (service role) can read the secrets.
create or replace function public.retention_dispatch_config()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_object_agg(key, value)
  from retention_private.settings
  where key in ('dispatch_secret', 'unsubscribe_secret');
$$;
revoke all on function public.retention_dispatch_config() from public, anon, authenticated;
grant execute on function public.retention_dispatch_config() to service_role;

-- Users the lifecycle email sweep should look at, with their email address.
create or replace function public.retention_email_candidates(p_limit integer default 200)
returns table (
  user_id uuid,
  email text,
  signed_up_at timestamptz,
  language text,
  timezone text,
  email_opt_in boolean,
  trial_started_at timestamptz,
  last_active_at timestamptz,
  sent_kinds text[]
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    profile.user_id,
    account.email::text,
    account.created_at,
    profile.language,
    profile.timezone,
    profile.email_opt_in,
    profile.trial_started_at,
    profile.last_active_at,
    coalesce(
      (select array_agg(sent.kind) from public.lifecycle_emails sent where sent.user_id = profile.user_id),
      '{}'::text[]
    )
  from public.retention_profiles profile
  join auth.users account on account.id = profile.user_id
  where account.email is not null
    and account.deleted_at is null
    and (
      account.created_at > now() - interval '10 days'
      or (profile.trial_started_at is not null and profile.trial_started_at > now() - interval '10 days')
      or profile.last_active_at < now() - interval '21 days'
    )
  order by profile.last_active_at
  limit least(greatest(coalesce(p_limit, 200), 1), 500);
$$;
revoke all on function public.retention_email_candidates(integer) from public, anon, authenticated;
grant execute on function public.retention_email_candidates(integer) to service_role;

-- Calls the dispatcher. Never raises: a failed call is retried by the cron job.
create or replace function public.retention_kick()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_url text;
  secret text;
begin
  select value into target_url from retention_private.settings where key = 'dispatch_url';
  select value into secret from retention_private.settings where key = 'dispatch_secret';
  if target_url is null or secret is null then
    return;
  end if;
  perform net.http_post(
    url := target_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-retention-secret', secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
exception when others then
  null;
end;
$$;
revoke all on function public.retention_kick() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Client activity -> push for everyone in the contractor's organization
-- ---------------------------------------------------------------------------
create or replace function public.enqueue_estimate_activity_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status
     or new.status not in ('viewed', 'approved', 'changes_requested') then
    return new;
  end if;

  begin
    insert into public.notification_outbox (user_id, kind, data, dedupe_key)
    select
      member.user_id,
      'client_' || new.status,
      jsonb_build_object(
        'estimate_number', coalesce(new.snapshot->'estimate'->>'number', ''),
        'approved_by', coalesce(new.approved_by, ''),
        'project_id', new.project_id
      ),
      new.id::text || ':' || new.status || ':' || member.user_id::text
    from public.organization_members member
    where member.organization_id = new.organization_id
    on conflict (dedupe_key) do nothing;

    perform public.retention_kick();
  exception when others then
    -- Notifications must never block a client approving an estimate.
    null;
  end;
  return new;
end;
$$;
revoke all on function public.enqueue_estimate_activity_push() from public, anon, authenticated;

drop trigger if exists estimate_share_links_activity_push on public.estimate_share_links;
create trigger estimate_share_links_activity_push
  after update of status on public.estimate_share_links
  for each row
  execute function public.enqueue_estimate_activity_push();

-- ---------------------------------------------------------------------------
-- Schedule: deliver delayed pushes (quiet hours) and lifecycle email
-- ---------------------------------------------------------------------------
do $$
begin
  perform cron.unschedule('retention-dispatch')
  where exists (select 1 from cron.job where jobname = 'retention-dispatch');
  perform cron.schedule('retention-dispatch', '*/10 * * * *', 'select public.retention_kick();');
end;
$$;
