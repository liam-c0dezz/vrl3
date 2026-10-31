# EasyBid estimate portal security

Last reviewed: July 29, 2026

## Security model

The estimate portal is public only because a client must be able to open a
contractor-supplied link without creating an account. The link contains a
256-bit random bearer token. The database stores only the token's SHA-256 hash,
not the raw token.

New app-generated links place the token in the URL fragment (`#token=...`).
Browser fragments are not sent in the initial HTTP request, server logs, or
referrer headers. The portal still accepts legacy query-string links, but moves
their token into the fragment immediately. Because the initial request for a
legacy link can already reach hosting logs, contractors should generate new
fragment-based links for sensitive estimates after this release.

The public Supabase key in the browser is a publishable anonymous key, not a
service-role secret. It can execute only the explicitly granted public portal
functions. The service-role key must never appear in the app, portal source, or
client bundle.

## Implemented controls

- 32-byte cryptographically random share tokens;
- SHA-256 token hashing at rest;
- 30-day link expiration and explicit revocation;
- a new link revokes prior active links for the same estimate;
- database row-level security for authenticated workspace access;
- fixed `search_path` on security-definer functions;
- explicit function grants rather than public table access;
- server-side length constraints for signer names and change requests;
- five-second database statement timeouts for anonymous portal RPCs;
- client-side token-format and input-length validation;
- estimate data is rendered through React text nodes, without raw HTML injection;
- estimate pages use `Cache-Control: no-store`;
- estimate pages are marked `noindex`, `nofollow`, and `noarchive`;
- `Referrer-Policy: no-referrer`;
- Content Security Policy limiting scripts, styles, images, forms, frames, and
  network connections;
- clickjacking protection through `frame-ancestors 'none'` and
  `X-Frame-Options: DENY`;
- disabled browser Camera, Microphone, Location, Payment, and USB permissions;
- HTTPS Strict Transport Security on production responses;
- generic public error messages that do not expose database error details; and
- no advertising pixels, third-party ads, or cross-site tracking.

## Verification

The portal's automated tests verify its security headers, non-cacheable estimate
entry page, privacy-policy route, token-fragment handling, bounded inputs, and
absence of personal-name text. The production build and lint pass.

`npm audit --omit=dev` reported zero known production dependency
vulnerabilities on July 29, 2026. Development-only lint plugins still inherit an
upstream `brace-expansion` advisory; those packages are not included in the
deployed portal. Recheck both production and development dependency audits
before every release.

## Required deployment checks

- Deploy the portal-security database migration before releasing the new site.
- Attach and validate a neutral custom domain with active HTTPS.
- Configure that same origin in both Xcode build configurations.
- Add a monitored, generic EasyBid support contact to the Support page and
  Privacy Policy.
- Confirm no service-role key or other secret appears in the client bundle.
- Verify an expired, revoked, malformed, approved, and change-requested link in
  production.
- Monitor Supabase and hosting logs for unusual request volume. Add edge rate
  limiting if abuse appears.
- Re-run build, lint, tests, and dependency audits before each deployment.
