import test from 'node:test';
import assert from 'node:assert/strict';
import { jsonKeepalive } from './json-keepalive.ts';
const delay = ms => new Promise(r=>setTimeout(r,ms));
test('fast authorization failure retains HTTP status', async()=>{const r=await jsonKeepalive(async()=>new Response('{"error":"Unauthorized"}',{status:401}),{},5);assert.equal(r.status,401);});
test('slow response sends whitespace before completion and parses as unchanged JSON', async()=>{let finish;const work=new Promise(r=>finish=r);const response=await jsonKeepalive(()=>work,{},5);const reader=response.body.getReader();const first=await reader.read();assert.match(new TextDecoder().decode(first.value),/^\s+$/);finish(new Response('{"reply":"done","total":77}'));let text=new TextDecoder().decode(first.value);for(;;){const r=await reader.read();if(r.done)break;text+=new TextDecoder().decode(r.value);}assert.deepEqual(JSON.parse(text),{reply:'done',total:77});});
test('late errors retain safe error and appear as errors in installed app',async()=>{const r=await jsonKeepalive(async()=>{await delay(20);return new Response('{"error":"Try again","code":"estimator_timeout"}',{status:504});},{},5);const j=await r.json();assert.equal(j.reply,'Try again');assert.equal(j.turn_stage,'intake');assert.equal(j.http_status,504);assert.equal(j.structured_estimate,null);});
test('stream cancellation safely clears heartbeat while work finishes',async()=>{let finish;const work=new Promise(r=>finish=r);const r=await jsonKeepalive(()=>work,{},5);await r.body.cancel();finish(new Response('{}'));await delay(20);});
