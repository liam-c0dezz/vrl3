-- Materialize the indexed nearest-neighbor scan BEFORE catalog freshness checks.
-- Joining the full catalog first caused the planner to sort every full vector.
create or replace function public.smart_service_apache_search(p_embedding extensions.vector(3072))
returns table(id bigint,similarity double precision)
language sql stable security invoker set search_path='' as $$
 with nearest as materialized (
   select e.catalog_id,e.embedding,e.source_text
   from public.smart_service_apache_embeddings e
   order by e.embedding::extensions.halfvec(3072) operator(extensions.<=>) p_embedding::extensions.halfvec(3072)
   limit 40
 )
 select n.catalog_id,1-(n.embedding operator(extensions.<=>) p_embedding)
 from nearest n join public.estimator_cost_items c on c.id=n.catalog_id
 where c.catalog_version='repair-2026-q3'
   and n.source_text=public.smart_service_apache_source_text(c)
 order by n.embedding operator(extensions.<=>) p_embedding
 limit 10;
$$;
revoke all on function public.smart_service_apache_search(extensions.vector) from public,anon,authenticated;
grant execute on function public.smart_service_apache_search(extensions.vector) to service_role;
