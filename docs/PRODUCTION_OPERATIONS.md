# EasyBid Production Operations

Last reviewed: 2026-08-05

This is the private operating guide for the EasyBid production system. It is not bundled into the iOS app or published on the client portal. Do not place passwords, API keys, access tokens, customer records, or private signing material in this file.

## Production inventory

- Supabase organization: `Selah Org` (Pro)
- Supabase project: `AI estimator`
- Project reference: `tuykoxmpnmrawrknjikr`
- Region: `us-east-1`
- Database: Postgres 17, GA release channel
- Client key: Supabase publishable key only
- Edge Functions:
  - `smart-service`, JWT verification enabled
  - `delete-account`, JWT verification enabled
- Private Storage bucket: `project-files`
- Public estimate portal: token-based estimate viewing and approval

## Server-only secrets

The following values belong only in provider-managed server environments:

- `OPENAI_API_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `AI_RATE_LIMIT_SALT` when explicitly configured
- Transactional email/SMTP credentials

The iOS app may contain the Supabase project URL and publishable key. It must never contain a Supabase secret/service-role key or an OpenAI API key.

## Normal monitoring

Check these areas before a release and at least weekly after launch:

1. Supabase Dashboard → Logs:
   - Auth: repeated failed sign-ins, password-reset failures, unusual new-user volume.
   - Edge Functions: `smart-service` and `delete-account` 4xx/5xx responses, timeouts, and bursts.
   - Postgres/API: permission errors, slow requests, connection pressure, and database failures.
   - Storage: rejected uploads and unusual download volume.
2. Supabase Dashboard → Database → Security Advisor and Performance Advisor.
3. OpenAI project usage:
   - Current spend versus the project limit.
   - Requests and token use inconsistent with the number of active customers.
   - Spend-alert delivery.
4. Supabase Auth email delivery and the monitored support inbox.
5. Estimate portal failures and reports of invalid, expired, or reused links.

As of 2026-08-05, no external Supabase log drain or app error-monitoring integration was found in the repository. Provider dashboards are therefore the current source of operational evidence.

## Active AI protections

The database-backed configuration reviewed on 2026-08-05 was:

- Emergency AI switch: enabled
- Per user: 8 requests/minute
- Per user: 75 AI requests/day
- Per user: 1,500 AI requests/month
- Per IP: 20 requests/minute
- Maximum concurrent requests per user: 1
- Request lease: 180 seconds
- Maximum output: 2,000 tokens

The server reserves a request before contacting OpenAI. Reservations enforce authentication, project membership, current AI consent, idempotency, concurrency, rate limits and quotas. Raw IP addresses are not stored; the server stores an HMAC-derived value when an IP is available.

## Emergency procedures

### Unexpected OpenAI spending

1. Confirm the alert in the OpenAI usage dashboard.
2. Inspect `smart-service` logs and aggregate AI request counts.
3. Disable AI with the existing `public.ai_service_config.is_enabled` emergency switch.
4. Do not delete usage or request history during the investigation.
5. Rotate the OpenAI key if compromise is suspected.
6. Re-enable AI only after the request source and rate-limit behavior are understood.

Changing the emergency switch is a production database action. It must be performed deliberately and recorded in the incident log.

### Authentication abuse

1. Inspect Auth logs and the source/time pattern.
2. Confirm Supabase Auth rate limits and leaked-password protection remain enabled.
3. Temporarily disable new registrations in Supabase Auth if account creation is under active abuse.
4. Do not disable existing sign-in unless account access itself is unsafe.
5. Record any dashboard configuration change and restore it after the incident.

### Portal abuse or exposure

1. Identify the affected estimate and share-link record without copying its raw token into tickets or chat.
2. Revoke the share link. Creating a replacement link also revokes prior active links for that estimate.
3. Inspect portal/API logs for repeated invalid attempts or unusual traffic.
4. Temporarily take portal sending offline if the behavior cannot be contained.
5. Confirm the estimate, project and client records were not modified unexpectedly.

### Production outage

1. Check Supabase project health and provider status pages.
2. Determine whether the failure affects Auth, Database/API, Storage, Edge Functions, the portal, or OpenAI.
3. Avoid schema changes during diagnosis.
4. If a recent Edge Function release caused the failure, redeploy the last known-good function source from Git.
5. If a database migration caused the failure, prefer a reviewed forward-fix migration. Do not manually rewrite migration history.
6. Use database restore only when the recovery impact and downtime are understood.

## Backups and recovery

- Scheduled physical database backups were confirmed in the Supabase dashboard on 2026-08-01.
- Supabase database backups include database records and Storage metadata.
- They do **not** include the actual objects stored in Supabase Storage.
- The `project-files` bucket contained zero objects during the 2026-08-05 audit, but an independent Storage-object backup process is required once customer files are stored there.
- Before a destructive database change, confirm a recent backup and document the intended recovery point.
- A database restore causes downtime and can roll back valid customer changes made after the selected recovery point.

## Deployment and rollback

### Edge Functions

1. Run local validation/media tests.
2. Compare the intended source with the currently deployed function.
3. Deploy only the changed function with JWT verification preserved.
4. Confirm the new version is active and inspect logs.
5. For rollback, redeploy the exact previous source from Git.

### Database

1. Every schema change must have a reviewed migration.
2. Test the migration outside production when possible.
3. Run Security and Performance Advisors after deployment.
4. Do not delete or rename existing production migration-history entries.
5. Prefer a new corrective migration over an improvised rollback.

### iOS app

1. Run unit and launch tests.
2. Test the production account, estimate, invoice, payment and portal flows manually.
3. Archive a Release build and inspect its privacy report.
4. Upload to TestFlight before App Store submission.

## Incident record template

Record the following without including secrets or unnecessary customer content:

- Start and end time
- Reporter
- Affected service and user impact
- Detection source
- Relevant request IDs and provider log references
- Containment actions
- Production configuration changes
- Recovery action
- Validation performed after recovery
- Follow-up owner and due date

