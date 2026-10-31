# Smart Service Apache

Direct port of DataDrivenConstruction OpenConstructionEstimate-DDC-CWICR, pinned to commit `e9e23fbab91014c8537b054d8f625c6f390fcf08`. The user's latest direction explicitly supersedes the original restrictions against DDC's scope expansion and estimated quantities. No prior Smart Service estimator implementation is imported.

## Upstream code

Twelve original text-workflow JavaScript node bodies are copied unchanged into `supabase/functions/smart-service-apache/ddc-nodes.js`. Small ordinary JavaScript bindings replace n8n's input/context access. There is no n8n runtime or hosted n8n dependency. `node-manifest.json` records their SHA-256 hashes. The original Apache code and notices are under `third_party/ddc-openconstructionestimate`. The iOS bundle includes the license and NOTICE.

Preserved: comprehensive scope generation, realistic inferred quantities, missing-quantity default of 1, query expansion, original-plus-ten-new-words query combination, text-embedding-3-large at 3072 dimensions, ten search candidates, five candidates shown in the rerank prompt, 70% LLM / 30% vector scoring, original fallback and quality classifications, original resource calculations and final aggregation rounding. The copied matcher may choose a weak match; it does not use the custom 85% rejection threshold from the discarded draft.

## Integration adaptations

- Qdrant search becomes a Supabase cosine search with the same top-10 interface. A halfvec HNSW index retrieves 40 candidates, then full-precision vectors rerank to ten. This is approximate retrieval and cannot guarantee identical Qdrant neighbors.
- Only the existing `repair-2026-q3` catalog is indexed. No DDC data or vector snapshots are imported.
- A catalog adapter supplies DDC `rate_code`, `rate_name`, `rate_unit`, `cost_summary`, and resources from real database rows. Fields named `resource_cost_eur` are retained for compatibility, but contain USD values; there is no currency conversion.
- The selected row is fetched again before calculation. IDs, descriptions and prices come from the database. Model-generated scope names remain separate from authoritative catalog descriptions.
- Because DDC's parser uses metric units, explicit unit conversion maps quantities to the selected US catalog unit. Incompatible dimensions return `UNIT_MISMATCH` instead of multiplying square metres by an each price. A missing real candidate returns `NO_MATCH`.
- Upstream `chatgpt-4o-latest` was removed from OpenAI's API. `gpt-4o` replaces it. `gpt-4o-mini`, temperatures and embedding model remain upstream defaults. Environment overrides: APACHE_PARSE_MODEL and APACHE_RERANK_MODEL.
- Photos use DDC's STAGE 1 survey prompt (including upstream dimension estimates), then the same text pipeline. Photos do not set catalog prices.
- Existing app authentication, project membership, AI consent and usage reservations protect the new endpoint. They do not modify estimating logic. Request IDs are bound to user, project and input hash.
- Explicit request markup defaults to 0. No old pricing settings, profit margin, contingency or hourly-rate overrides are applied.
- Administrative `index` and `evaluate` operations require a server credential, verified by Supabase and the server-only table grants. They cannot be called with a normal user or anonymous token. They do not save customer estimates.
- Up to 60 work items and three bounded JPEG/PNG images per request. Whitespace streaming prevents gateway idle timeout. Overall processing deadline is 350 seconds.

## Deployment

Supabase project: `tuykoxmpnmrawrknjikr` (AI estimator).
Endpoint: `/functions/v1/smart-service-apache`, JWT verification enabled.
Deployed edge version: **4**, SHA-256 `5904b0746d62415ddbc59a8b75abf3a31ce9f74a3dc8f873e9af9a611e9d5b82`.

Deployed migrations:
- `20261001034640_smart_service_apache.sql`: schema, privileges and initial retrieval.
- `20261001041827_smart_service_apache_indexed_search.sql`: materializes the nearest-neighbor scan before joining the catalog. EXPLAIN confirms use of the HNSW index; this fixes the initial live search timeout.

New tables: `smart_service_apache_embeddings`, `smart_service_apache_requests`.
New functions: `smart_service_apache_source_text`, `smart_service_apache_pending`, `smart_service_apache_search`.
New indexes: `smart_service_apache_embedding_hnsw`, `smart_service_apache_requests_user_idx`, `smart_service_apache_requests_project_idx`.
Extension enabled: `vector` in `extensions`.

The estimator refuses to run until every catalog row is indexed and current. Re-run the administrative index operation after changes to descriptions/categories/units/actions or new rows. Price changes are reflected immediately without re-embedding.

The existing `smart-service`, `smart-service-v7`, catalog schema and pricing rows are not modified. The app's existing chat endpoint remains unchanged. A separate project Estimate-tab button opens the Apache preview; it does not save to the project's estimate history or replace an existing estimate.

## Request

```json
{"operation":"estimate","request_id":"NEW-UUID","project_id":"ACCESSIBLE-PROJECT-UUID","scope":"Remodel a 5 x 8 ft bathroom...","photos":[],"markup_percent":10}
```

Use the signed-in user's bearer token and the app publishable key. Response includes `items`, `unresolved`, `subtotal`, `markup_amount`, `total`, `parsed_works`, `audit`, and `ddc_aggregate`. Streamed runtime failures return an `error` field; callers must check it even with HTTP 200.

## Verification

- Type check passed.
- Eight local tests passed, covering upstream defaults, weighting, malformed-response fallback, empty results, real-price calculation, unit conversion, invalid numbers and aggregation.
- All twelve copied node bodies match their upstream SHA-256 hashes.
- Live database checks confirm anonymous/authenticated users cannot read the embedding table or call the search function; service role can.
- Security advisor's no-policy INFO notices for the new tables are intentional: these are server-only tables with client privileges revoked. No new SECURITY DEFINER function was introduced. Other reported warnings concern existing functions and were left untouched.
- The user explicitly approved OpenAI catalog indexing. No catalog prices or customer details are part of the embedding text.
- Indexing completed: 12,107 rows, text-embedding-3-large, 3,072 dimensions. Pending index rows: **0**. All four live remodeling tests completed.
- Swift syntax check passed. Full iOS build failed before app compilation because the Mac ran out of disk space while building the Superscript dependency. The 618 MB temporary build folder was removed. Signed-in iOS flow remains unverified.


## Live results and remaining gaps

These are single live runs with **explicit 10% markup**. “Complete” means the pipeline returned all parsed work items; it does not certify the scope-to-catalog matches. Every returned ID, description, unit and price was checked against the actual catalog, and all returned line calculations and totals passed deterministic checks.

| Test | Parsed / priced | Status | Subtotal USD | Total with 10% | Time |
|---|---:|---|---:|---:|---:|
| Bathroom | 7 / 7 | Complete | 3,431.67 | 3,774.84 | 24 s |
| Carpet removal + LVP | 2 / 1 | Partial | 40.67 | 44.74 | 9 s |
| Kitchen | 4 / 3 | Partial | 1,654.11 | 1,819.52 | 15 s |
| Bundled bathroom photo: replace toilet | 2 / 2 | Complete | 372.50 | 409.75 | 19 s |

**The copied workflow has material matching problems and these results are not ready to use as reliable quotes.** Real database prices can still be attached to the wrong work:

- Bathroom: bathtub replacement selected row **929**, detach/reset bathtub, at **$356/Ea**. Vanity replacement selected row **5820**, in the demolition category, at **$102/Ea**. Other selections included ceramic floor row 4641 at $12.93/SF, ceramic wall row 4670 at $22.90/SF and toilet row 14376 at $992/Ea. The upstream metric parser also turned 40 SF into 3.72 m², then 40.0417 SF after conversion.
- Flooring: carpet removal selected row **2722**, pad demolition, at **$1.22/SY**, with LLM score 0. LVP selected a glulam ledger candidate, row **10178**, priced by LF; the unit adapter returned `UNIT_MISMATCH`, so no LVP price was charged. A catalog description/category search for “luxury vinyl” or “vinyl plank” returned zero rows; this does not rule out differently named entries.
- Kitchen: laminate countertop work selected row **9226**, a glulam beam item, at **$1.89/SF**, with LLM score 0. Sink work selected plumbing rough-in row **13833**, at **$1,453/Ea**. Base cabinet work selected an each-priced corner cabinet, row **1022**, and returned `UNIT_MISMATCH` for the requested length. Wall paint used row 12030 at $0.72/SF.
- Photo: the approved bundled bathroom image went through the DDC survey and catalog pipeline. Toilet demolition selected row **14364** at **$34.50/Ea** and toilet installation selected row **14384** at **$338/Ea**, one each. Both matched the intended toilet work.

The original reranker shows five candidates to the LLM but scores ten candidates, and its fallback can select an unranked candidate using its vector score. This behavior, scope expansion and inferred quantities remain unchanged to honor the requested direct copy. No custom rejection threshold or old Smart Service logic was added. Improving semantic matching would require a separately chosen change to the copied workflow or catalog coverage.

Missing, anonymous and invalid credentials returned HTTP 401 in live tests. Normal users cannot access the administrative indexing route or server-only catalog search. The authenticated iOS end-to-end flow is still unverified because the full build ran out of disk space before app compilation. The new screen is a preview and does not persist results to project estimate history.

## Exact task file inventory

Paths below are relative to the existing app repository, `/Users/jackgozigian/Developer/CURRENT - Construction Estimate`.

Added:
- `supabase/functions/smart-service-apache/ddc-nodes.js` — twelve unchanged upstream node bodies and runtime bindings.
- `supabase/functions/smart-service-apache/catalog.ts` — real-catalog payload and unit adapter.
- `supabase/functions/smart-service-apache/engine.ts` — DDC pipeline orchestration, authoritative price fetch, markup and audit output.
- `supabase/functions/smart-service-apache/index.ts` — endpoint, authentication, request binding, index administration and streaming.
- `supabase/functions/smart-service-apache/vision-prompt.ts` — adapted DDC photo survey prompt.
- `supabase/functions/smart-service-apache/deno.json` — runtime configuration.
- `supabase/functions/smart-service-apache/engine.test.ts` — eight unit tests.
- `supabase/migrations/20261001034640_smart_service_apache.sql`.
- `supabase/migrations/20261001041827_smart_service_apache_indexed_search.sql`.
- `Construction Estimate/SmartServiceApacheView.swift` — separate scope/photo/markup preview screen.
- `Construction Estimate/ApacheEstimator-LICENSE.txt`.
- `Construction Estimate/ApacheEstimator-NOTICE.txt`.
- `third_party/ddc-openconstructionestimate/LICENSE-CODE.txt`.
- `third_party/ddc-openconstructionestimate/NOTICE`.
- `third_party/ddc-openconstructionestimate/node-manifest.json`.
- `third_party/ddc-openconstructionestimate/upstream-code-nodes.json`.
- `scripts/smart_service_apache.py` — reusable index/evaluate administrator helper using environment credentials.
- `docs/SMART_SERVICE_APACHE.md` — this implementation record.

Changed:
- `Construction Estimate/ProjectDetailView.swift` — separate Apache button, presentation state and sheet. Existing Smart Service routing is preserved.

The repository already contained many unrelated modifications. They were not reverted or included as this task's changes. No commit or app-store release was made. Existing deployed `smart-service` version 78 and `smart-service-v7` version 19 were verified unchanged; both retain code SHA `81716ce39a5633df16c549a1f59b8f1bf62036c2e00ef61116ffd6f425ba3dea`.

## Source references

- [Pinned upstream source](https://github.com/datadrivenconstruction/OpenConstructionEstimate-DDC-CWICR/tree/e9e23fbab91014c8537b054d8f625c6f390fcf08): code/workflow provenance. Apache code license and upstream NOTICE are preserved; modified wrappers/adapters are identified in their headers. No noncommercial DDC cost data was imported.
- [OpenAI deprecations](https://developers.openai.com/api/docs/deprecations): retired upstream model replacement.
- [Supabase vector indexes](https://supabase.com/docs/guides/ai/vector-indexes): vector search implementation.
