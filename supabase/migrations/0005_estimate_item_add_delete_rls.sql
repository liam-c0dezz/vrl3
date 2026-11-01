-- Allow authenticated users to ADD and DELETE their own estimate line items.
-- Complements 0004 (which only granted SELECT + UPDATE). Without this, the
-- estimate card's "+" (add) and trash (delete category) buttons are blocked
-- by RLS. Run once in the Supabase SQL editor.

-- Auto-populate ownership on insert so the client never has to send user_id
-- (and so the restrictive owner guard's WITH CHECK passes).
alter table public.estimate_items
  alter column user_id set default auth.uid();

grant insert on table public.estimate_items to authenticated;
grant delete on table public.estimate_items to authenticated;

drop policy if exists "users can add own estimate items" on public.estimate_items;
drop policy if exists "users can delete own estimate items" on public.estimate_items;

create policy "users can add own estimate items"
  on public.estimate_items for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "users can delete own estimate items"
  on public.estimate_items for delete to authenticated
  using ((select auth.uid()) = user_id);
