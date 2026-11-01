import test from 'node:test';import assert from 'node:assert/strict';
import {modelJSON} from './model-request.ts';
const schema={type:'object',properties:{ok:{type:'boolean'}},required:['ok'],additionalProperties:false};
const complete={id:'resp_test',status:'completed',output:[{content:[{type:'output_text',text:'{"ok":true}'}]}]};
const base={name:'test',instructions:'test',input:{},schema,effort:'low',apiKey:'test',model:'test'};
test('background saves response before polling and returns completed output',async()=>{let saved=false;const methods=[];const result=await modelJSON({...base,signal:new AbortController().signal,background:{pollMs:1,onCreated:async id=>{assert.equal(id,'resp_test');saved=true},onInvalid:async()=>assert.fail('unexpected invalidation')},transport:async(url,init)=>{methods.push(init.method);if(init.method==='POST'){const body=JSON.parse(init.body);assert.equal(body.background,true);assert.equal(body.store,false);return Response.json({id:'resp_test',status:'queued'})}assert.equal(saved,true);return Response.json(complete)}});assert.deepEqual(result,{ok:true});assert.deepEqual(methods,['POST','GET'])});
test('request cancellation preserves ID and next request retrieves without regeneration',async()=>{const controller=new AbortController();let saved;let invalid=0;await assert.rejects(modelJSON({...base,signal:controller.signal,background:{pollMs:1,onCreated:async id=>{saved=id;controller.abort(new Error('request deadline'))},onInvalid:async()=>invalid++},transport:async()=>Response.json({id:'resp_test',status:'queued'})}),/request deadline/);assert.equal(saved,'resp_test');assert.equal(invalid,0);let calls=0;const value=await modelJSON({...base,signal:new AbortController().signal,background:{responseId:saved,pollMs:1,onCreated:async()=>assert.fail('must not create again'),onInvalid:async()=>invalid++},transport:async(url,init)=>{calls++;assert.equal(init.method,'GET');assert.match(url,/resp_test$/);return Response.json(complete)}});assert.equal(calls,1);assert.equal(value.ok,true);assert.equal(invalid,0)});
test('provider rejection identifies invalid parameter without logging echoed customer data',async()=>{
 let calls=0;const stages=[];
 await assert.rejects(modelJSON({...base,signal:new AbortController().signal,onStage:s=>stages.push(s),background:{onCreated:async()=>assert.fail('no response created'),onInvalid:async()=>{}},transport:async()=>{calls++;return Response.json({error:{code:'invalid_value',param:'input[0].content[1].image_url',message:'private customer image data'}},{status:400})}}),/Provider HTTP 400 invalid_value param=input\[0\].content\[1\].image_url/);
 assert.equal(calls,2);assert.ok(stages.every(s=>!s.includes('private customer')));
});

test('whole-project planning reserves reasoning capacity and identifies truncation without customer data',async()=>{
 const budgets=[];const stages=[];let n=0;
 const result=await modelJSON({...base,name:'whole_plan',signal:new AbortController().signal,onStage:s=>stages.push(s),transport:async(url,init)=>{budgets.push(JSON.parse(init.body).max_output_tokens);return Response.json(n++===0?{status:'incomplete',incomplete_details:{reason:'max_output_tokens'},output:[]}:complete)}});
 assert.deepEqual(result,{ok:true});assert.deepEqual(budgets,[30000,30000]);assert.ok(stages.some(s=>s.includes('reason=max_output_tokens')));
});

test('failed background response exposes exhausted credits safely and does not regenerate',async()=>{
 let calls=0;let invalidations=0;const stages=[];
 await assert.rejects(modelJSON({...base,signal:new AbortController().signal,onStage:s=>stages.push(s),background:{onCreated:async()=>{},onInvalid:async()=>invalidations++},transport:async()=>{calls++;return Response.json({id:'resp_failed',status:'failed',error:{code:'credit_balance_exhausted',message:'You have no credits remaining; private customer content'}})}}),/credit_balance_exhausted/);
 assert.equal(calls,1);assert.equal(invalidations,1);assert.ok(stages.every(s=>!s.includes('private customer')));
});
