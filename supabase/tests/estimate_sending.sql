-- Run in a transaction against a migrated database. All fixture changes roll back.
begin;
do $$
declare
  target uuid;
  project uuid;
  member uuid;
  first_link jsonb;
  replacement jsonb;
  current_status text;
  snapshot jsonb;
begin
  select e.id, e.project_id, m.user_id into target, project, member
    from public.estimates e join public.organization_members m using (organization_id)
    where e.project_id is not null limit 1;
  if target is null then raise exception 'Test needs one saved estimate and organization member'; end if;
  perform set_config('request.jwt.claim.sub', member::text, true);
  update public.estimates set status = 'Draft', appearance = '{"accent":"green","businessName":"Test Builders"}' where id = target;
  update public.projects set status = 'Draft' where id = project;
  first_link := public.create_estimate_share_link(target);
  select status into current_status from public.estimates where id = target;
  assert current_status = 'Draft', 'Preparing must not mark an estimate sent';
  select status into current_status from public.projects where id = project;
  assert current_status = 'Draft', 'Preparing must not mark a project sent';
  select status into current_status from public.estimate_share_links where id = (first_link->>'share_id')::uuid;
  assert current_status = 'prepared', 'New links must start prepared';
  perform public.confirm_estimate_share_sent(first_link->>'token');
  select status into current_status from public.estimates where id = target;
  assert current_status = 'Sent', 'A successful composer result must mark sent';
  replacement := public.create_estimate_share_link(target);
  select status into current_status from public.estimate_share_links where id = (first_link->>'share_id')::uuid;
  assert current_status = 'sent', 'Canceling a resend must preserve the delivered link';
  perform public.confirm_estimate_share_sent(replacement->>'token');
  select status into current_status from public.estimate_share_links where id = (first_link->>'share_id')::uuid;
  assert current_status = 'revoked', 'Successful resend replaces the previous link';
  snapshot := public.get_public_estimate(replacement->>'token');
  assert snapshot#>>'{estimate,appearance,accent}' = 'green', 'Portal must use saved accent';
  assert snapshot#>>'{estimate,appearance,businessName}' = 'Test Builders', 'Portal must use saved business name';
  perform public.approve_public_estimate(replacement->>'token', 'Test Client');
  perform public.confirm_estimate_share_sent(replacement->>'token');
  select status into current_status from public.estimates where id = target;
  assert current_status = 'Approved', 'Retrying confirmation must not overwrite approval';
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.confirm_estimate_share_sent(replacement->>'token');
    raise exception 'Unauthenticated confirmation unexpectedly succeeded';
  exception when raise_exception then
    if sqlerrm = 'Unauthenticated confirmation unexpectedly succeeded' then raise; end if;
  end;
end;
$$;
rollback;
