// Pure helpers for retention-dispatch. No Deno or network APIs, so they are
// unit-tested with `node --experimental-strip-types logic.test.ts`.

export type Language = "en" | "es";
export type Frequency = "all" | "important" | "off";
export type PushKind = "client_viewed" | "client_approved" | "client_changes_requested";
export type EmailKind = "welcome" | "day3_tip" | "trial_ending" | "win_back";

export interface Preferences {
  timezone: string;
  language: Language;
  quietStart: number;
  quietEnd: number;
  frequency: Frequency;
}

export const DEFAULT_PREFERENCES: Preferences = {
  timezone: "America/Denver",
  language: "en",
  quietStart: 21,
  quietEnd: 8,
  frequency: "all",
};

// ---------------------------------------------------------------------------
// Time zones and quiet hours
// ---------------------------------------------------------------------------

export function safeTimeZone(timeZone: string | null | undefined): string {
  if (!timeZone) return DEFAULT_PREFERENCES.timezone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone }).format(new Date());
    return timeZone;
  } catch {
    return DEFAULT_PREFERENCES.timezone;
  }
}

export function localHour(date: Date, timeZone: string): number {
  const hour = new Intl.DateTimeFormat("en-US", {
    timeZone: safeTimeZone(timeZone),
    hour: "numeric",
    hourCycle: "h23",
  }).format(date);
  return Number.parseInt(hour, 10) % 24;
}

export function isQuietHour(hour: number, quietStart: number, quietEnd: number): boolean {
  if (quietStart === quietEnd) return false;
  if (quietStart < quietEnd) return hour >= quietStart && hour < quietEnd;
  return hour >= quietStart || hour < quietEnd;
}

/** Earliest moment at or after `now` outside quiet hours in the user's zone. */
export function nextAllowedSendTime(now: Date, prefs: Preferences): Date {
  if (!isQuietHour(localHour(now, prefs.timezone), prefs.quietStart, prefs.quietEnd)) return now;
  const start = new Date(now);
  start.setUTCMinutes(0, 0, 0);
  for (let step = 1; step <= 26; step++) {
    const candidate = new Date(start.getTime() + step * 3_600_000);
    if (!isQuietHour(localHour(candidate, prefs.timezone), prefs.quietStart, prefs.quietEnd)) {
      return candidate;
    }
  }
  return now;
}

// ---------------------------------------------------------------------------
// Push copy (English / Spanish, two variants each for copy tests)
// ---------------------------------------------------------------------------

/** Stable 50/50 split per user and kind, so opens can be compared by variant. */
export function variantFor(userId: string, kind: string): "a" | "b" {
  let hash = 0;
  for (const char of `${userId}:${kind}`) {
    hash = (hash * 31 + char.charCodeAt(0)) & 0x7fffffff;
  }
  return hash % 2 === 0 ? "a" : "b";
}

export function allowsPush(kind: PushKind, frequency: Frequency): boolean {
  // Client activity counts as "important"; only "off" silences it.
  void kind;
  return frequency !== "off";
}

export interface PushCopy {
  title: string;
  body: string;
}

export function pushCopy(
  kind: PushKind,
  variant: "a" | "b",
  language: Language,
  data: { estimate_number?: string; approved_by?: string },
): PushCopy {
  const es = language === "es";
  const estimate = data.estimate_number?.trim() || (es ? "tu cotización" : "your estimate");
  const who = data.approved_by?.trim() || (es ? "Tu cliente" : "Your client");

  switch (kind) {
    case "client_approved":
      return variant === "a"
        ? {
          title: es ? "Cotización aprobada ✅" : "Estimate approved ✅",
          body: es
            ? `${who} aprobó ${estimate}. Envía la factura mientras está reciente.`
            : `${who} approved ${estimate}. Send the invoice while it's fresh.`,
        }
        : {
          title: es ? `${estimate} fue aprobada` : `${estimate} was approved`,
          body: es ? "Tu cliente dijo que sí. Toca para empezar a cobrar." : "Your client said yes. Tap to start billing.",
        };
    case "client_viewed":
      return variant === "a"
        ? {
          title: es ? "Abrieron tu cotización" : "Your estimate was opened",
          body: es
            ? `Tu cliente acaba de ver ${estimate}. Un seguimiento rápido ayuda a cerrarla.`
            : `Your client just viewed ${estimate}. A quick follow-up helps close it.`,
        }
        : {
          title: es ? `${estimate} vista` : `${estimate} viewed`,
          body: es ? "Tu cliente la está revisando ahora." : "Your client is looking at it now.",
        };
    case "client_changes_requested":
      return variant === "a"
        ? {
          title: es ? "Cambios solicitados" : "Changes requested",
          body: es ? `Tu cliente pidió cambios en ${estimate}.` : `Your client asked for changes to ${estimate}.`,
        }
        : {
          title: es ? `${estimate} necesita cambios` : `${estimate} needs changes`,
          body: es ? "Ábrela para ver lo que pidió tu cliente." : "Open it to see what your client asked for.",
        };
  }
}

export function apnsPayload(copy: PushCopy, kind: PushKind, variant: string, badge?: number) {
  return {
    aps: {
      alert: { title: copy.title, body: copy.body },
      sound: "default",
      "thread-id": "client_activity",
      category: "client_activity",
      ...(badge === undefined ? {} : { badge }),
    },
    route: "notifications",
    category: "client_activity",
    kind,
    variant,
  };
}

/** APNs responses that mean the token will never work again. */
export function isDeadToken(status: number, reason: string | undefined): boolean {
  return status === 410 ||
    (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"));
}

// ---------------------------------------------------------------------------
// Lifecycle email rules
// ---------------------------------------------------------------------------

export interface EmailCandidate {
  user_id: string;
  email: string;
  signed_up_at: string;
  language: string;
  timezone: string;
  email_opt_in: boolean;
  trial_started_at: string | null;
  last_active_at: string;
  sent_kinds: string[];
}

const DAY = 86_400_000;

/** Which email (if any) is due now. Trial-ending is always sent. */
export function dueEmail(candidate: EmailCandidate, now: Date, trialDays: number): EmailKind | null {
  const sent = new Set(candidate.sent_kinds ?? []);
  const hour = localHour(now, candidate.timezone);
  const daytime = hour >= 9 && hour < 18;
  const awake = hour >= 8 && hour < 21;
  const signedUp = Date.parse(candidate.signed_up_at);
  const lastActive = Date.parse(candidate.last_active_at);
  const age = now.getTime() - signedUp;

  if (candidate.trial_started_at && !sent.has("trial_ending") && awake) {
    const trialStart = Date.parse(candidate.trial_started_at);
    const reminderAt = trialStart + (trialDays - 1) * DAY;
    const trialEnd = trialStart + trialDays * DAY;
    if (now.getTime() >= reminderAt && now.getTime() < trialEnd) return "trial_ending";
  }
  if (!sent.has("welcome") && age < 2 * DAY) return "welcome";
  if (!candidate.email_opt_in) return null;
  if (!sent.has("day3_tip") && age >= 3 * DAY && age < 10 * DAY && daytime) return "day3_tip";
  if (!sent.has("win_back") && now.getTime() - lastActive > 21 * DAY && age > 21 * DAY && daytime) return "win_back";
  return null;
}

export interface EmailContent {
  subject: string;
  heading: string;
  paragraphs: string[];
  cta: string;
  marketing: boolean;
}

export function emailContent(kind: EmailKind, language: Language, trialDays: number): EmailContent {
  const es = language === "es";
  switch (kind) {
    case "welcome":
      return {
        subject: es ? "Bienvenido a EasyBid" : "Welcome to EasyBid",
        heading: es ? "Tu primera cotización en minutos" : "Your first estimate in minutes",
        paragraphs: es
          ? [
            "Toma una foto del trabajo, agrega una nota de voz o unas palabras y EasyBid prepara una cotización detallada con precios locales.",
            "Cuando tu cliente la abra o la apruebe, te avisaremos al instante.",
          ]
          : [
            "Snap a photo of the job, add a voice note or a few words, and EasyBid builds a detailed estimate with local pricing.",
            "When your client opens or approves it, we'll let you know right away.",
          ],
        cta: es ? "Crear una cotización" : "Create an estimate",
        marketing: false,
      };
    case "day3_tip":
      return {
        subject: es ? "Un consejo para ganar más trabajos" : "One tip to win more jobs",
        heading: es ? "Envía la cotización antes de irte" : "Send the estimate before you leave",
        paragraphs: es
          ? [
            "Los contratistas que envían la cotización el mismo día ganan más trabajos. Desde la obra, crea la cotización y envíala por mensaje o correo con un enlace para aprobar.",
            "Tu cliente puede aprobarla desde su teléfono y tú recibes el aviso.",
          ]
          : [
            "Contractors who send the estimate the same day win more jobs. Build it on site and send it by text or email with a one-tap approval link.",
            "Your client approves from their phone, and you get notified.",
          ],
        cta: es ? "Abrir EasyBid" : "Open EasyBid",
        marketing: true,
      };
    case "trial_ending":
      return {
        subject: es ? "Tu prueba gratuita termina mañana" : "Your free trial ends tomorrow",
        heading: es ? "Tu prueba termina mañana" : "Your trial ends tomorrow",
        paragraphs: es
          ? [
            `Tu prueba gratuita de ${trialDays} días termina mañana. Si no haces nada, tu suscripción continúa y conservas todas tus cotizaciones, clientes y facturas.`,
            "Para administrar o cancelar: abre Ajustes del iPhone, toca tu nombre, elige Suscripciones y selecciona EasyBid.",
          ]
          : [
            `Your ${trialDays}-day free trial ends tomorrow. If you do nothing, your subscription continues and you keep all your estimates, clients and invoices.`,
            "To manage or cancel: open iPhone Settings, tap your name, choose Subscriptions, then select EasyBid.",
          ],
        cta: es ? "Abrir EasyBid" : "Open EasyBid",
        marketing: false,
      };
    case "win_back":
      return {
        subject: es ? "Tus clientes siguen esperando cotizaciones" : "Your next bid is a photo away",
        heading: es ? "Vuelve a cotizar en minutos" : "Get back to bidding in minutes",
        paragraphs: es
          ? [
            "Tus proyectos y clientes siguen en EasyBid. Toma una foto del próximo trabajo y tendrás una cotización lista para enviar en menos de un minuto.",
          ]
          : [
            "Your projects and clients are still in EasyBid. Snap a photo of your next job and you'll have an estimate ready to send in under a minute.",
          ],
        cta: es ? "Volver a EasyBid" : "Return to EasyBid",
        marketing: true,
      };
  }
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, (char) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]!
  );
}

export function emailHTML(content: EmailContent, ctaURL: string, unsubscribeURL: string | null, language: Language): string {
  const es = language === "es";
  const paragraphs = content.paragraphs
    .map((text) => `<p style="margin:0 0 14px;font-size:16px;line-height:1.5;color:#4D4D54">${escapeHTML(text)}</p>`)
    .join("");
  const footer = unsubscribeURL
    ? `<p style="margin:24px 0 0;font-size:12px;color:#8E8E93">${
      es ? "¿No quieres estos correos?" : "Don't want these emails?"
    } <a href="${escapeHTML(unsubscribeURL)}" style="color:#8E8E93">${es ? "Darse de baja" : "Unsubscribe"}</a></p>`
    : "";
  return `<!DOCTYPE html><html lang="${language}"><body style="margin:0;background:#F2F4F7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#FFFFFF;border-radius:16px;overflow:hidden">
<tr><td style="background:linear-gradient(#0B2E5A,#347FE5);background-color:#1D5297;padding:22px 28px;color:#FFFFFF;font-size:20px;font-weight:700">EasyBid</td></tr>
<tr><td style="padding:28px">
<h1 style="margin:0 0 16px;font-size:22px;line-height:1.3;color:#141419">${escapeHTML(content.heading)}</h1>
${paragraphs}
<a href="${escapeHTML(ctaURL)}" style="display:inline-block;margin-top:8px;background:#1D5297;color:#FFFFFF;text-decoration:none;font-weight:600;font-size:16px;padding:13px 22px;border-radius:999px">${escapeHTML(content.cta)}</a>
${footer}
</td></tr></table></td></tr></table></body></html>`;
}

export function emailText(content: EmailContent, ctaURL: string, unsubscribeURL: string | null, language: Language): string {
  const lines = [content.heading, "", ...content.paragraphs, "", `${content.cta}: ${ctaURL}`];
  if (unsubscribeURL) {
    lines.push("", `${language === "es" ? "Darse de baja" : "Unsubscribe"}: ${unsubscribeURL}`);
  }
  return lines.join("\n");
}

// ---------------------------------------------------------------------------
// Unsubscribe tokens (HMAC-SHA256 of the user id)
// ---------------------------------------------------------------------------

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

async function hmac(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return base64url(new Uint8Array(signature));
}

export async function unsubscribeToken(userId: string, secret: string): Promise<string> {
  return `${userId}.${await hmac(secret, `unsubscribe:${userId}`)}`;
}

export function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let index = 0; index < a.length; index++) diff |= a.charCodeAt(index) ^ b.charCodeAt(index);
  return diff === 0;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function verifyUnsubscribeToken(token: string, secret: string): Promise<string | null> {
  const [userId, signature] = token.split(".");
  if (!userId || !signature || !UUID_PATTERN.test(userId)) return null;
  const expected = await hmac(secret, `unsubscribe:${userId}`);
  return constantTimeEqual(signature, expected) ? userId : null;
}
