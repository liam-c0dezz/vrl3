import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { buildCustomerDescription, appEstimate, appQuestions } from './app-adapter.ts';
import { families } from './whole-project.ts';
import { pricePlan, sourceId } from './residential-estimator.ts';
const user='00000000-0000-4000-8000-000000000001', project='00000000-0000-4000-8000-000000000002', request='00000000-0000-4000-8000-000000000003';
const description='Remove 100 SF acoustical ceiling tile only in kitchen. Small-volume work.';
const plan=()=>({summary:'Ceiling tile removal',items:[{id:'demo',category:'Demolition',description:'Remove acoustical ceiling tile only',location:'kitchen ceiling',certainty:'stated',evidence:'Remove 100 SF acoustical ceiling tile only',quantity:{method:'direct',basis:'stated',measurements:[{value:100,unit:'SF',evidence:'100 SF'}],explanation:'Measured area'},catalogId:sourceId(3),matchReason:'Tile-only demolition, small volume'}],questions:[],assumptions:[],exclusions:['Grid removal'],reviewItems:[],conflicts:[]});
const report=()=>pricePlan({description,plan:plan()});
test('app response arithmetic, sources and short job title',()=>{const e=appEstimate(report(),0,0,'Ceiling Tile Removal');assert.equal(e.total,77);assert.equal(e.categories[0].items[0].unitPrice,.77);assert.equal(e.title,'Ceiling Tile Removal');assert.match(e.notes,/not applied/);assert.equal(e.pricing.projectTotal,null);});
test('only explicit markup and contingency apply',()=>{const e=appEstimate(report(),20,10);assert.equal(e.markupAmount,15.4);assert.equal(e.contingencyAmount,7.7);assert.equal(e.total,100.1);});
test('partial estimates cannot become false complete totals',()=>{const p=plan();p.items[0].catalogId=null;assert.throws(()=>appEstimate(pricePlan({description,plan:p})));});
test('conflicts block persisted estimate',()=>{const p=plan();p.conflicts=['100 or 200 SF'];assert.throws(()=>appEstimate(pricePlan({description,plan:p})));});
test('questions use app-compatible response schema and revision IDs',()=>{const p=plan();p.items[0].catalogId=null;p.questions=['What is the measured area?'];const q=appQuestions(pricePlan({description,plan:p}),project,2);assert(q.length>0&&q.length<=3);assert.equal(q[0].response_type,'text');assert.match(q[0].id,/:r2:q1$/);assert.deepEqual(q[0].options,[]);});
test('assistant statements never become measurement evidence',()=>{const r=buildCustomerDescription([{role:'user',content:'Paint walls'},{role:'assistant',content:'Assume 500 SF'}],null);assert.equal(r.description,'Paint walls');});
const draft=()=>({id:project,title:'Test',scope_text:'Paint walls',status:'awaiting_answers',revision:1,plan:{engine:'residential-estimator-2026-09-25'},questions:[{id:'q1',question:'Measured wall area?',response_type:'text',help_text:'',options:[]}],answers:{}});
test('answers are mapped only to stored questions',()=>{const r=buildCustomerDescription([],draft(),[{question_id:'q1',text:'500 SF'}]);assert.match(r.description,/Measured wall area/);assert.match(r.description,/500 SF/);});
test('forged and obsolete question IDs rejected',()=>assert.throws(()=>buildCustomerDescription([],draft(),[{question_id:'wrong',text:'500 SF'}])));
test('choice IDs cannot masquerade as free text',()=>assert.throws(()=>buildCustomerDescription([],draft(),[{question_id:'q1',option_id:'unoffered'}])));
test('scope history does not grow by duplicating prior messages',()=>{const d=draft();d.scope_text='Paint walls\n\n500 SF';const r=buildCustomerDescription([{role:'user',content:'Paint walls'},{role:'user',content:'500 SF'},{role:'user',content:'Two coats'}],d);assert.equal(r.scopeText,'Paint walls\n\n500 SF\n\nTwo coats');});
test('long customer history fails clearly instead of truncating',()=>assert.throws(()=>buildCustomerDescription([{role:'user',content:'x'.repeat(12001)}],null)));

// Run the actual handler with its external client import replaced by a local mock.
// All other production code, validation, provider JSON and app adapter are unchanged.
const source=await readFile(new URL('./index.ts', import.meta.url),'utf8');
await writeFile(new URL('./index.mock.ts', import.meta.url),source.replace('import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";', 'const createClient = (...args: unknown[]) => (globalThis as any).__mockCreateClient(...args);'));
const env={SUPABASE_URL:'https://mock.invalid',SUPABASE_SERVICE_ROLE_KEY:'offline-service-placeholder',SUPABASE_ANON_KEY:'offline-public-placeholder',OPENAI_API_KEY:'offline-ai-placeholder'};
globalThis.Deno={env:{get:k=>env[k]},serve:()=>{}};
const {handler}=await import('./index.mock.ts');
let calls, settings, modelCalls, lastSave, lastDraft;
function setup(override={}){
  settings={authorized:true,member:true,consent:true,reservation:'granted',draft:null,...override};calls=[];modelCalls=0;lastSave=null;lastDraft=null;
  globalThis.__mockCreateClient=()=>({
    auth:{getUser:async()=>({data:{user:settings.authorized?{id:user}:null},error:null})},
    from(table){let mutation=null;const q={select(){return q},eq(){return q},in(){return q},insert(value){mutation=value;return q},update(value){mutation=value;return q},
      async maybeSingle(){calls.push(table);if(table==='projects')return {data:{id:project,organization_id:project},error:null};if(table==='organization_members')return {data:settings.member?{user_id:user}:null,error:null};if(table==='smart_service_drafts'){if(mutation){lastDraft=mutation;return {data:{id:mutation.id},error:null};}return {data:settings.draft,error:null};}return {data:null,error:null};},
      async single(){return q.maybeSingle()},then(resolve,reject){return Promise.resolve({data:settings.rates??[],error:null}).then(resolve,reject)}};return q;},
    async rpc(name,args){calls.push(name);if(name==='reserve_ai_request')return {data:{state:settings.reservation,max_output_tokens:2000,response:settings.cached},error:null};
      if(name==='has_current_ai_consent')return {data:settings.consent,error:null};
      if(name==='complete_ai_request'||name==='fail_ai_request')return {data:true,error:null};
      if(name==='residential_estimator_save_draft'){lastSave=args;return {data:{...args.p_response,estimate_id:request},error:null};}
      throw new Error('Unexpected RPC '+name);}
  });
  globalThis.fetch=async(url,init)=>{
    assert.equal(url,'https://api.openai.com/v1/responses');const body=JSON.parse(init.body);modelCalls++;
    assert.equal(body.store,false);assert.equal(body.max_output_tokens,body.text.format.name === "estimate_job_plan" ? 27000 : ["whole_plan","whole_review"].includes(body.text.format.name) ? 30000 : 12000);assert.equal(body.model,"gpt-6-luna");assert.equal(body.reasoning.effort,"low");assert(init.signal instanceof AbortSignal);
    const name=body.text.format.name;
    if(name==='whole_discovery'){assert.equal(body.text.format.schema.properties.families.minItems,1);assert.equal(body.text.format.schema.properties.families.items.type,'integer');assert.equal(body.text.format.schema.properties.families.items.maximum,families().length-1);}
    let value;
    if(name==='whole_discovery')value={title:'Ceiling Tile Removal',summary:'Remove ceiling tiles',facts:[description],requirements:settings.wholePlan?settings.wholePlan.coverage.map(c=>c.requirement):['Remove tiles'],assumptions:[],families:settings.wholePlan?[...new Set(settings.wholePlan.components.map(c=>families().findIndex(f=>f.rows.includes(c.row))))]:[families().findIndex(f=>f.rows.includes(3))],workPackages:['Demolition']};
    else if((name==='whole_plan'||name==='whole_review'))value=settings.wholePlan??{title:'Ceiling Tile Removal',summary:'Remove ceiling tiles',assumptions:[],exclusions:['Grid removal'],components:[{id:'demo',category:'Demolition',name:'Remove ceiling tile',location:'Kitchen ceiling',kind:'catalog',row:3,quantity:100,quantityFormula:null,quantityUnit:'SF',unit:'SF',basis:'stated',rationale:'Tile-only removal'}],unpriced:settings.unmatched?[{name:'Additional unsupported work',reason:'No defensible material source'}]:[],coverage:[{requirement:'Remove tiles',componentIds:['demo'],status:'priced',reason:'Catalog removal'}],review:{quantities:'100 SF stated',inclusions:'No grid',productivity:'Source hours',completeness:'Reviewed'}};
    else if(name==='scope_update'&&settings.richPatch)value=settings.richPatch;
    else if(name==='scope_matches'&&settings.realMatches)value={matches:settings.realMatches.matches.filter(m=>JSON.parse(body.input[0].content[0].text).items.some(i=>i.id===m.id)).map(m=>({quantityOverride:null,...m}))};
    else if(name==='scope_update'){const p=settings.plan??plan();value={title:'Ceiling Tile Removal',summary:p.summary,upsert:p.items.map(i=>({id:i.id,category:i.category,name:i.description,object:'acoustical ceiling tile',action:'remove',location:i.location,instances:{count:1,evidence:''},attributes:[],searchQueries:['acoustical ceiling tile demolition'],evidence:i.evidence,quantity:i.quantity})),removeIds:[],constraints:[],exclusions:p.exclusions,questions:[]};}
    else if(name==='scope_matches')value={matches:[{id:'demo',quantityOverride:null,catalogId:settings.unmatched?null:sourceId(3),reason:'Mock exact match',billing:'quantity',coveredIds:[],broaderQueries:[]}]};
    else if(name==='estimate_job_plan')value={plan_sections:[{title:'Prepare',steps:['Confirm scope','Protect adjacent finishes','Confirm access']},{title:'Perform work',steps:['Remove tiles','Inspect area','Tidy work area']}]};
    else throw new Error('Unexpected schema '+name);
    return new Response(JSON.stringify({status:'completed',output:[{content:[{type:'output_text',text:JSON.stringify(value)}]}]}));
  };
}
const post=(extra={},headers={})=>new Request('https://mock.invalid/estimate',{method:'POST',headers:{authorization:'Bearer offline-user-placeholder','content-type':'application/json',...headers},body:JSON.stringify({request_id:request,project_id:project,messages:[{role:'user',content:description}],...extra})});
test('real handler preserves auth before planning',async()=>{setup({authorized:false});assert.equal((await handler(post())).status,401);assert.equal(modelCalls,0);});
test('real handler rejects absent authorization',async()=>{setup();assert.equal((await handler(post({}, {authorization:''}))).status,401);assert.equal(modelCalls,0);});
test('real handler enforces project membership',async()=>{setup({member:false});assert.equal((await handler(post())).status,403);assert.equal(modelCalls,0);});
test('real handler respects quota',async()=>{setup({reservation:'quota_exceeded'});assert.equal((await handler(post())).status,429);assert.equal(modelCalls,0);});
test('real handler reuses cached request',async()=>{setup({reservation:'cached',cached:{reply:'cached result'}});const r=await handler(post());assert.equal((await r.json()).reply,'cached result');assert.equal(modelCalls,0);});
test('real handler requires consent',async()=>{setup({reservation:'consent_required'});assert.equal((await handler(post())).status,403);assert.equal(modelCalls,0);});
test('real handler rechecks consent before draft saving',async()=>{setup({consent:false});assert.equal((await handler(post())).status,403);assert.equal(lastSave,null);assert.equal(lastDraft,null);});
test('real handler saves complete estimate through atomic RPC',async()=>{setup();const r=await handler(post());const j=await r.json();assert.equal(r.status,200,JSON.stringify(j));assert.equal(j.structured_estimate.total,84.7);assert.equal(j.structured_estimate.markupPercent,10);assert.equal(j.structured_estimate.markupAmount,7.7);assert.equal(j.estimate_id,request);assert.equal(j.stage,3);assert.equal(lastSave.p_items[0].unit_price,.77);assert.equal(lastSave.p_estimate.work_plan.length,3);assert.equal(modelCalls,3);assert(!calls.includes('complete_ai_request'));});
test('missing component saves explicit partial scope without repeated questions',async()=>{setup({unmatched:true});const r=await handler(post());const j=await r.json();assert.equal(r.status,200);assert(lastSave);assert.equal(lastDraft.questions.length,0);assert.equal(lastDraft.status,'ready');assert.match(j.structured_estimate.exclusions.join(' '),/Not included.*unsupported/);assert.equal(j.residential_estimate.status,'partial_priced_scope');assert.equal(j.structured_estimate.pricing.projectTotal,null);});
test('real handler rejects another users missing draft',async()=>{setup();assert.equal((await handler(post({draft_id:project}))).status,409);assert.equal(modelCalls,0);});
test('real handler rejects stale v7 draft contract',async()=>{setup({draft:{...draft(),plan:{scope:{}}}});assert.equal((await handler(post({draft_id:project}))).status,409);assert.equal(modelCalls,0);});
test('real handler replays completed draft without AI or saving again',async()=>{setup({draft:{...draft(),status:'completed',plan:{engine:'residential-estimator-2026-09-25',response:{reply:'saved',estimate_id:request}}}});const r=await handler(post({draft_id:project}));assert.equal((await r.json()).estimate_id,request);assert.equal(modelCalls,0);assert.equal(lastSave,null);});
test('real handler rejects invalid request shape',async()=>{setup();assert.equal((await handler(post({project_id:'invalid'}))).status,400);assert.equal(modelCalls,0);});
test('real handler maintains media validation',async()=>{setup();assert.equal((await handler(post({attachment_kind:'photo',attachment_mime_type:'image/jpeg',attachment_base64:'aGVsbG8='}))).status,400);assert.equal(modelCalls,0);});
test('method and content type validation',async()=>{setup();assert.equal((await handler(new Request('https://mock.invalid'))).status,405);assert.equal((await handler(post({}, {'content-type':'text/plain'}))).status,415);});

const { reasoningOutputBudget } = await import('./model_config.ts');
test('reasoning budget includes output room and is bounded',()=>{assert.equal(reasoningOutputBudget(2000),27000);assert.equal(reasoningOutputBudget(1000000),32000);assert.equal(reasoningOutputBudget(NaN),27000);});

test('follow-up snapshots current facts without replaying obsolete answers or conflicts',()=>{
 const d=draft();d.plan.residentialPlan=plan();d.plan.residentialPlan.conflicts=['Earlier 9 ft, corrected to 7 ft, final 7 ft'];d.scope_text='Original request: height 9 ft';d.answers={old:{question:'Height?',text:'9 ft'}};
 d.questions=[{id:'current',question:'How tall are the walls?',response_type:'text',help_text:'',options:[]}];
 const result=buildCustomerDescription([{role:'user',content:d.scope_text}],d,[{question_id:'current',text:'Use 7 ft'}]);
 assert.match(result.description,/LATEST CUSTOMER ANSWER: Use 7 ft/);assert(!result.description.includes('9 ft'));assert(!result.description.includes('final 7 ft'));assert.match(result.description,/100 SF/);
});
test('repeat answer updates are ordered after older answers',()=>{const d=draft();d.answers={q1:{question:'Measured wall area?',text:'100 SF'},q2:{question:'Other detail?',text:'old'}};const r=buildCustomerDescription([],d,[{question_id:'q1',text:'200 SF'}]);assert.equal(Object.values(r.answers).at(-1).text,'200 SF');assert(!r.description.includes('100 SF'));});
test('already consumed customer messages do not reappear as new corrections',()=>{const d=draft();d.plan.residentialPlan=plan();d.plan.customerMessages=['Use 9 ft','Use 7 ft'];const r=buildCustomerDescription([{role:'user',content:'Use 9 ft'},{role:'user',content:'Use 7 ft'},{role:'user',content:'Paint white'}],d);assert(!r.description.includes('Use 9 ft'));assert.match(r.description,/NEW CUSTOMER UPDATE: Paint white/);});
test('form keeps multiple friendly questions and excludes conflict history',()=>{const r=report();r.conflicts=['earlier 9 then 7'];r.questions=['How wide is the room? Example: 5 feet.','How long is the room? Example: 3 feet.'];const q=appQuestions(r,project,2);assert.equal(q.length,2);assert(!JSON.stringify(q).includes('earlier 9'));});
const {searchCatalog,evidenceNumbers}=await import('./residential-estimator.ts');
test('white paint layers retrieve ordinary two-coat painting',()=>assert(searchCatalog('White Paint Two Layers','SF').some(x=>/Paint, two coats/.test(x.description))));
test('60-inch vanity retrieval includes suitable actual vanity items',()=>assert(searchCatalog('Install 60-inch vanity','Ea').some(x=>/Vanity/.test(x.category))));
test('requested label remains visible while catalog supplies the rate',()=>{const description='White Paint — Two Layers over 100 SF';const selected=searchCatalog('interior paint two coats','SF').find(x=>/Paint, two coats/.test(x.description));assert(selected);const p=plan();p.items[0]={...p.items[0],description:'White Paint — Two Layers',evidence:description,catalogId:selected.id,matchReason:'Closest catalog row omits white color'};const r=pricePlan({description,plan:p});const e=appEstimate(r);const item=e.categories[0].items[0];assert.equal(item.name,'White Paint — Two Layers');assert.equal(item.unitPrice,selected.rate);assert(!item.description.includes('Closest'));assert(!item.description.includes(selected.description));});
test('everyday number words support measured quantities',()=>{assert(evidenceNumbers('seven feet').includes(7));const p=plan();p.items[0].quantity.measurements=[{value:7,unit:'SF',evidence:'seven SF'}];p.items[0].evidence='Remove seven SF acoustical ceiling tile only';const r=pricePlan({description:p.items[0].evidence,plan:p});assert.equal(r.pricedLineCount,1);assert.equal(r.lines[0].catalogQuantity,7);});
test('a new correction can repeat the text of an older superseded message',()=>{const d=draft();d.plan.residentialPlan=plan();d.plan.customerMessages=['Use 7 ft','Use 9 ft'];const r=buildCustomerDescription([{role:'user',content:'Use 7 ft'},{role:'user',content:'Use 9 ft'},{role:'user',content:'Use 7 ft'}],d);assert.match(r.description,/NEW CUSTOMER UPDATE: Use 7 ft/);assert(!r.description.includes('NEW CUSTOMER UPDATE: Use 9 ft'));});

const wholeBathroom=JSON.parse(await readFile(new URL('./whole-bathroom-fixture.json',import.meta.url),'utf8'));
// This legacy fixture tests save contracts, not takeoff arithmetic; preserve its recorded quantities.
for(const c of wholeBathroom.components)c.quantityFormula=c.basis==='derived'?String(c.quantity):null;
for(const component of wholeBathroom.components)component.quantityUnit=component.unit;
test('whole bathroom output passes real handler and atomic save contract',async()=>{setup({wholePlan:wholeBathroom});const response=await handler(post());const body=await response.json();assert.equal(response.status,200,JSON.stringify(body));assert(body.estimate_id);assert.equal(lastSave.p_items.length,body.structured_estimate.categories.flatMap(c=>c.items).length);assert(lastSave.p_items.length>0);assert.equal(lastDraft.plan.wholeState.version,3);assert.equal(lastDraft.questions.length,0);assert.equal(body.structured_estimate.title,wholeBathroom.title);assert(lastSave.p_items.every(i=>Math.abs(i.total-Math.round(i.quantity*i.unit_price*100)/100)<.021));});

test('real handler preserves an explicitly requested zero markup',async()=>{setup();const r=await handler(post({markup_percent:0}));const j=await r.json();assert.equal(r.status,200);assert.equal(j.structured_estimate.total,77);assert.equal(j.structured_estimate.markupPercent,0);});
