import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.95.0';
import { ENGINE, estimate, indexBatch } from './engine.ts';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
function key(primary:string,legacy:string) {
  const direct=Deno.env.get(legacy);if(direct)return direct;
  const values=JSON.parse(Deno.env.get(primary)||'{}');
  for(const v of Object.values(values))if(typeof v==='string'){const resolved=Deno.env.get(v);if(resolved)return resolved;if(v.startsWith('sb_'))return v;}
  throw new Error('Missing server configuration');
}
async function readBody(req:Request) {
  if(!req.body)throw new Error('Missing request');const reader=req.body.getReader();const chunks:Uint8Array[]=[];let size=0;
  const timer=setTimeout(()=>void reader.cancel(),15000);
  try {while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>12_000_000){await reader.cancel();throw new Error('Request too large');}chunks.push(value);}}
  finally{clearTimeout(timer);reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return JSON.parse(new TextDecoder().decode(bytes));
}
const uuid=(v:any)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
function validate(body:any) {
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!['operation','request_id','project_id','scope','photos','markup_percent'].includes(k)))throw new Error('Invalid request fields');
  if(typeof body.scope!=='string'||body.scope.trim().length<3||body.scope.length>20000)throw new Error('Scope must be 3–20000 characters');
  const markup=body.markup_percent??0;if(typeof markup!=='number'||!Number.isFinite(markup)||markup<0||markup>100)throw new Error('Invalid markup');
  const photos=body.photos??[];if(!Array.isArray(photos)||photos.length>3)throw new Error('Maximum three photos');
  for(const photo of photos){if(typeof photo!=='string'||photo.length>4_000_000||!/^data:image\/(png|jpeg);base64,[A-Za-z0-9+/]+={0,2}$/.test(photo))throw new Error('Photos must be JPEG/PNG data URLs');
    const bytes=atob(photo.split(',')[1]);if(photo.startsWith('data:image/png')?!bytes.startsWith('\x89PNG\r\n\x1a\n'):!bytes.startsWith('\xff\xd8\xff'))throw new Error('Photo format mismatch');}
  return {scope:body.scope,photos,markup};
}
async function hash(text:string){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),b=>b.toString(16).padStart(2,'0')).join('');}
// Send whitespace while working: valid JSON leading whitespace prevents idle
// gateway timeouts without changing the returned estimate contract.
function stream(work:()=>Promise<unknown>, diagnostic=false) {
  const encoder=new TextEncoder();let cancelled=false;
  return new Response(new ReadableStream({start(controller){const timer=setInterval(()=>{if(!cancelled)controller.enqueue(encoder.encode('\n'));},10000);
    controller.enqueue(encoder.encode('\n'));
    work().then(data=>{if(!cancelled)controller.enqueue(encoder.encode(JSON.stringify(data)));}).catch(error=>{console.error('apache_failed',error.message);if(!cancelled)controller.enqueue(encoder.encode(JSON.stringify({error:'Estimator could not finish. Retry with a new request.',code:'apache_failed',...(diagnostic?{diagnostic:error.message}:{})})));}).finally(()=>{clearInterval(timer);if(!cancelled)controller.close();});},cancel(){cancelled=true;}}),{headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
}
Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({error:'Method not allowed'},405);
  try {
    const service=key('SUPABASE_SECRET_KEYS','SUPABASE_SERVICE_ROLE_KEY');
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,service,{auth:{persistSession:false,autoRefreshToken:false}});
    const bearer=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');
    if(!bearer)return json({error:'Authentication required'},401);
    let privileged=bearer===service;
    const auth=privileged?null:await admin.auth.getUser(bearer);
    if(!privileged&&(auth?.error||!auth?.data.user)) {
      // Hosted Supabase may mint a different internal service JWT. Validate the
      // presented key with PostgREST, which cryptographically verifies it and
      // enforces this server-only table's grants; never trust decoded JWT claims.
      const probe=createClient(Deno.env.get('SUPABASE_URL')!,bearer,{auth:{persistSession:false,autoRefreshToken:false}});
      const access=await probe.from('smart_service_apache_embeddings').select('catalog_id').limit(1);
      privileged=!access.error;
      if(!privileged)return json({error:'Invalid session'},401);
    }
    let body;try{body=await readBody(req);}catch{return json({error:'Invalid or oversized JSON body'},400);}
    const openai=Deno.env.get('OPENAI_API_KEY');if(!openai)throw new Error('Missing OpenAI key');
    const signal=AbortSignal.any([req.signal,AbortSignal.timeout(350000)]);
    if(body.operation==='index') {
      if(!privileged)return json({error:'Administrator required'},403);
      return stream(async()=>{let indexed=0;for(let i=0;i<6;i++){const result=await indexBatch(admin,openai,signal);indexed+=result.indexed;if(result.done)return {indexed,done:true};}return {indexed,done:false};});
    }
    let input;try{input=validate(body);}catch(e){return json({error:(e as Error).message},400);}
    if(privileged){if(body.operation!=='evaluate')return json({error:'Use evaluate for administrative tests'},400);return stream(()=>estimate(admin,openai,input.scope,input.photos,input.markup,signal),true);}
    if(body.operation&&body.operation!=='estimate')return json({error:'Invalid operation'},400);
    if(!uuid(body.project_id)||!uuid(body.request_id))return json({error:'project_id and request_id must be UUIDs'},400);
    const userId=auth!.data.user!.id;
    const {data:project,error:pError}=await admin.from('projects').select('organization_id').eq('id',body.project_id).maybeSingle();
    if(pError||!project)return json({error:'Project not found'},404);
    const {data:member,error:mError}=await admin.from('organization_members').select('user_id').eq('organization_id',project.organization_id).eq('user_id',userId).maybeSingle();
    if(mError||!member)return json({error:'Project access denied'},403);
    const inputHash=await hash(JSON.stringify(input));
    const inserted=await admin.from('smart_service_apache_requests').upsert({request_id:body.request_id,user_id:userId,project_id:body.project_id,input_hash:inputHash},{onConflict:'request_id',ignoreDuplicates:true});
    if(inserted.error)throw new Error('Request binding failed');
    const bound=await admin.from('smart_service_apache_requests').select('user_id,project_id,input_hash').eq('request_id',body.request_id).single();
    if(bound.error||bound.data.user_id!==userId||bound.data.project_id!==body.project_id||bound.data.input_hash!==inputHash)return json({error:'Request ID belongs to different input'},409);
    const reservation=await admin.rpc('reserve_ai_request',{p_user_id:userId,p_request_id:body.request_id,p_uses_ai:true,p_consent_version:'2026-07-31',p_ip_hash:null});
    if(reservation.error)throw new Error('Usage reservation failed');
    if(reservation.data.state==='cached')return reservation.data.response?.engine===ENGINE?json(reservation.data.response):json({error:'Request ID already used by another service'},409);
    if(reservation.data.state!=='granted')return json({error:reservation.data.state},reservation.data.state==='consent_required'?403:429);
    return stream(async()=>{
      try {
        const result=await estimate(admin,openai,input.scope,input.photos,input.markup,signal);
        const consent=await admin.rpc('has_current_ai_consent',{p_user_id:userId,p_consent_version:'2026-07-31'});
        if(consent.error||consent.data!==true)throw new Error('Consent withdrawn');
        const complete=await admin.rpc('complete_ai_request',{p_user_id:userId,p_request_id:body.request_id,p_response_body:result});
        if(complete.error||complete.data!==true)throw new Error('Request completion failed');return result;
      }catch(e){await admin.rpc('fail_ai_request',{p_user_id:userId,p_request_id:body.request_id,p_error_code:'apache_failed'});throw e;}
    });
  } catch(e){console.error('apache_request_failed',(e as Error).message);return json({error:'Service unavailable'},503);}
});
