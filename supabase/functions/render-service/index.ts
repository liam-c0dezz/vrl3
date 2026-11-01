import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";

const AI_CONSENT_VERSION = "2026-07-31";
const DEFAULT_RENDER_MODEL = "gpt-5.6";
const MAX_IMAGE_BYTES = 8_000_000;
const MAX_PROMPT_LENGTH = 2_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type RenderOperation = "create" | "revise" | "accept";

type RenderRequest = {
  request_id: string;
  operation: RenderOperation;
  project_id: string;
  render_id?: string;
  prompt?: string;
  image_base64?: string;
  image_mime_type?: string;
};

type Reservation = {
  state: string;
  response?: Record<string, unknown> | null;
};

class PublicError extends Error {
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
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function parseRequest(raw: unknown): RenderRequest {
  if (!raw || typeof raw !== "object") {
    throw new PublicError(400, "invalid_request", "Invalid render request.");
  }
  const value = raw as Record<string, unknown>;
  if (!isUUID(value.request_id) || !isUUID(value.project_id)) {
    throw new PublicError(400, "invalid_request", "Invalid render request.");
  }
  if (!["create", "revise", "accept"].includes(String(value.operation))) {
    throw new PublicError(400, "invalid_request", "Invalid render operation.");
  }

  const operation = value.operation as RenderOperation;
  const prompt = typeof value.prompt === "string" ? value.prompt.trim() : "";
  if (operation !== "accept" && (prompt.length < 3 || prompt.length > MAX_PROMPT_LENGTH)) {
    throw new PublicError(
      400,
      "invalid_prompt",
      "Describe the remodel in a few words before generating a render.",
    );
  }
  if ((operation === "revise" || operation === "accept") && !isUUID(value.render_id)) {
    throw new PublicError(400, "invalid_request", "Select a render first.");
  }
  if (operation === "create") {
    if (typeof value.image_base64 !== "string" || value.image_base64.length === 0) {
      throw new PublicError(400, "missing_photo", "Add a project photo first.");
    }
    if (!["image/jpeg", "image/png"].includes(String(value.image_mime_type))) {
      throw new PublicError(400, "invalid_photo", "Use a JPEG or PNG photo.");
    }
  }

  return {
    request_id: value.request_id,
    project_id: value.project_id,
    operation,
    render_id: typeof value.render_id === "string" ? value.render_id : undefined,
    prompt: prompt || undefined,
    image_base64: typeof value.image_base64 === "string" ? value.image_base64 : undefined,
    image_mime_type: typeof value.image_mime_type === "string"
      ? value.image_mime_type
      : undefined,
  };
}

function decodeImage(encoded: string, mimeType: string): Uint8Array {
  if (encoded.length > Math.ceil(MAX_IMAGE_BYTES * 4 / 3) + 16) {
    throw new PublicError(413, "photo_too_large", "Choose a photo smaller than 8 MB.");
  }
  let binary: string;
  try {
    binary = atob(encoded);
  } catch {
    throw new PublicError(400, "invalid_photo", "The selected photo could not be read.");
  }
  if (binary.length > MAX_IMAGE_BYTES) {
    throw new PublicError(413, "photo_too_large", "Choose a photo smaller than 8 MB.");
  }
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  const isJPEG = bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff;
  const isPNG = bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47;
  if ((mimeType === "image/jpeg" && !isJPEG) || (mimeType === "image/png" && !isPNG)) {
    throw new PublicError(400, "invalid_photo", "The selected photo could not be verified.");
  }
  return bytes;
}

function encodeBase64(bytes: Uint8Array): string {
  let result = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    result += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(result);
}

async function safetyIdentifier(userId: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`easybid-render:${userId}`),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function reservationDenied(reservation: Reservation): Response | null {
  switch (reservation.state) {
    case "granted":
      return null;
    case "cached":
      return jsonResponse(reservation.response ?? { error: "Request already completed." });
    case "consent_required":
      return jsonResponse({ error: "AI consent is required.", code: "consent_required" }, 403);
    case "rate_limited":
    case "quota_exceeded":
      return jsonResponse({ error: "AI limit reached. Please try again later.", code: reservation.state }, 429);
    case "in_progress":
    case "busy":
      return jsonResponse({ error: "A render is already being generated.", code: reservation.state }, 409);
    case "disabled":
      return jsonResponse({ error: "AI rendering is temporarily unavailable.", code: "disabled" }, 503);
    default:
      return jsonResponse({ error: "This render request cannot be processed.", code: "request_failed" }, 400);
  }
}

async function generateRender(
  openAIKey: string,
  userId: string,
  prompt: string,
  sourceBytes: Uint8Array,
  sourceMimeType: string,
): Promise<Uint8Array> {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_RENDER_MODEL") ?? DEFAULT_RENDER_MODEL,
      store: false,
      safety_identifier: await safetyIdentifier(userId),
      instructions:
        "Create a photorealistic construction or remodel visualization by editing the supplied project photo. Preserve the camera angle, room geometry, doors, windows, and unrequested structural elements. Apply only the requested design changes. Do not add text, labels, logos, watermarks, people, or split-screen framing.",
      input: [{
        role: "user",
        content: [
          { type: "input_text", text: prompt },
          {
            type: "input_image",
            image_url: `data:${sourceMimeType};base64,${encodeBase64(sourceBytes)}`,
          },
        ],
      }],
      tools: [{ type: "image_generation", action: "edit", quality: "medium" }],
    }),
    signal: AbortSignal.timeout(120_000),
  });

  if (!response.ok) {
    console.error("OpenAI render failed", response.status);
    if (response.status === 400 || response.status === 403) {
      throw new PublicError(
        422,
        "render_not_generated",
        "That render could not be generated. Try a different photo or description.",
      );
    }
    throw new PublicError(
      503,
      "ai_temporarily_unavailable",
      "AI rendering is temporarily unavailable. Please try again.",
    );
  }

  const payload = await response.json() as {
    output?: Array<{ type?: string; result?: string }>;
  };
  const result = payload.output?.find((item) => item.type === "image_generation_call")?.result;
  if (!result) {
    throw new PublicError(502, "empty_render", "No render was returned. Please try again.");
  }
  return decodeImage(result, "image/png");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  let requestContext: { admin: ReturnType<typeof createClient>; userId: string; requestId: string } | null = null;
  try {
    const contentLength = Number(request.headers.get("Content-Length") ?? "0");
    if (Number.isFinite(contentLength) && contentLength > 12_000_000) {
      throw new PublicError(413, "request_too_large", "Choose a photo smaller than 8 MB.");
    }

    const supabaseURL = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const openAIKey = Deno.env.get("OPENAI_API_KEY");
    if (!supabaseURL || !serviceRoleKey || !openAIKey) {
      throw new Error("Render service environment is not configured");
    }
    const admin = createClient(supabaseURL, serviceRoleKey);
    const accessToken = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    if (!accessToken) return jsonResponse({ error: "Authentication required" }, 401);

    const { data: authData, error: authError } = await admin.auth.getUser(accessToken);
    if (authError || !authData.user) return jsonResponse({ error: "Invalid or expired session" }, 401);
    const userId = authData.user.id;
    const body = parseRequest(await request.json());

    const { data: project, error: projectError } = await admin
      .from("projects")
      .select("id, organization_id")
      .eq("id", body.project_id)
      .maybeSingle();
    if (projectError || !project) return jsonResponse({ error: "Project not found" }, 404);

    const { data: membership } = await admin
      .from("organization_members")
      .select("user_id")
      .eq("organization_id", project.organization_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (!membership) return jsonResponse({ error: "You do not have access to this project" }, 403);

    let existingRender: Record<string, string | null> | null = null;
    if (body.render_id) {
      const { data, error } = await admin
        .from("project_renders")
        .select("id, project_id, original_image_path, current_image_path, accepted_image_path, initial_prompt, status")
        .eq("id", body.render_id)
        .eq("project_id", body.project_id)
        .maybeSingle();
      if (error || !data) return jsonResponse({ error: "Render not found" }, 404);
      existingRender = data;
    }

    if (body.operation === "accept") {
      const acceptedPath = existingRender!.current_image_path;
      const { data: accepted, error } = await admin
        .from("project_renders")
        .update({
          accepted_image_path: acceptedPath,
          status: "accepted",
          accepted_at: new Date().toISOString(),
        })
        .eq("id", body.render_id!)
        .select()
        .single();
      if (error) throw new Error("Render acceptance failed");
      return jsonResponse({ render: accepted });
    }

    const { data: reservationData, error: reservationError } = await admin.rpc(
      "reserve_ai_request",
      {
        p_user_id: userId,
        p_request_id: body.request_id,
        p_uses_ai: true,
        p_consent_version: AI_CONSENT_VERSION,
        p_ip_hash: null,
      },
    );
    if (reservationError || !reservationData) throw new Error("AI reservation failed");
    const denied = reservationDenied(reservationData as Reservation);
    if (denied) return denied;
    requestContext = { admin, userId, requestId: body.request_id };

    let sourceBytes: Uint8Array;
    let sourceMimeType: string;
    let renderId: string;
    let originalPath: string;

    if (body.operation === "create") {
      sourceMimeType = body.image_mime_type!;
      sourceBytes = decodeImage(body.image_base64!, sourceMimeType);
      renderId = crypto.randomUUID();
      const extensionName = sourceMimeType === "image/png" ? "png" : "jpg";
      originalPath = `${project.organization_id}/${body.project_id}/renders/${renderId}/before.${extensionName}`;
      const { error } = await admin.storage.from("project-files").upload(
        originalPath,
        sourceBytes,
        { contentType: sourceMimeType, upsert: false },
      );
      if (error) throw new Error("Original render upload failed");
    } else {
      renderId = body.render_id!;
      originalPath = existingRender!.original_image_path!;
      const { data, error } = await admin.storage
        .from("project-files")
        .download(existingRender!.current_image_path!);
      if (error || !data) throw new Error("Current render download failed");
      sourceBytes = new Uint8Array(await data.arrayBuffer());
      sourceMimeType = existingRender!.current_image_path!.endsWith(".png")
        ? "image/png"
        : "image/jpeg";
    }

    const generatedBytes = await generateRender(
      openAIKey,
      userId,
      body.prompt!,
      sourceBytes,
      sourceMimeType,
    );
    const generatedPath = `${project.organization_id}/${body.project_id}/renders/${renderId}/${crypto.randomUUID()}.png`;
    const { error: uploadError } = await admin.storage.from("project-files").upload(
      generatedPath,
      generatedBytes,
      { contentType: "image/png", upsert: false },
    );
    if (uploadError) throw new Error("Generated render upload failed");

    let savedRender: Record<string, unknown>;
    if (body.operation === "create") {
      const { data, error } = await admin.from("project_renders").insert({
        id: renderId,
        organization_id: project.organization_id,
        project_id: body.project_id,
        original_image_path: originalPath,
        current_image_path: generatedPath,
        initial_prompt: body.prompt,
        status: "draft",
        created_by: userId,
      }).select().single();
      if (error || !data) throw new Error("Render save failed");
      savedRender = data;
    } else {
      const { data, error } = await admin.from("project_renders").update({
        current_image_path: generatedPath,
        accepted_image_path: null,
        accepted_at: null,
        status: "draft",
      }).eq("id", renderId).select().single();
      if (error || !data) throw new Error("Render revision save failed");
      savedRender = data;
    }

    const messageRows = [{
      organization_id: project.organization_id,
      render_id: renderId,
      role: "user",
      content: body.prompt,
      image_path: null,
    }, {
      organization_id: project.organization_id,
      render_id: renderId,
      role: "assistant",
      content: body.operation === "create" ? "Created render" : "Updated render",
      image_path: generatedPath,
    }];
    const { error: messageError } = await admin.from("render_messages").insert(messageRows);
    if (messageError) console.error("Render message save failed", messageError.code);

    const payload = { render: savedRender };
    const { data: completed, error: completionError } = await admin.rpc(
      "complete_ai_request",
      {
        p_user_id: userId,
        p_request_id: body.request_id,
        p_response_body: payload,
      },
    );
    if (completionError || completed !== true) throw new Error("AI request completion failed");
    requestContext = null;
    return jsonResponse(payload);
  } catch (error) {
    const publicError = error instanceof PublicError ? error : null;
    const errorCode = publicError?.code ?? "internal_error";
    if (requestContext) {
      await requestContext.admin.rpc("fail_ai_request", {
        p_user_id: requestContext.userId,
        p_request_id: requestContext.requestId,
        p_error_code: errorCode,
      });
    }
    if (!publicError) console.error("render-service internal failure", (error as Error)?.message);
    return jsonResponse(
      {
        error: publicError?.publicMessage ?? "Something went wrong. Please try again.",
        code: errorCode,
      },
      publicError?.status ?? 500,
    );
  }
});
