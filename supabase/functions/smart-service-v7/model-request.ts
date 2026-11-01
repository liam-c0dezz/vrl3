import { EstimateError, readBounded, validate } from './residential-estimator.ts';

type Options = {
  name:string; instructions:string; input:unknown; schema:unknown; effort:string;
  signal:AbortSignal; apiKey:string; model:string; images?:string[]; transport?:typeof fetch;
  background?:{responseId?:string;onCreated:(id:string)=>Promise<void>;onInvalid:()=>Promise<void>;pollMs?:number};
  check?:(value:any)=>void; onStage?:(stage:string,ms:number)=>void; attemptTimeoutMs?:number;
};

// Provider messages can echo customer content. Log only bounded identifier fields.
function providerFailure(status:number,body:any){
 const identifier=(value:unknown)=>typeof value==='string'&&/^[a-zA-Z0-9_.\[\]-]{1,120}$/.test(value)?value:'';
 const code=identifier(body?.error?.code);
 const param=identifier(body?.error?.param);
 // Fixed vocabulary reveals format failures without emitting provider-echoed values.
 const vocabulary=new Set('image images input invalid value base64 data url format content expected detail string object supported support unsupported background store missing required decode bytes parse empty type schema jpeg png model not cannot'.split(' '));
 const hints=[...new Set((String(body?.error?.message??'').toLowerCase().match(/[a-z]+/g)??[]).filter(word=>vocabulary.has(word)))].slice(0,18).join(',');
 return new EstimateError(502,`Provider HTTP ${status}${code?' '+code:''}${param?' param='+param:''}${hints?' hints='+hints:''}`);
}

/** Retry provider and contract failures inside the service, never as customer questions. */
export async function modelJSON(o:Options):Promise<any>{
  const started=Date.now();
  let correction:string|undefined;
  let last:unknown;
  for(let attempt=0;attempt<2;attempt++){
    o.signal.throwIfAborted();
    o.onStage?.(`${o.name}:start`,Date.now()-started);
    const attemptSignal=o.background?o.signal:AbortSignal.any([o.signal,AbortSignal.timeout(o.attemptTimeoutMs??(o.name==='scope_update'?40_000:25_000))]);
    try{
      const requestBody={model:o.model,store:false,...(o.background?{background:true}:{}),reasoning:{effort:o.effort},max_output_tokens:/^whole_(?:plan|review)$/.test(o.name)?30000:12000,
          instructions:o.instructions,
          input:[{role:'user',content:[{type:'input_text',text:JSON.stringify(correction?{...(o.input as Record<string,unknown>),internalCorrection:correction}:o.input)},...(o.images??[]).map(image_url=>({type:'input_image',image_url}))]}],
          text:{format:{type:'json_schema',name:o.name,strict:true,schema:o.schema}}};
      let body:any;
      if(o.background){body=await backgroundResponse(o,requestBody);}
      else {const r=await(o.transport??fetch)('https://api.openai.com/v1/responses',{
        method:'POST',signal:attemptSignal,headers:{Authorization:`Bearer ${o.apiKey}`,'Content-Type':'application/json'},
        body:JSON.stringify(requestBody),
      });
      if(!r.ok){let detail='';if(r.status===429){try{const e=await r.json();detail=' '+String(e.error?.code??'')+' '+String(e.error?.message??'').slice(0,300);}catch{}}else await r.body?.cancel();throw new EstimateError(502,`Provider HTTP ${r.status}${detail}`);}
      body=JSON.parse(await readBounded(r.body,512000,attemptSignal));}
      if(body.status!=='completed'){await o.background?.onInvalid();if(o.background)o.background.responseId=undefined;if(body.status==='failed'&&body.error)throw providerFailure(502,body);throw new EstimateError(502,`Provider output ${body.status??'missing status'}${body.incomplete_details?.reason==='max_output_tokens'?' reason=max_output_tokens':''}`);}
      const parts=body.output?.flatMap((x:any)=>x.content??[]).filter((x:any)=>x.type==='output_text');
      if(parts?.length!==1)throw new EstimateError(502,'Provider response has no single JSON result');
      const parsed=JSON.parse(parts[0].text);
      try{validate(parsed,o.schema as any);o.check?.(parsed);}catch(e){await o.background?.onInvalid();if(o.background)o.background.responseId=undefined;throw e;}
      o.onStage?.(`${o.name}:complete`,Date.now()-started);
      return parsed;
    }catch(error){
      last=error;
      if(error instanceof EstimateError && /credit_balance_exhausted|insufficient_quota/.test(error.message))throw error;
      // This only logs provider statuses and locally-generated validation diagnostics.
      const detail=error instanceof EstimateError?error.message:(error as Error)?.name??'UnknownError';
      o.onStage?.(`${o.name}:retry:${detail.slice(0,180)}`,Date.now()-started);
      if(o.signal.aborted)throw o.signal.reason;
      correction=`The previous response failed an internal check: ${detail}. Regenerate a complete valid result from the supplied task. Do not ask the customer to repair this output.`;
    }
  }
  throw last instanceof EstimateError?new EstimateError(502,last.message):new EstimateError(502,'Provider request failed after automatic recovery');
}


async function backgroundResponse(o:Options,requestBody:unknown):Promise<any>{
 const base='https://api.openai.com/v1/responses';
 const transport=o.transport??fetch;
 async function getBody(url:string,init:RequestInit){
  const response=await transport(url,{...init,signal:AbortSignal.any([o.signal,AbortSignal.timeout(20000)]),headers:{Authorization:`Bearer ${o.apiKey}`,'Content-Type':'application/json'}});
  const body=JSON.parse(await readBounded(response.body,512000,o.signal));
  if(!response.ok){
   if(response.status===404){await o.background!.onInvalid();o.background!.responseId=undefined;}
   throw providerFailure(response.status,body);
  }return body;
 }
 let body:any;
 if(o.background!.responseId)body=await getBody(`${base}/${encodeURIComponent(o.background!.responseId)}`,{method:'GET'});
 else{
  body=await getBody(base,{method:'POST',body:JSON.stringify(requestBody)});
  if(typeof body.id==='string'){
   o.background!.responseId=body.id;
   await o.background!.onCreated(body.id); // durable before any waiting
  }else if(body.status!=='completed')throw new EstimateError(502,'Missing background response ID');
 }
 while(body.status==='queued'||body.status==='in_progress'){
  o.signal.throwIfAborted();
  await new Promise<void>((resolve,reject)=>{
   const stop=()=>{clearTimeout(timer);o.signal.removeEventListener('abort',stop);reject(o.signal.reason);};
   const timer=setTimeout(()=>{o.signal.removeEventListener('abort',stop);resolve();},o.background!.pollMs??2000);
   o.signal.addEventListener('abort',stop,{once:true});if(o.signal.aborted)stop();
  });
  body=await getBody(`${base}/${encodeURIComponent(o.background!.responseId!)}`,{method:'GET'});
 }
 return body;
}
