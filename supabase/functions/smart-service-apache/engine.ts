import { runNode } from './ddc-nodes.js';
import { CATALOG, EMBEDDING_MODEL, DIMENSIONS, payload, conversion, checkedQuantity, money, type Row } from './catalog.ts';
import { VISION_PROMPT } from './vision-prompt.ts';
export const ENGINE='smart-service-apache-ddc-1';
type Admin = any;
type Context = Record<string,any>;
export async function openAI(key:string,path:string,body:unknown,signal:AbortSignal) {
  const res=await fetch(`https://api.openai.com/v1/${path}`,{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify(body),signal});
  if(!res.ok)throw new Error(`OpenAI ${path} failed (${res.status})`);
  return await res.json();
}
async function chat(key:string,prompt:string,model:string,temperature:number,signal:AbortSignal,images:string[]=[]) {
  const content:any=images.length?[{type:'text',text:prompt},...images.map(url=>({type:'image_url',image_url:{url}}))]:prompt;
  const data=await openAI(key,'chat/completions',{model,temperature,messages:[{role:'user',content}],max_tokens:6000},signal);
  if(data.choices?.[0]?.finish_reason!=='stop'||!data.choices[0].message?.content)throw new Error('Incomplete model response');
  return data.choices[0].message.content as string;
}
export async function embed(key:string,input:string[],signal:AbortSignal):Promise<number[][]> {
  const data=await openAI(key,'embeddings',{model:EMBEDDING_MODEL,input,dimensions:DIMENSIONS},signal);
  if(!Array.isArray(data.data)||data.data.length!==input.length)throw new Error('Embedding batch mismatch');
  const ordered=data.data.sort((a:any,b:any)=>a.index-b.index);
  if(ordered.some((d:any,i:number)=>d.index!==i||d.embedding?.length!==DIMENSIONS||d.embedding.some((n:any)=>!Number.isFinite(n))))throw new Error('Invalid embedding');
  return ordered.map((d:any)=>d.embedding);
}
async function rows(admin:Admin,ids:number[]):Promise<Row[]> {
  const {data,error}=await admin.from('estimator_cost_items').select('id,catalog_version,source_row,description,category,unit,direct_cost,material_cost,labor_cost,equipment_cost,action').in('id',ids).eq('catalog_version',CATALOG);
  if(error)throw new Error('Catalog read failed');return data??[];
}
export async function indexBatch(admin:Admin,key:string,signal:AbortSignal) {
  const {data,error}=await admin.rpc('smart_service_apache_pending',{p_limit:64});
  if(error)throw new Error('Index lookup failed');if(!data.length)return {indexed:0,done:true};
  const vectors=await embed(key,data.map((x:any)=>x.source_text),signal);
  const result=await admin.from('smart_service_apache_embeddings').upsert(data.map((x:any,i:number)=>({...x,model:EMBEDDING_MODEL,embedding:vectors[i],updated_at:new Date().toISOString()})));
  if(result.error)throw new Error('Index write failed');return {indexed:data.length,done:false};
}
export async function estimate(admin:Admin,key:string,scope:string,photos:string[],markup:number,signal:AbortSignal) {
  const readiness=await admin.rpc('smart_service_apache_pending',{p_limit:1});
  if(readiness.error||readiness.data?.length)throw new Error('Apache catalog index is not ready');
  // chatgpt-4o-latest (upstream) was removed by its provider. Same family replacement.
  const parseModel=Deno.env.get('APACHE_PARSE_MODEL')||'gpt-4o';
  const smallModel=Deno.env.get('APACHE_RERANK_MODEL')||'gpt-4o-mini';
  let vision:string|null=null;
  if(photos.length)vision=await chat(key,VISION_PROMPT.replace('__USER_NOTE__',scope),parseModel,0.2,signal,photos);
  const text=vision?`${scope}\n\nPhoto survey:\n${vision}`:scope;
  const state:any={};const context:Context={'Config':{chatId:'request',text,L:{search_lang:'English',sym:'$',not_found:'Not found'},db:'EN_USER_CATALOG'},'🔑 TOKEN':{}};
  const step=(name:string,input:any)=>{const result=runNode(name,input,context,state);const v=Array.isArray(result)?result[0]:result;context[name]=v;return v;};
  const prep=step('Prep Text LLM',{});
  const parsed=step('📝 Parse Text Response',{text:await chat(key,prep._parse_prompt,parseModel,0.15,signal)});
  if(!parsed.works.length)throw new Error('DDC parser returned no work items');
  if(parsed.works.length>60)throw new Error('Scope exceeds 60 work items; split into smaller estimates');
  const works=runNode('Prep Works',parsed,context,state) as any[];
  const audit:any[]=[];const items:any[]=[];const unresolved:any[]=[];
  for(const work of works) {
    checkedQuantity(work.qty);
    const q=step('1️⃣ Prep Query',work);
    const transformed=step('2️⃣ Extract Transform',{text:await chat(key,q._transform_prompt,smallModel,0.3,signal)});
    const [embedding]=await embed(key,[transformed._query],signal);
    step('4️⃣ Extract Embedding',{data:[{embedding}]});
    const {data:matches,error}=await admin.rpc('smart_service_apache_search',{p_embedding:embedding});
    if(error)throw new Error('Catalog search failed');
    const catalog=matches.length?await rows(admin,matches.map((m:any)=>m.id)):[];
    const candidates=matches.flatMap((m:any)=>{const r=catalog.find(r=>r.id===m.id);return r?[{score:m.similarity,payload:payload(r)}]:[];});
    const rerank=step('6️⃣ Prep Rerank',{result:candidates});
    const ranked=candidates.length?step('8️⃣ Apply Rerank',{text:await chat(key,rerank._rerank_prompt,smallModel,0.3,signal)}):null;
    const chosen=ranked?._best_result?.payload?.rate_code;
    // DDC chooses the candidate object, not an AI-supplied price or catalog record.
    if(chosen&&!catalog.some(r=>String(r.id)===chosen))throw new Error('Catalog selection escaped candidate set');
    const fresh=chosen?(await rows(admin,[Number(chosen)]))[0]:null;
    const factor=fresh?conversion(work.unit,fresh.unit):null;
    let calculation:any;
    if(fresh&&factor!==null) {
      const authoritative=payload(fresh);
      calculation=step('9️⃣ Calculate',{...ranked,qty:checkedQuantity(work.qty*factor),unit:fresh.unit,_best_payload:authoritative,_best_result:{...ranked._best_result,payload:authoritative}});
      items.push({catalog_id:String(fresh.id),catalog_version:fresh.catalog_version,source_row:fresh.source_row,description:fresh.description,category:fresh.category,quantity:calculation.qty,unit:fresh.unit,unit_price:Number(fresh.direct_cost),total:money(calculation.tc),ddc_work_name:work.name,ddc_quantity:work.qty,ddc_unit:work.unit,quality:calculation.ql,score:calculation.llm_score});
    } else {
      calculation={...work,rate_code:'NOT_FOUND',rate_name:'',uc:0,tc:0};
      unresolved.push({work:work.name,quantity:work.qty,unit:work.unit,status:fresh?'UNIT_MISMATCH':'NO_MATCH'});
    }
    step('📊 Update Result',calculation);step('Acc',{});
    audit.push({work:work.name,query:transformed._query,candidate_ids:catalog.map(r=>String(r.id)),selected_id:fresh?String(fresh.id):null,llm_score:ranked?._llm_score??0,combined_score:ranked?._best_result?.combined_score??0});
  }
  const aggregate=step('Agg',{});
  const subtotal=aggregate.total;const markupAmount=money(subtotal*markup/100);
  return {engine:ENGINE,name:'Smart Service Apache',catalog_version:CATALOG,currency:'USD',items,unresolved,subtotal,markup_percent:markup,markup_amount:markupAmount,total:money(subtotal+markupAmount),status:unresolved.length?'partial':'complete',ddc_aggregate:aggregate,parsed_works:parsed.works,vision_survey:vision,audit};
}
