# Chunks 3–4 Audit — 2026-08-05

## Scope and change boundary

The production iOS implementation, portal implementation, Edge Functions, SQL migrations, database schema, production records, and provider dashboard configuration were treated as read-only.

Permitted edits:

- iOS test targets
- Private local operations/audit documentation

## Chunk 3: automated verification

### Existing baseline

- iOS unit suite: passed before expansion
- Smart-service validation/media suite: 17 passed
- Portal build/security suite: 5 passed

### Expanded-suite result

- All 15 expanded iOS unit tests passed in a clean confirmation run on an iPhone 17 simulator.
- The foreground-launch UI assertion passed in 7.514 seconds.
- Both commands exited successfully and produced Xcode `TEST SUCCEEDED` reports with code coverage disabled.
- An earlier result-finalization failure was caused by insufficient disk space. After 4.8 GiB became available and the replacement iPhone 17 simulator was selected, the clean reruns completed successfully.

### Added iOS coverage

- Estimate item/material summaries
- Estimate dictionary parsing and category subtotal reconciliation
- Invoice subtotal, discount, tax and total calculations
- Estimate-to-invoice conversion including markup and contingency
- Invoice and payment Codable round trips
- Project workflow status derived from estimate state
- Server AI-consent record decoding
- Basic foreground launch assertion

### Deliberately excluded from automated tests

- Paid OpenAI requests
- Production database writes
- Production account creation or deletion
- Real email delivery
- Real App Store purchase/restore
- Destructive portal-token tests against customer records

Those behaviors belong in the controlled end-to-end launch pass with disposable accounts and records.

## Chunk 4: production audit

### Supabase project

- Status: active and healthy
- Plan: Pro
- Database: Postgres 17
- Region: `us-east-1`
- All listed public application tables had RLS enabled.

### Migrations

- Local migrations: 23
- Deployed migrations: 23
- Every local migration name exists in production.
- 13 migrations have the same local and deployed version.
- 10 migration names have different timestamp/version prefixes locally and in production.

No migration was renamed or rewritten. The version-prefix difference is recorded as migration-history drift and should be preserved until a deliberate migration-reconciliation plan is approved.

Affected names:

- `launch_data_integrity_and_account_deletion`
- `estimate_portal_security`
- `ai_consent_and_abuse_protection`
- `security_definer_privilege_corrections`
- `portal_rpc_input_guards`
- `fix_invoice_upsert_ambiguity`
- `replace_estimate_with_items`
- `restrict_estimate_total_trigger_execution`
- `use_invoker_for_estimate_replacement`
- `fix_estimate_replacement_item_alias`

### Edge Functions

- `smart-service`: active, JWT verification enabled
- `delete-account`: active, JWT verification enabled
- Deployed `smart-service` files exactly matched the local `index.ts`, `validation.ts`, and `media.ts` files.
- Deployed `delete-account/index.ts` exactly matched the local file.

### AI protections

The deployed request reservation path verifies the session and project membership before reserving a request. The database reservation enforces:

- Current consent version
- Per-user and per-IP rate limits
- Daily and monthly quotas
- One active request per user
- Idempotent request IDs and cached successful retries
- Processing leases for abandoned requests
- Emergency disable switch
- Maximum output-token configuration

The Edge Function rechecks consent after an AI response and before returning/persisting the result.

### Secrets

- No OpenAI-style `sk-…` key was found in the application, portal, functions, migrations, tests or docs.
- The app contains a Supabase publishable key, which is designed for public clients.
- Server-only key names occur only as environment lookups or documentation.
- No service-role or OpenAI secret value was found in the iOS or portal source.

### RLS and privileged functions

Security Advisor reported:

- 11 informational `RLS enabled, no policy` notices
- 3 warnings for anonymous execution of public portal `SECURITY DEFINER` functions
- 12 warnings for authenticated execution of `SECURITY DEFINER` functions

Review findings:

- The anonymous functions are the intentional token-based estimate portal API.
- Portal tokens are 32 random bytes represented as 64 hexadecimal characters and stored only as SHA-256 hashes.
- Portal functions validate token format and expiration and use a five-second statement timeout.
- Approval/change functions accept only active `sent` or `viewed` links, preventing duplicate finalization.
- Share-link creation checks organization membership and revokes older active links.
- Authenticated privileged functions reviewed contained authentication and/or organization-ownership checks and had an empty fixed `search_path`.
- No immediate privilege-bypass path was identified in this read-only review.
- Advisor warnings remain visible because the intended public/authenticated APIs are privileged by design; they must continue to be reviewed after any SQL change.

The `RLS enabled, no policy` tables are either server-owned AI accounting/configuration tables or reference/catalog tables. RLS therefore denies direct client rows unless an intentional policy is later added.

### Portal and Storage

- Share links expire after 30 days.
- The Storage bucket `project-files` is private.
- Storage SELECT, INSERT, UPDATE and DELETE policies require authenticated project access.
- Bucket size limit: 50 MB per object.
- Allowed MIME types are not restricted at the bucket level.
- The bucket contained zero objects during this audit.

### Advisor performance notices

- 1 RLS auth-init-plan warning on payment insertion
- 1 multiple-permissive-policy warning on membership reads
- 2 duplicate-index warnings
- 29 informational unused-index notices
- 1 informational fixed Auth-connection-allocation notice

These were documented but not changed. Unused-index notices are not sufficient evidence to remove indexes from a young, low-traffic production database.

### Backups, monitoring and email

- Scheduled physical database backups were user-confirmed in the dashboard on 2026-08-01.
- Database backups do not include actual Storage objects.
- Supabase Auth, API and Edge Function logs are accessible.
- No external log drain or app error-monitoring SDK was found in the repository.
- OpenAI spend limit and spend alerts were user-confirmed before this audit.
- Password-reset email delivery was manually confirmed earlier; no new SMTP changes were made.

## Items that still require a controlled manual/dashboard pass

1. Configure external monitoring or commit to a documented provider-dashboard review schedule.
2. Establish off-provider backup for Storage objects before customer attachments accumulate.
3. Use two disposable accounts to prove cross-organization RLS denial without touching customer records.
4. Test account deletion with a disposable owner account and verify Auth/session invalidation and data cleanup.
5. Test SMTP delivery, spam placement and password-reset deep links across at least Gmail and iCloud.
6. Run Apple Sign-In, subscription purchase/restore and portal approval on a physical iPhone.
7. Decide whether bucket-level MIME restrictions should be added in a future reviewed backend change.

No production remediation was performed during this audit.
