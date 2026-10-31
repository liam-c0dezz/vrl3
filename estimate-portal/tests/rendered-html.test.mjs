import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render(pathname = "/") {
  const workerURL = new URL("../dist/server/index.js", import.meta.url);
  workerURL.searchParams.set("test", `${process.pid}-${Date.now()}-${pathname}`);
  const { default: worker } = await import(workerURL.href);

  return worker.fetch(
    new Request(new URL(pathname, "https://portal.easybid.test"), {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("renders a private, non-cacheable estimate entry page", async () => {
  const response = await render("/");
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);
  assert.equal(response.headers.get("cache-control"), "no-store, max-age=0");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-frame-options"), "DENY");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow, noarchive");
  assert.match(
    response.headers.get("content-security-policy") ?? "",
    /frame-ancestors 'none'/,
  );

  const html = await response.text();
  assert.match(html, /<title>Estimate ready for review \| EasyBid<\/title>/i);
  assert.match(html, /Estimate unavailable/);
  assert.match(html, /estimate link is incomplete/i);
  assert.doesNotMatch(html, /jack|gozigian/i);
});

test("renders the complete public privacy policy", async () => {
  const response = await render("/privacy");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-robots-tag"), null);

  const html = await response.text();
  assert.match(html, /<title>Privacy Policy \| EasyBid<\/title>/i);
  assert.match(html, /Information we collect/);
  assert.match(html, /Device permissions/);
  assert.match(html, /How we disclose information/);
  assert.match(html, /Retention/);
  assert.match(html, /Your choices and privacy rights/);
  assert.match(html, /OpenAI/);
  assert.match(html, /photos/i);
  assert.match(html, /video frames/i);
  assert.match(html, /audio/i);
  assert.match(html, /withdraw(?: or restore)? AI permission/i);
  assert.match(html, /Supplemental United States privacy notice/);
  assert.match(html, /Contact us/);
  assert.doesNotMatch(html, /jack|gozigian/i);
});

test("renders terms covering AI attachments and App Store cancellation", async () => {
  const response = await render("/terms");
  assert.equal(response.status, 200);

  const html = await response.text();
  assert.match(html, /<title>Terms of Use \| EasyBid<\/title>/i);
  assert.match(html, /OpenAI/);
  assert.match(html, /photos, video frames, or audio/i);
  assert.match(html, /open iPhone Settings/i);
  assert.match(html, /choose Subscriptions/i);
  assert.doesNotMatch(html, /jack|gozigian/i);
});

test("renders a public support page with a monitored contact", async () => {
  const response = await render("/support");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-robots-tag"), null);

  const html = await response.text();
  assert.match(html, /<title>Support \| EasyBid<\/title>/i);
  assert.match(html, /EasyBid Support/);
  assert.match(html, /sofia@viralappdev\.com/i);
  assert.match(html, /opening iPhone Settings/i);
  assert.match(html, /choosing Subscriptions/i);
  assert.doesNotMatch(html, /apps\.apple\.com\/account\/subscriptions/i);
  assert.doesNotMatch(html, /jack|jackgozigian/i);
});

test("keeps estimate credentials out of request URLs", async () => {
  const [portalSource, workerSource] = await Promise.all([
    readFile(new URL("../app/EstimatePortal.tsx", import.meta.url), "utf8"),
    readFile(new URL("../worker/index.ts", import.meta.url), "utf8"),
  ]);

  assert.match(portalSource, /SHARE_TOKEN_PATTERN = \/\^\[a-f0-9\]\{64\}\$\//);
  assert.match(portalSource, /url\.hash/);
  assert.match(portalSource, /currentURL\.searchParams\.delete\("token"\)/);
  assert.match(portalSource, /credentials: "omit"/);
  assert.match(portalSource, /referrerPolicy: "no-referrer"/);
  assert.match(portalSource, /functions\/v1\/estimate-media/);
  assert.match(portalSource, /method: "POST"/);
  assert.match(portalSource, /media_id: media\.id/);
  assert.doesNotMatch(portalSource, /estimate-media\?/);
  assert.match(portalSource, /estimate-total-card/);
  assert.doesNotMatch(portalSource, /estimate\?\.items/);
  assert.match(portalSource, /maxLength=\{MAX_SIGNER_LENGTH\}/);
  assert.match(portalSource, /maxLength=\{MAX_CHANGE_REQUEST_LENGTH\}/);
  assert.match(workerSource, /Content-Security-Policy/);
  assert.match(workerSource, /Cache-Control/);
  assert.match(workerSource, /Permissions-Policy/);
});
