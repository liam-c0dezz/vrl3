// retention-dispatch
//
// Called by pg_cron every 10 minutes and immediately by a database trigger
// when a client views, approves or requests changes on an estimate.
//
//  - Delivers queued pushes through APNs (HTTP/2, token auth), honoring each
//    user's frequency, quiet hours and time zone, and removing dead tokens.
//  - Sends lifecycle email (welcome, day-3 tip, trial ending, win-back).
//  - GET ?unsubscribe=<token> turns off tips and product email.
//
// Deploy:  supabase functions deploy retention-dispatch --no-verify-jwt
// Secrets: APNS_KEY_ID, APNS_PRIVATE_KEY (APNs .p8). Optional: RESEND_API_KEY,
//          EMAIL_FROM. Missing secrets turn that channel off; nothing breaks.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";
import {
  allowsPush,
  apnsPayload,
  constantTimeEqual,
  DEFAULT_PREFERENCES,
  dueEmail,
  type EmailCandidate,
  emailContent,
  emailHTML,
  emailText,
  type Frequency,
  isDeadToken,
  type Language,
  nextAllowedSendTime,
  type Preferences,
  pushCopy,
  type PushKind,
  unsubscribeToken,
  variantFor,
  verifyUnsubscribeToken,
} from "./logic.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? Deno.env.get("APPLE_TEAM_ID") ?? "5WLL25W3WQ";
const APNS_TOPIC = Deno.env.get("APNS_TOPIC") ?? "com.constructionestimate.Construction-Estimate";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const EMAIL_FROM = Deno.env.get("EMAIL_FROM") ?? "";
const APP_URL = Deno.env.get("RETENTION_APP_URL") ?? "https://easybid.viralappdev.com";
const TRIAL_DAYS = Number(Deno.env.get("TRIAL_DAYS") ?? "3") || 3;
const FUNCTION_URL = `${SUPABASE_URL}/functions/v1/retention-dispatch`;

const MAX_PUSHES_PER_RUN = 200;
const MAX_EMAILS_PER_RUN = 100;
const PUSH_EXPIRY_MS = 3 * 86_400_000;

type Config = { dispatch_secret: string; unsubscribe_secret: string };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function html(body: string, status = 200): Response {
  return new Response(
    `<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>EasyBid</title></head><body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:40px 24px;max-width:480px;margin:auto;color:#141419">${body}</body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } },
  );
}

async function loadConfig(admin: SupabaseClient): Promise<Config | null> {
  const { data, error } = await admin.rpc("retention_dispatch_config");
  if (error || !data?.dispatch_secret) return null;
  return data as Config;
}

// ---------------------------------------------------------------------------
// APNs
// ---------------------------------------------------------------------------

let cachedJWT: { token: string; issuedAt: number } | null = null;

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

function pemToPKCS8(pem: string): ArrayBuffer {
  const body = pem.replaceAll("\\n", "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0)).buffer as ArrayBuffer;
}

/** Provider token, reused for 50 minutes (Apple allows up to 60). */
async function apnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 50 * 60) return cachedJWT.token;
  const header = base64url(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID }));
  const claims = base64url(JSON.stringify({ iss: APNS_TEAM_ID, iat: now }));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPKCS8(APNS_PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  cachedJWT = { token: `${header}.${claims}.${base64url(signature)}`, issuedAt: now };
  return cachedJWT.token;
}

async function sendAPNs(
  device: { token: string; environment: string; bundle_id: string },
  payload: unknown,
  collapseId: string,
): Promise<{ ok: boolean; status: number; reason?: string }> {
  const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const response = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsJWT()}`,
      "apns-topic": device.bundle_id || APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 86_400),
      "apns-collapse-id": collapseId.slice(0, 64),
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (response.ok) return { ok: true, status: response.status };
  const reason = await response.json().then((body) => body?.reason as string | undefined).catch(() => undefined);
  return { ok: false, status: response.status, reason };
}

// ---------------------------------------------------------------------------
// Pushes
// ---------------------------------------------------------------------------

interface OutboxRow {
  id: string;
  user_id: string;
  kind: PushKind;
  data: { estimate_number?: string; approved_by?: string };
  attempts: number;
  created_at: string;
  dedupe_key: string;
}

async function deliverPushes(admin: SupabaseClient) {
  const result = { sent: 0, delayed: 0, skipped: 0, failed: 0 };
  const now = new Date();
  const { data: due, error } = await admin
    .from("notification_outbox")
    .select("id, user_id, kind, data, attempts, created_at, dedupe_key")
    .eq("status", "pending")
    .lte("send_after", now.toISOString())
    .order("send_after")
    .limit(MAX_PUSHES_PER_RUN);
  if (error || !due?.length) return result;

  const rows = due as OutboxRow[];
  const userIds = [...new Set(rows.map((row) => row.user_id))];
  const [{ data: profiles }, { data: devices }] = await Promise.all([
    admin.from("retention_profiles")
      .select("user_id, timezone, language, quiet_start, quiet_end, frequency")
      .in("user_id", userIds),
    admin.from("push_devices").select("token, user_id, environment, bundle_id").in("user_id", userIds),
  ]);
  const prefsByUser = new Map<string, Preferences>();
  for (const profile of profiles ?? []) {
    prefsByUser.set(profile.user_id, {
      timezone: profile.timezone,
      language: (profile.language === "es" ? "es" : "en") as Language,
      quietStart: profile.quiet_start,
      quietEnd: profile.quiet_end,
      frequency: profile.frequency as Frequency,
    });
  }
  const devicesByUser = new Map<string, { token: string; environment: string; bundle_id: string }[]>();
  for (const device of devices ?? []) {
    devicesByUser.set(device.user_id, [...(devicesByUser.get(device.user_id) ?? []), device]);
  }

  const apnsReady = Boolean(APNS_KEY_ID && APNS_PRIVATE_KEY);

  for (const row of rows) {
    const finish = (status: "sent" | "skipped" | "failed", lastError: string | null, variant?: string) =>
      admin.from("notification_outbox").update({
        status,
        last_error: lastError,
        variant: variant ?? null,
        sent_at: status === "sent" ? new Date().toISOString() : null,
        attempts: row.attempts + 1,
      }).eq("id", row.id).eq("status", "pending");

    const prefs = prefsByUser.get(row.user_id) ?? DEFAULT_PREFERENCES;
    if (now.getTime() - Date.parse(row.created_at) > PUSH_EXPIRY_MS) {
      await finish("skipped", "expired");
      result.skipped++;
      continue;
    }
    if (!allowsPush(row.kind, prefs.frequency)) {
      await finish("skipped", "user_turned_off");
      result.skipped++;
      continue;
    }
    const sendAt = nextAllowedSendTime(now, prefs);
    if (sendAt.getTime() > now.getTime()) {
      await admin.from("notification_outbox").update({ send_after: sendAt.toISOString() }).eq("id", row.id);
      result.delayed++;
      continue;
    }
    const userDevices = devicesByUser.get(row.user_id) ?? [];
    if (!apnsReady || userDevices.length === 0) {
      await finish("skipped", apnsReady ? "no_devices" : "apns_not_configured");
      result.skipped++;
      continue;
    }

    const variant = variantFor(row.user_id, row.kind);
    const payload = apnsPayload(pushCopy(row.kind, variant, prefs.language, row.data ?? {}), row.kind, variant);
    let delivered = 0;
    let lastError: string | null = null;
    for (const device of userDevices) {
      try {
        const response = await sendAPNs(device, payload, row.dedupe_key);
        if (response.ok) {
          delivered++;
        } else {
          lastError = `${response.status} ${response.reason ?? ""}`.trim();
          if (isDeadToken(response.status, response.reason)) {
            await admin.from("push_devices").delete().eq("token", device.token);
          }
        }
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
      }
    }
    if (delivered > 0) {
      await finish("sent", null, variant);
      result.sent++;
    } else if (row.attempts + 1 >= 5) {
      await finish("failed", lastError, variant);
      result.failed++;
    } else {
      await admin.from("notification_outbox").update({
        attempts: row.attempts + 1,
        last_error: lastError,
        send_after: new Date(now.getTime() + 15 * 60_000).toISOString(),
      }).eq("id", row.id);
      result.failed++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Lifecycle email (Resend). Off until RESEND_API_KEY and EMAIL_FROM are set.
// ---------------------------------------------------------------------------

async function sendLifecycleEmail(admin: SupabaseClient, config: Config) {
  const result = { sent: 0, skipped: !RESEND_API_KEY || !EMAIL_FROM };
  if (result.skipped) return result;

  const { data, error } = await admin.rpc("retention_email_candidates", { p_limit: 300 });
  if (error || !data) return result;
  const now = new Date();

  for (const candidate of data as EmailCandidate[]) {
    if (result.sent >= MAX_EMAILS_PER_RUN) break;
    const kind = dueEmail(candidate, now, TRIAL_DAYS);
    if (!kind) continue;

    // Claim first so two overlapping runs never send the same email twice.
    const { data: claimed } = await admin
      .from("lifecycle_emails")
      .upsert({ user_id: candidate.user_id, kind }, { onConflict: "user_id,kind", ignoreDuplicates: true })
      .select("user_id");
    if (!claimed?.length) continue;

    const language: Language = candidate.language === "es" ? "es" : "en";
    const content = emailContent(kind, language, TRIAL_DAYS);
    const unsubscribeURL = content.marketing
      ? `${FUNCTION_URL}?unsubscribe=${encodeURIComponent(await unsubscribeToken(candidate.user_id, config.unsubscribe_secret))}`
      : null;

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: EMAIL_FROM,
        to: [candidate.email],
        subject: content.subject,
        html: emailHTML(content, APP_URL, unsubscribeURL, language),
        text: emailText(content, APP_URL, unsubscribeURL, language),
        headers: unsubscribeURL
          ? { "List-Unsubscribe": `<${unsubscribeURL}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click" }
          : undefined,
        tags: [{ name: "kind", value: kind }],
      }),
    }).catch(() => null);

    if (response?.ok) {
      result.sent++;
    } else {
      // Release the claim so the next run retries.
      await admin.from("lifecycle_emails").delete().eq("user_id", candidate.user_id).eq("kind", kind);
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (request) => {
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) return json({ error: "misconfigured" }, 500);
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
  const config = await loadConfig(admin);
  if (!config) return json({ error: "run the retention migration first" }, 503);

  const url = new URL(request.url);
  const unsubscribe = url.searchParams.get("unsubscribe");
  if (unsubscribe) {
    const userId = await verifyUnsubscribeToken(unsubscribe, config.unsubscribe_secret);
    if (!userId) return html("<h2>This link is no longer valid.</h2>", 400);
    const { data: profile } = await admin
      .from("retention_profiles")
      .update({ email_opt_in: false, updated_at: new Date().toISOString() })
      .eq("user_id", userId)
      .select("language")
      .maybeSingle();
    await admin.from("engagement_events").insert({ user_id: userId, event: "email_unsubscribed" });
    return profile?.language === "es"
      ? html("<h2>Te diste de baja.</h2><p>Ya no recibirás consejos ni correos de producto de EasyBid. Los correos de tu cuenta y de tu prueba seguirán llegando.</p>")
      : html("<h2>You're unsubscribed.</h2><p>You won't get tips or product emails from EasyBid. Account and trial emails still arrive.</p>");
  }

  if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
  const secret = request.headers.get("x-retention-secret") ?? "";
  if (!constantTimeEqual(secret, config.dispatch_secret)) return json({ error: "forbidden" }, 403);

  const [pushes, email] = await Promise.all([
    deliverPushes(admin),
    sendLifecycleEmail(admin, config),
  ]);
  return json({ pushes, email });
});
