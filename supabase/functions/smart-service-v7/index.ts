import { estimateWholeProject, snapshot, wholeAppEstimate, GENERATOR_VERSION, type WholeState } from './whole-project.ts';
import { jsonKeepalive } from "./json-keepalive.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";
import {
  RequestValidationError,
  type ValidatedSmartServiceRequest,
  validateSmartServiceRequest,
} from "./validation.ts";
import {
  audioFilename,
  decodeBoundedBase64,
  verifyAudioBytes,
  verifyImageBytes,
} from "./media.ts";
import { basicJobPlan, generateStoredJobPlan, JobPlanError } from "./job_plan.ts";

import { ESTIMATE_MODEL, ESTIMATE_REASONING, SCOPE_REASONING, AI_DEADLINE_MS, reasoningOutputBudget } from "./model_config.ts";
const OPENAI_MODEL = ESTIMATE_MODEL;
const OPENAI_TRANSCRIPTION_MODEL = "gpt-4o-mini-transcribe";
const AI_CONSENT_VERSION = "2026-07-31";
const ENGINE_VERSION = "residential-estimator-2026-09-25";
const MAX_PHOTO_BYTES = 8_000_000;
const MAX_AUDIO_BYTES = 25_000_000;
const MAX_VIDEO_FRAME_BYTES = 2_000_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Reservation = {
  state: "granted" | "cached" | "in_progress" | "failed" | "disabled" |
    "consent_required" | "busy" | "rate_limited" | "quota_exceeded";
  scope?: string;
  max_output_tokens?: number;
  response?: Record<string, unknown> | null;
};

class SafeServiceError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
  ) {
    super(publicMessage);
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

async function sha256(value: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function configuredKey(primary: string, legacy: string): string | null {
  const direct = Deno.env.get(legacy);
  if (direct) return direct;
  const dictionary = Deno.env.get(primary);
  if (!dictionary) return null;
  try {
    const parsed = JSON.parse(dictionary) as Record<string, unknown>;
    for (const value of Object.values(parsed)) {
      if (typeof value !== "string") continue;
      const resolved = Deno.env.get(value);
      if (resolved && resolved.length > 20) return resolved;
      if (value.length > 20 && (value.startsWith("sb_") || value.split(".").length === 3)) return value;
    }
  } catch {
    return null;
  }
  return null;
}

async function transcribeAudio(encodedAudio: string, mimeType: string, openAIKey: string, signal: AbortSignal): Promise<string> {
  const bytes = decodeBoundedBase64(encodedAudio, MAX_AUDIO_BYTES, "Audio attachment");
  verifyAudioBytes(bytes, mimeType);
  const form = new FormData();
  form.append("model", OPENAI_TRANSCRIPTION_MODEL);
  form.append("file", new Blob([bytes.buffer as ArrayBuffer], { type: mimeType }), audioFilename(mimeType));
  const result = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${openAIKey}` },
    body: form,
    signal: AbortSignal.any([signal, AbortSignal.timeout(45_000)]),
  });
  if (!result.ok) throw new SafeServiceError(503, "ai_temporarily_unavailable", "The attachment could not be processed. Please try again.");
  const payload = await result.json();
  if (typeof payload?.text !== "string" || !payload.text.trim()) {
    throw new SafeServiceError(503, "ai_invalid_response", "The attachment could not be understood. Please try again.");
  }
  return payload.text.slice(0, 20_000);
}

async function prepareAttachment(request: ValidatedSmartServiceRequest, openAIKey: string, signal: AbortSignal) {
  const kind = request.attachment_kind ?? (request.image_base64 ? "photo" : null);
  const mimeType = request.attachment_mime_type ?? (kind === "photo" ? "image/jpeg" : null);
  const photoBase64 = kind === "photo" ? request.attachment_base64 ?? request.image_base64 ?? null : null;
  const videoFrames = request.video_frames_base64 ?? [];
  if (photoBase64 && mimeType) {
    const bytes = decodeBoundedBase64(photoBase64, MAX_PHOTO_BYTES, "Photo attachment");
    verifyImageBytes(bytes, mimeType);
  }
  for (const [index, frame] of videoFrames.entries()) {
    const bytes = decodeBoundedBase64(frame, MAX_VIDEO_FRAME_BYTES, `Video frame ${index + 1}`);
    verifyImageBytes(bytes, "image/jpeg");
  }
  const audioBase64 = kind === "audio"
    ? request.attachment_base64 ?? null
    : kind === "video"
    ? request.video_audio_base64 ?? null
    : null;
  const transcript = audioBase64 && mimeType ? await transcribeAudio(audioBase64, mimeType, openAIKey, signal) : null;
  return { kind, mimeType, photoBase64, videoFrames, transcript, caption: request.image_caption ?? null };
}

function reservationResponse(reservation: Reservation): Response | null {
  if (reservation.state === "granted") return null;
  if (reservation.state === "cached" && reservation.response) return jsonResponse(reservation.response);
  const responses: Record<string, [number, string, string]> = {
    consent_required: [403, "ai_consent_required", "Allow AI features before using Smart Service."],
    rate_limited: [429, "rate_limited", "Too many requests. Please wait a moment and try again."],
    quota_exceeded: [429, "ai_quota_exceeded", "Your AI usage limit has been reached."],
    busy: [409, "request_in_progress", "Your previous request is still processing."],
    in_progress: [409, "request_in_progress", "Your previous request is still processing."],
    failed: [409, "request_failed", "That request could not be completed. Please start a new request."],
    disabled: [503, "ai_disabled", "AI assistance is temporarily unavailable."],
  };
  const [status, code, message] = responses[reservation.state] ?? [503, "ai_unavailable", "AI assistance is temporarily unavailable."];
  return jsonResponse({ error: message, code }, status);
}


import { createOpenAIPlanner, EstimateError, pricePlan, type Plan } from './residential-estimator.ts';
import { buildCustomerDescription, appEstimate, appQuestions, type SavedDraft } from './app-adapter.ts';

/** App boundary: existing verified auth/consent/quota controls; residential engine;
 * persistent clarification drafts; atomic, idempotent save through a scoped RPC.
 */
export async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ error: 'Method not allowed' }, 405);
  let requestContext: { admin: any; userId: string; requestId: string } | null = null;
  let activeStage = 'request';
  const startedAt = Date.now();
  try {
    if (req.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return jsonResponse({ error: 'Expected application/json' }, 415);
    const supabaseURL = Deno.env.get('SUPABASE_URL');
    const serviceKey = configuredKey('SUPABASE_SECRET_KEYS', 'SUPABASE_SERVICE_ROLE_KEY');
    const publicKey = configuredKey('SUPABASE_PUBLISHABLE_KEYS', 'SUPABASE_ANON_KEY');
    const openAIKey = Deno.env.get('OPENAI_API_KEY');
    if (!supabaseURL || !serviceKey || !publicKey || !openAIKey) throw new Error('Function environment is incomplete');
    const authorization = req.headers.get('Authorization');
    if (!authorization?.match(/^Bearer\s+\S+$/i)) return jsonResponse({ error: 'Authentication required' }, 401);
    const accessToken = authorization.replace(/^Bearer\s+/i, '');
    const admin = createClient(supabaseURL, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await admin.auth.getUser(accessToken);
    if (authError || !authData.user) return jsonResponse({ error: 'Invalid or expired session' }, 401);
    const userId = authData.user.id;
    // Count actual streamed bytes, not a client-controlled Content-Length value.
    if (!req.body) throw new RequestValidationError('Request body is required');
    const reader = req.body.getReader(); const chunks: Uint8Array[] = []; let bytes = 0;
    const bodyTimer = setTimeout(() => { void reader.cancel(); }, 15000);
    try { while (true) { const next = await reader.read(); if (next.done) break;
      bytes += next.value.byteLength; if (bytes > 48000000) { await reader.cancel(); throw new SafeServiceError(413, 'body_too_large', 'Request body is too large'); }
      chunks.push(next.value);
    } } finally { clearTimeout(bodyTimer); reader.releaseLock(); }
    const joined = new Uint8Array(bytes); let offset = 0;
    for (const chunk of chunks) { joined.set(chunk, offset); offset += chunk.byteLength; }
    let raw: unknown; try { raw = JSON.parse(new TextDecoder().decode(joined)); } catch { throw new RequestValidationError('Invalid JSON body'); }
    const validated = validateSmartServiceRequest(raw);
    if (validated.operation !== 'generate' && validated.operation !== 'generate_plan') throw new SafeServiceError(422, 'generate_only', 'Edit the saved estimate directly; natural-language estimate editing is not supported by this engine.');
    if (Array.isArray(validated.screening_answers) || validated.job_id) throw new SafeServiceError(409, 'catalog_updated', 'Please start a new estimate with the residential estimator.');
    const { data: project, error: projectError } = await admin.from('projects').select('id, organization_id').eq('id', validated.project_id).maybeSingle();
    if (projectError || !project) return jsonResponse({ error: 'Project not found' }, 404);
    const { data: membership, error: membershipError } = await admin.from('organization_members').select('user_id').eq('organization_id', project.organization_id).eq('user_id', userId).maybeSingle();
    if (membershipError || !membership) return jsonResponse({ error: 'You do not have access to this project' }, 403);
    const { data: reservationData, error: reservationError } = await admin.rpc('reserve_ai_request', {
      p_user_id: userId, p_request_id: validated.request_id, p_uses_ai: true,
      p_consent_version: AI_CONSENT_VERSION, p_ip_hash: null,
    });
    if (reservationError || !reservationData) throw new Error('AI reservation failed');
    const denied = reservationResponse(reservationData as Reservation); if (denied) return denied;
    requestContext = { admin, userId, requestId: validated.request_id };
    const aiSignal = AbortSignal.any([req.signal, AbortSignal.timeout(AI_DEADLINE_MS)]);
    const finish = async (payload: Record<string, unknown>) => {
      const { data, error } = await admin.rpc('complete_ai_request', { p_user_id: userId, p_request_id: validated.request_id, p_response_body: payload });
      if (error || data !== true) throw new Error('AI request completion failed');
      requestContext = null; return jsonResponse(payload);
    };
    if (validated.operation === 'generate_plan') return await finish(await generateStoredJobPlan(admin, openAIKey, userId, validated.project_id, project.organization_id, validated.estimate_id!, reservationData.max_output_tokens ?? 2000, aiSignal));
    const { data: prior, error: priorError } = !validated.draft_id && validated.chat_session_id
      ? await admin.from('smart_service_drafts').select('id').eq('user_id', userId).eq('project_id', validated.project_id)
        .eq('chat_session_id', validated.chat_session_id).in('status', ['planning', 'awaiting_answers', 'ready']).maybeSingle()
      : { data: null, error: null };
    if (priorError) throw new Error('Draft lookup failed');
    const draftID = validated.draft_id ?? prior?.id ?? crypto.randomUUID();
    const { data: draft, error: draftError } = await admin.from('smart_service_drafts').select('*').eq('id', draftID).eq('user_id', userId).eq('project_id', validated.project_id).maybeSingle();
    if (draftError) throw new Error('Draft lookup failed');
    if (validated.draft_id && !draft) throw new SafeServiceError(409, 'draft_not_found', 'That draft is no longer available. Start a new chat.');
    const existing = draft as SavedDraft | null;
    if (existing && existing.plan.engine !== ENGINE_VERSION) throw new SafeServiceError(409, 'catalog_updated', 'The estimator has been updated. Start a new chat for this project.');
    if (existing?.status === 'completed') {
      if (existing.plan.response) return await finish(existing.plan.response);
      throw new SafeServiceError(409, 'draft_completed', 'This estimate was already saved. Open the saved estimate.');
    }
    const attachment = await prepareAttachment(validated, openAIKey, aiSignal);
    let customer;
    try { customer = buildCustomerDescription(validated.messages ?? [], existing, validated.draft_answers,
      [attachment.caption, attachment.transcript].filter(Boolean).join('\n')); }
    catch (e) { throw new SafeServiceError(422, 'invalid_project_details', (e as Error).message); }
    const imageData = attachment.photoBase64 ? [attachment.photoBase64] : attachment.videoFrames;
    const images = imageData.map(base64 => base64.startsWith('data:') ? base64 : `data:${attachment.kind === 'photo' ? attachment.mimeType ?? 'image/jpeg' : 'image/jpeg'};base64,${base64}`);
    // Checkpoint each completed stage. A failed model call cannot discard accepted scope.
    let workingDraft = existing;
    const checkpointInput = JSON.stringify([customer.scopeText, customer.answers]);
    const persistCheckpoint = async (state: WholeState) => {
      const {data:allowed,error:consentError}=await admin.rpc('has_current_ai_consent',{p_user_id:userId,p_consent_version:AI_CONSENT_VERSION});
      if(consentError||allowed!==true)throw new SafeServiceError(403,'ai_consent_revoked','AI permission was withdrawn before this request completed.');
      const revision=(workingDraft?.revision??0)+1;
      const values={id:draftID,user_id:userId,organization_id:project.organization_id,project_id:validated.project_id,
        chat_session_id:validated.chat_session_id??workingDraft?.chat_session_id??null,status:'planning',revision,
        title:state.title??'Residential Project',scope_text:customer.scopeText,
        plan:{engine:ENGINE_VERSION,generator:GENERATOR_VERSION,wholeState:state,residentialPlan:snapshot(state),checkpointInput,customerMessages:customer.customerMessages},
        questions:existing?.questions??[],answers:customer.answers,updated_at:new Date().toISOString()};
      const saved=workingDraft
        ? await admin.from('smart_service_drafts').update(values).eq('id',draftID).eq('user_id',userId).eq('project_id',validated.project_id).eq('revision',workingDraft.revision).select('id').maybeSingle()
        : await admin.from('smart_service_drafts').insert(values).select('id').single();
      if(saved.error||!saved.data)throw new SafeServiceError(409,'draft_changed','The estimate changed while processing. Please reopen it.');
      workingDraft=values as SavedDraft;
    };
    const {data:rateRows,error:rateError}=await admin.from('business_hourly_rates').select('rate_key,hourly_rate').eq('organization_id',project.organization_id);
    if(rateError)throw new Error('Business rates lookup failed');
    const rates:Record<string,number>={};for(const row of rateRows??[]){const rate=Number(row.hourly_rate);if(row.rate_key&&Number.isFinite(rate)&&rate>0)rates[row.rate_key]=rate;}
    const resume=(existing?.status==='planning'||existing?.status==='ready') && existing.plan.checkpointInput===checkpointInput && existing.plan.wholeState?.version===3 && existing.plan.generator===GENERATOR_VERSION;
    const resolved = await estimateWholeProject(customer.fullContext, aiSignal, {
      apiKey:openAIKey, model:ESTIMATE_MODEL, rates, previous:existing?.plan.wholeState??null, images, resume, onCheckpoint:persistCheckpoint,
      onStage:(stage,elapsedMs)=>{activeStage=stage;console.info('estimator_stage',JSON.stringify({request_id:validated.request_id,generator:GENERATOR_VERSION,stage,elapsed_ms:elapsedMs}));},
    });
    const { plan, report } = resolved;
    const revision = (workingDraft?.revision ?? 0) + 1;
    const questions: ReturnType<typeof appQuestions> = [];
    const needsDetails = report.pricedLineCount === 0 || report.conflicts.length > 0;
    const { data: consent, error: consentError } = await admin.rpc('has_current_ai_consent', { p_user_id: userId, p_consent_version: AI_CONSENT_VERSION });
    if (consentError || consent !== true) throw new SafeServiceError(403, 'ai_consent_revoked', 'AI permission was withdrawn before this request completed.');
    const draftValues = { id: draftID, user_id: userId, organization_id: project.organization_id,
      project_id: validated.project_id, chat_session_id: validated.chat_session_id ?? existing?.chat_session_id ?? null,
      status: needsDetails ? 'awaiting_answers' : 'ready', revision,
      title: resolved.state.title ?? 'Residential Project', scope_text: customer.scopeText,
      plan: { engine: ENGINE_VERSION, residentialPlan: plan, report, checkpointInput, wholeState: resolved.state, generator: GENERATOR_VERSION, customerMessages: customer.customerMessages }, questions,
      answers: customer.answers, updated_at: new Date().toISOString() };
    // Avoid upsert: an arbitrary draft id must never overwrite a different owner.
    const saved = workingDraft
      ? await admin.from('smart_service_drafts').update(draftValues).eq('id', draftID).eq('user_id', userId).eq('project_id', validated.project_id).eq('revision', workingDraft.revision).select('id').maybeSingle()
      : await admin.from('smart_service_drafts').insert(draftValues).select('id').single();
    if (saved.error || !saved.data) throw new SafeServiceError(409, 'draft_changed', 'The draft changed while processing. Please retry the latest details.');
    if (needsDetails && !questions.length) throw new SafeServiceError(503, 'catalog_resolution', 'The estimate could not finish pricing every item. Your project details are saved; please retry.');
    if (needsDetails) return await finish({ reply: 'I need a few details before I can save a priced estimate. Unsupported work remains unpriced.',
      structured_estimate: null, estimate_id: null, stage: 'screening', turn_stage: 'intake',
      job_id: draftID, job_name: draftValues.title, questions, residential_estimate: report, engine: ENGINE_VERSION });
    let estimate;
    try { estimate = wholeAppEstimate(report, validated.markup_percent ?? 10, validated.contingency_percent ?? 0, resolved.state.title); }
    catch (e) { throw new SafeServiceError(422, 'estimate_requires_review', (e as Error).message); }
    activeStage='build_work_plan';
    estimate.workPlan = basicJobPlan({ title: estimate.title, customer_scope: customer.description,
      items: estimate.categories.flatMap(category => category.items.map(item => ({ category: category.name, name: item.name, quantity: item.quantity, unit: item.unitLabel, description: item.description })))
    });
    const payload = { reply: report.omittedScopeCount ? 'Your estimate is ready. Some work could not be priced and is listed in the exclusions; the total covers the priced items.' : 'Your estimate and job plan are ready. Review the line items and assumptions before quoting.', generator: GENERATOR_VERSION,
      structured_estimate: estimate, residential_estimate: report, stage: 3, turn_stage: 'estimate_ready', plan_status: 'ready', engine: ENGINE_VERSION };
    const pItems = estimate.categories.flatMap(category => category.items.map(item => ({ category: category.name, name: item.name, quantity: item.quantity, unit_label: item.unitLabel, unit_price: item.unitPrice, total: item.total, source: item.source, url: item.url, description: item.description, on_hand: item.onHand })));
    activeStage='save_estimate';
    const { data: response, error: storeError } = await admin.rpc('residential_estimator_save_draft', {
      p_user_id: userId, p_draft_id: draftID, p_revision: revision, p_request_id: validated.request_id,
      p_estimate: { title: estimate.title, subtotal: estimate.subtotal, markup_percent: estimate.markupPercent, markup_amount: estimate.markupAmount,
        contingency_percent: estimate.contingencyPercent, contingency_amount: estimate.contingencyAmount, total: estimate.total,
        exclusions: estimate.exclusions, payment_terms: estimate.paymentTerms, sanity_check: estimate.sanityCheck, work_plan: estimate.workPlan, notes: estimate.notes },
      p_items: pItems, p_response: payload,
    });
    if (storeError || !response?.estimate_id) throw new Error(`Atomic estimate save failed: ${storeError?.code ?? 'invalid_result'}`);
    console.info('estimator_complete',JSON.stringify({request_id:validated.request_id,elapsed_ms:Date.now()-startedAt,estimate_id:response.estimate_id}));
    requestContext = null; // The RPC saves the estimate, completes its draft and caches its response atomically.
    return jsonResponse(response);
  } catch (error) {
    const timedOut = (error as Error)?.name === 'TimeoutError';
    const billingBlocked=error instanceof EstimateError && /credit_balance_exhausted|insufficient_quota/.test(error.message);
    const safe = billingBlocked ? new SafeServiceError(503, 'ai_billing_unavailable', 'Estimate generation is temporarily unavailable because the AI service has no API credits. Please contact support.') : timedOut ? new SafeServiceError(504, 'estimator_timeout', 'The estimate is taking longer than expected. Your completed work is saved for recovery.') : error instanceof SafeServiceError ? error : error instanceof JobPlanError
      ? new SafeServiceError(error.code === 'estimate_not_found' ? 404 : 503, error.code, error.message)
      : error instanceof EstimateError ? new SafeServiceError(503, 'residential_validation', 'The estimating service could not finish this attempt. Your completed work is saved for recovery.') : null;
    const validation = error instanceof RequestValidationError ? error : null;
    const code = safe?.code ?? (validation ? 'invalid_request' : 'internal_error');
    if (requestContext) await requestContext.admin.rpc('fail_ai_request', { p_user_id: requestContext.userId, p_request_id: requestContext.requestId, p_error_code: code });
    console.error('residential_estimator_failure',JSON.stringify({request_id:requestContext?.requestId,stage:activeStage,code,elapsed_ms:Date.now()-startedAt,detail:error instanceof EstimateError||error instanceof JobPlanError?(error as Error).message.slice(0,200):(error as Error)?.name??'UnknownError'}));
    return jsonResponse({ error: safe?.publicMessage ?? validation?.message ?? 'The estimate could not be completed. Please try again.', code }, safe?.status ?? validation?.status ?? 500);
  }
}

export const serveHandler = (req: Request) => jsonKeepalive(() => handler(req), corsHeaders);
Deno.serve(serveHandler);
