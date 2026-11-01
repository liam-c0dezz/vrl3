-- Separate DDC retrieval adapter; existing Smart Service objects are unchanged.
create extension if not exists vector with schema extensions;
create table public.smart_service_apache_embeddings (
  catalog_id bigint primary key references public.estimator_cost_items(id) on delete cascade,
  source_text text not null,
  model text not null check (model = 'text-embedding-3-large'),
  embedding extensions.vector(3072) not null,
  updated_at timestamptz not null default now()
);
alter table public.smart_service_apache_embeddings enable row level security;
revoke all on public.smart_service_apache_embeddings from public, anon, authenticated;
grant select, insert, update, delete on public.smart_service_apache_embeddings to service_role;
-- half precision index supports 3072 dimensions; retain full precision for reranking.
create index smart_service_apache_embedding_hnsw on public.smart_service_apache_embeddings
using hnsw ((embedding::extensions.halfvec(3072)) extensions.halfvec_cosine_ops);

create function public.smart_service_apache_source_text(c public.estimator_cost_items)
returns text language sql immutable security invoker set search_path='' as $$
 select c.category || E'\n' || c.description || E'\nUnit: ' || c.unit || E'\nAction: ' || c.action;
$$;
revoke all on function public.smart_service_apache_source_text(public.estimator_cost_items) from public,anon,authenticated;
grant execute on function public.smart_service_apache_source_text(public.estimator_cost_items) to service_role;

create function public.smart_service_apache_pending(p_limit integer default 64)
returns table(catalog_id bigint,source_text text) language sql stable security invoker set search_path='' as $$
 select c.id, public.smart_service_apache_source_text(c)
 from public.estimator_cost_items c left join public.smart_service_apache_embeddings e on e.catalog_id=c.id
 where c.catalog_version='repair-2026-q3' and (e.catalog_id is null or e.source_text<>public.smart_service_apache_source_text(c))
 order by c.id limit greatest(1,least(p_limit,128));
$$;
revoke all on function public.smart_service_apache_pending(integer) from public,anon,authenticated;
grant execute on function public.smart_service_apache_pending(integer) to service_role;

create function public.smart_service_apache_search(p_embedding extensions.vector(3072))
returns table(id bigint,similarity double precision) language sql stable security invoker set search_path='' as $$
 with nearest as materialized (
 select e.catalog_id,e.embedding from public.smart_service_apache_embeddings e
 join public.estimator_cost_items c on c.id=e.catalog_id
 where c.catalog_version='repair-2026-q3' and e.source_text=public.smart_service_apache_source_text(c)
 order by e.embedding::extensions.halfvec(3072) operator(extensions.<=>) p_embedding::extensions.halfvec(3072)
 limit 40
 )
 select n.catalog_id, 1-(n.embedding operator(extensions.<=>) p_embedding)
 from nearest n order by n.embedding operator(extensions.<=>) p_embedding limit 10;
$$;
revoke all on function public.smart_service_apache_search(extensions.vector) from public,anon,authenticated;
grant execute on function public.smart_service_apache_search(extensions.vector) to service_role;

create table public.smart_service_apache_requests (
 request_id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 input_hash text not null,
 created_at timestamptz not null default now()
);
create index smart_service_apache_requests_user_idx on public.smart_service_apache_requests(user_id);
create index smart_service_apache_requests_project_idx on public.smart_service_apache_requests(project_id);
alter table public.smart_service_apache_requests enable row level security;
revoke all on public.smart_service_apache_requests from public,anon,authenticated;
grant select,insert on public.smart_service_apache_requests to service_role;
