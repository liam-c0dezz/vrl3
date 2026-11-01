
alter policy "members can read business assets"
  on storage.objects
  using (
    bucket_id = 'business-assets'
    and lower((storage.foldername(name))[1])
      = (select public.current_organization_id())::text
  );

alter policy "members can insert business assets"
  on storage.objects
  with check (
    bucket_id = 'business-assets'
    and lower((storage.foldername(name))[1])
      = (select public.current_organization_id())::text
  );

alter policy "members can update business assets"
  on storage.objects
  using (
    bucket_id = 'business-assets'
    and lower((storage.foldername(name))[1])
      = (select public.current_organization_id())::text
  )
  with check (
    bucket_id = 'business-assets'
    and lower((storage.foldername(name))[1])
      = (select public.current_organization_id())::text
  );

alter policy "members can delete business assets"
  on storage.objects
  using (
    bucket_id = 'business-assets'
    and lower((storage.foldername(name))[1])
      = (select public.current_organization_id())::text
  );
;
