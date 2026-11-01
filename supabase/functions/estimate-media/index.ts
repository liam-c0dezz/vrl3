import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function isUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") return json("Not found.", 404);

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) return json("Media is unavailable.", 503);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json("Invalid media request.", 400);
  }

  const token = typeof body.token === "string" ? body.token : "";
  const mediaID = body.media_id;
  if (!/^[0-9a-f]{64}$/.test(token) || !isUUID(mediaID)) {
    return json("Invalid media request.", 400);
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const tokenHash = await sha256(token);
  const { data: share, error: shareError } = await admin
    .from("estimate_share_links")
    .select("estimate_id, status, expires_at")
    .eq("token_hash", tokenHash)
    .neq("status", "revoked")
    .maybeSingle();

  if (shareError || !share || new Date(share.expires_at).getTime() <= Date.now()) {
    return json("This estimate media is no longer available.", 404);
  }

  const { data: media, error: mediaError } = await admin
    .from("estimate_media")
    .select("storage_path, render_id, mime_type")
    .eq("id", mediaID)
    .eq("estimate_id", share.estimate_id)
    .maybeSingle();
  if (mediaError || !media) return json("Media not found.", 404);

  let storagePath = media.storage_path as string | null;
  if (!storagePath && media.render_id) {
    const { data: render } = await admin
      .from("project_renders")
      .select("accepted_image_path, current_image_path")
      .eq("id", media.render_id)
      .maybeSingle();
    storagePath = render?.accepted_image_path ?? render?.current_image_path ?? null;
  }
  if (!storagePath) return json("Media not found.", 404);

  const { data: file, error: downloadError } = await admin.storage
    .from("project-files")
    .download(storagePath);
  if (downloadError || !file) return json("Media not found.", 404);

  return new Response(await file.arrayBuffer(), {
    status: 200,
    headers: {
      ...corsHeaders,
      "Content-Type": media.mime_type || file.type || "image/jpeg",
      "Content-Length": String(file.size),
      "Cache-Control": "private, no-store, max-age=0",
      "Content-Disposition": "inline",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "no-referrer",
    },
  });
});
