import {runNode} from './ddc-nodes.js';
import {payload,conversion,checkedQuantity,type Row} from './catalog.ts';
function equal(a:unknown,b:unknown){if(JSON.stringify(a)!==JSON.stringify(b))throw new Error(`${JSON.stringify(a)} != ${JSON.stringify(b)}`);}
const row:Row={id:42,catalog_version:'repair-2026-q3',source_row:2,description:'Fixture',category:'Plumbing',unit:'Ea',direct_cost:'100.2500',material_cost:60,labor_cost:35.25,equipment_cost:5,action:'install'};
const first=(name:string,input:any,context:any={},state:any={})=>{const r=runNode(name,input,context,state);return Array.isArray(r)?r[0]:r;};
Deno.test('DDC parser retains expansion prompt and quantity default',()=>{
 const context:any={Config:{chatId:'t',text:'Bathroom remodel',L:{search_lang:'English'}},'🔑 TOKEN':{}};
 const p=first('Prep Text LLM',{},context);equal(p._parse_prompt.includes('Be COMPREHENSIVE'),true);equal(p._parse_prompt.includes('REALISTIC quantities'),true);
 context['Prep Text LLM']=p;
 const r=first('📝 Parse Text Response',{text:'[{"name":"Toilet install"}]'},context,{});equal(r.works[0].qty,1);
});
Deno.test('DDC candidate index controls ID; model-created price and ID are ignored',()=>{
 const result=first('8️⃣ Apply Rerank',{text:'{"rankings":[{"index":0,"score":90,"reason":"match","rate_code":"evil","price":0}]}'},{'6️⃣ Prep Rerank':{_qdrant_results:[{score:0.8,payload:payload(row)}]}});
 equal(result._best_result.payload.rate_code,'42');equal(result._best_result.combined_score,87);equal(result._best_result.payload.cost_summary.total_cost_position,100.25);
});
Deno.test('DDC malformed JSON falls back to vector scores exactly as upstream',()=>{
 const result=first('8️⃣ Apply Rerank',{text:'{invalid}'},{'6️⃣ Prep Rerank':{_qdrant_results:[{score:0.8,payload:payload(row)}]}});
 equal(result._llm_score,80);equal(result._best_result.combined_score,80);
});
Deno.test('DDC empty search retains no candidate',()=>{
 const result=first('8️⃣ Apply Rerank',{text:'{}'},{'6️⃣ Prep Rerank':{_qdrant_results:[]}});equal(result._best_result,null);
});
Deno.test('Authoritative catalog cost is calculated by original DDC code',()=>{
 const r=first('9️⃣ Calculate',{qty:2,unit:'Ea',name:'Work',_best_result:{payload:payload(row)},_llm_score:90});
 equal(r.uc,100.25);equal(r.tc,200.5);equal(r.workers_total,70.5);equal(r.materials_total,120);equal(r.machines_total,10);
});
Deno.test('Metric and US units map without mixing dimensions',()=>{
 equal(conversion('SF','m²'),0.09290304);equal(conversion('SY','SF'),9);equal(conversion('LF','SF'),null);equal(conversion('pcs','Ea'),1);equal(conversion('pcs','Set'),null);
});
Deno.test('Invalid catalog records and numeric inputs fail',()=>{
 let failed=0;for(const run of [()=>payload({...row,catalog_version:'foreign'}),()=>checkedQuantity(NaN),()=>checkedQuantity(-1)]){try{run();}catch{failed++;}}equal(failed,3);
});
Deno.test('DDC aggregation rounds only the final total',()=>{
 const r=first('Agg',{}, {Config:{chatId:'x',L:{sym:'$'}}},{res:{x:[{tc:1.234,_found:true},{tc:2.234,_found:true}]}});equal(r.total,3.47);equal(r.found_count,2);
});
