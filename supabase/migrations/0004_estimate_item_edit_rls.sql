-- Auth ownership + RLS for estimates and editable estimate line items.
-- Run once in the Supabase SQL editor before using the authenticated app.

alter table public.estimates
  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.estimate_items
  add column if not exists user_id uuid references auth.users(id) on delete cascade;

create index if not exists estimates_user_id_idx on public.estimates(user_id);
create index if not exists estimate_items_user_id_idx on public.estimate_items(user_id);

-- Preserve legacy data for the existing single-user app.
update public.estimates
set user_id = (select id from auth.users order by created_at limit 1)
where user_id is null and exists (select 1 from auth.users);

update public.estimate_items i
set user_id = coalesce(
  (select e.user_id from public.estimates e where e.id = i.estimate_id),
  (select id from auth.users order by created_at limit 1)
)
where i.user_id is null and exists (select 1 from auth.users);

-- If no account exists yet, the first signup receives legacy unowned rows.
create or replace function public.assign_legacy_estimates_to_first_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.estimates where user_id is not null) then
    update public.estimates set user_id = new.id where user_id is null;
    update public.estimate_items i
      set user_id = coalesce(
        (select e.user_id from public.estimates e where e.id = i.estimate_id),
        new.id
      )
      where i.user_id is null;
  end if;
  return new;
end;
$$;

drop trigger if exists assign_legacy_estimates_after_signup on auth.users;
create trigger assign_legacy_estimates_after_signup
  after insert on auth.users
  for each row execute function public.assign_legacy_estimates_to_first_user();

alter table public.estimates enable row level security;
alter table public.estimate_items enable row level security;

revoke all on table public.estimates from anon;
revoke all on table public.estimate_items from anon;
grant select on table public.estimates to authenticated;
grant select on table public.estimate_items to authenticated;
grant update (name, quantity, unit_price, total, description)
  on table public.estimate_items to authenticated;

drop policy if exists "anon can edit estimate item fields" on public.estimate_items;
drop policy if exists "users can view own estimates" on public.estimates;
drop policy if exists "users can view own estimate items" on public.estimate_items;
drop policy if exists "users can edit own estimate items" on public.estimate_items;
drop policy if exists "estimate owner guard" on public.estimates;
drop policy if exists "estimate item owner guard" on public.estimate_items;

create policy "users can view own estimates"
  on public.estimates for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users can view own estimate items"
  on public.estimate_items for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "users can edit own estimate items"
  on public.estimate_items for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Restrictive guards prevent older permissive policies from widening access.
create policy "estimate owner guard"
  on public.estimates as restrictive for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "estimate item owner guard"
  on public.estimate_items as restrictive for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
