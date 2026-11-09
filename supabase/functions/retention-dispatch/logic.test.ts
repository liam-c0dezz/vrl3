// Run: node --experimental-strip-types logic.test.ts
import assert from "node:assert/strict";
import {
  allowsPush, apnsPayload, dueEmail, emailContent, emailHTML, isDeadToken, isQuietHour, localHour,
  nextAllowedSendTime, pushCopy, unsubscribeToken, variantFor, verifyUnsubscribeToken, DEFAULT_PREFERENCES,
} from "./logic.ts";

let passed = 0;
const test = async (name: string, fn: () => void | Promise<void>) => { await fn(); passed++; console.log("ok -", name); };

await test("quiet hours wrap past midnight", () => {
  assert.equal(isQuietHour(22, 21, 8), true);
  assert.equal(isQuietHour(3, 21, 8), true);
  assert.equal(isQuietHour(8, 21, 8), false);
  assert.equal(isQuietHour(12, 21, 8), false);
  assert.equal(isQuietHour(13, 12, 14), true);
  assert.equal(isQuietHour(5, 5, 5), false);
});

await test("local hour follows the user's time zone", () => {
  const noonUTC = new Date("2026-11-03T12:00:00Z");
  assert.equal(localHour(noonUTC, "UTC"), 12);
  assert.equal(localHour(noonUTC, "America/Denver"), 5);
  assert.equal(localHour(noonUTC, "Europe/Madrid"), 13);
  assert.equal(localHour(noonUTC, "Not/AZone"), 5); // falls back to the default zone
});

await test("a 2 AM approval waits until quiet hours end at 8 AM local", () => {
  const prefs = { ...DEFAULT_PREFERENCES, timezone: "America/Chicago" };
  const twoAM = new Date("2026-11-03T08:00:00Z"); // 2 AM in Chicago (CST)
  const sendAt = nextAllowedSendTime(twoAM, prefs);
  assert.equal(localHour(sendAt, "America/Chicago"), 8);
  assert.equal(sendAt.toISOString(), "2026-11-03T14:00:00.000Z");
  const tenAM = new Date("2026-11-03T16:00:00Z");
  assert.equal(nextAllowedSendTime(tenAM, prefs).getTime(), tenAM.getTime());
});

await test("copy variants are stable and split users", () => {
  assert.equal(variantFor("user-1", "client_approved"), variantFor("user-1", "client_approved"));
  const counts = { a: 0, b: 0 };
  for (let i = 0; i < 400; i++) counts[variantFor(`00000000-0000-0000-0000-${String(i).padStart(12, "0")}`, "client_approved")]++;
  assert.ok(counts.a > 120 && counts.b > 120, JSON.stringify(counts));
});

await test("push copy is localized and fills in the estimate and client", () => {
  const en = pushCopy("client_approved", "a", "en", { estimate_number: "EST-1042", approved_by: "Daniel" });
  assert.equal(en.title, "Estimate approved ✅");
  assert.equal(en.body, "Daniel approved EST-1042. Send the invoice while it's fresh.");
  const es = pushCopy("client_viewed", "b", "es", { estimate_number: "EST-7" });
  assert.equal(es.title, "EST-7 vista");
  const fallback = pushCopy("client_approved", "a", "es", {});
  assert.match(fallback.body, /^Tu cliente aprobó tu cotización/);
  for (const kind of ["client_viewed", "client_approved", "client_changes_requested"] as const)
    for (const v of ["a", "b"] as const) for (const l of ["en", "es"] as const) {
      const c = pushCopy(kind, v, l, { estimate_number: "EST-1" });
      assert.ok(c.title.length > 0 && c.title.length <= 60 && c.body.length <= 160, `${kind}/${v}/${l}`);
    }
});

await test("frequency: client activity is important; only 'off' silences it", () => {
  assert.equal(allowsPush("client_viewed", "all"), true);
  assert.equal(allowsPush("client_viewed", "important"), true);
  assert.equal(allowsPush("client_approved", "off"), false);
});

await test("APNs payload routes taps to notifications and carries the variant", () => {
  const p = apnsPayload({ title: "t", body: "b" }, "client_approved", "b");
  assert.equal(p.route, "notifications");
  assert.equal(p.variant, "b");
  assert.equal(p.aps.category, "client_activity");
  assert.equal(isDeadToken(410, undefined), true);
  assert.equal(isDeadToken(400, "BadDeviceToken"), true);
  assert.equal(isDeadToken(403, "InvalidProviderToken"), false);
});

const base = {
  user_id: "11111111-1111-1111-1111-111111111111", email: "a@b.co", language: "en", timezone: "UTC",
  email_opt_in: true, trial_started_at: null as string | null, sent_kinds: [] as string[],
};
const now = new Date("2026-11-03T12:00:00Z");
const ago = (days: number) => new Date(now.getTime() - days * 86_400_000).toISOString();

await test("lifecycle email schedule: welcome, day-3 tip, trial ending, win-back", () => {
  assert.equal(dueEmail({ ...base, signed_up_at: ago(0.1), last_active_at: ago(0) }, now, 3), "welcome");
  assert.equal(dueEmail({ ...base, signed_up_at: ago(4), last_active_at: ago(1), sent_kinds: ["welcome"] }, now, 3), "day3_tip");
  assert.equal(dueEmail({ ...base, signed_up_at: ago(2.5), last_active_at: ago(0), sent_kinds: ["welcome"], trial_started_at: ago(2.2) }, now, 3), "trial_ending");
  assert.equal(dueEmail({ ...base, signed_up_at: ago(60), last_active_at: ago(30), sent_kinds: ["welcome", "day3_tip"] }, now, 3), "win_back");
  assert.equal(dueEmail({ ...base, signed_up_at: ago(60), last_active_at: ago(2), sent_kinds: ["welcome", "day3_tip"] }, now, 3), null);
});

await test("trial-ending email ignores the marketing opt-out; tips respect it", () => {
  const optedOut = { ...base, email_opt_in: false };
  assert.equal(dueEmail({ ...optedOut, signed_up_at: ago(2.5), last_active_at: ago(0), sent_kinds: ["welcome"], trial_started_at: ago(2.2) }, now, 3), "trial_ending");
  assert.equal(dueEmail({ ...optedOut, signed_up_at: ago(4), last_active_at: ago(1), sent_kinds: ["welcome"] }, now, 3), null);
});

await test("tips wait for daytime in the user's zone", () => {
  const night = new Date("2026-11-03T06:00:00Z"); // midnight in Denver
  assert.equal(dueEmail({ ...base, timezone: "America/Denver", signed_up_at: ago(4), last_active_at: ago(1), sent_kinds: ["welcome"] }, night, 3), null);
});

await test("email templates are localized, escaped and include unsubscribe only for marketing", () => {
  const tip = emailContent("day3_tip", "es", 3);
  assert.equal(tip.marketing, true);
  const html = emailHTML(tip, "https://x.test/?a=1&b=2", "https://x.test/u?t=1", "es");
  assert.match(html, /Darse de baja/);
  assert.match(html, /a=1&amp;b=2/);
  assert.equal(emailContent("trial_ending", "en", 3).marketing, false);
  assert.match(emailContent("trial_ending", "en", 3).paragraphs[0], /3-day free trial/);
});

await test("unsubscribe tokens verify and reject tampering", async () => {
  const token = await unsubscribeToken(base.user_id, "secret");
  assert.equal(await verifyUnsubscribeToken(token, "secret"), base.user_id);
  assert.equal(await verifyUnsubscribeToken(token, "other"), null);
  assert.equal(await verifyUnsubscribeToken(token.replace("1111", "2222"), "secret"), null);
  assert.equal(await verifyUnsubscribeToken("garbage", "secret"), null);
});

console.log(`\n${passed} tests passed`);
