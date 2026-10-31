# Estimate preview and sending release — October 21, 2026

The client portal now follows the estimate PDF's document layout. The app's Preview & Send sheet renders the actual PDF and offers blue, black, gray, and green accents plus a business name. Appearance is saved per estimate and included in the portal snapshot. Sent estimates retain a resend action.

Opening preview creates no share link. Selecting email/text prepares a link without changing estimate/project status or revoking a delivered link. A successful system composer result invokes authenticated `confirm_estimate_share_sent`. Canceled and failed compositions do not mark sent. Confirmation is idempotent, preserves approval, and can be retried without sending another message.

## Production

- Supabase migration: `estimate_appearance_and_confirmed_sending` applied.
- Portal: Sites version 9, source commit `9507cc38bd080ed023831a85ad11364b4c715e5b`.
- URL: https://easybid.viralappdev.com
- iOS changes require a new app build; website publication does not update installed binaries.

## Validation

- iOS simulator build passed.
- Two executed simulator tests passed: estimate PDF content and appearance/legacy decoding.
- Two portal document rendering tests passed (`node --import tsx --test tests/estimate-document.test.tsx` from `estimate-portal`).
- Four relevant portal HTTP/security tests passed. The full suite has a preexisting support-email expectation mismatch; support content was not changed.
- Database regression: `supabase/tests/estimate_sending.sql` passed with transaction rollback.
- Portal checked at desktop and 390px phone width; no horizontal overflow.

## Generation failure investigation

The two latest generation attempts on October 21 at approximately 10:14 PM and 10:17 PM America/Denver reached Supabase and failed after about 180 seconds with `estimator_timeout`. The first finished scope discovery in about 7.7 seconds, then timed out in `whole_plan`. The second timed out in `whole_discovery`. Both retained planning drafts without an `estimate_id`; no completed estimates exist to load for those attempts. The preceding Carpet Replacement generation completed in about 29 seconds.

This is a generation/provider timeout, separate from portal preview or fetching an existing saved estimate. No customer records were rewritten and the estimator was not redeployed as part of this release. The retained checkpoints need recovery and the provider polling path needs separate reliability work; the timeout cause beyond the recorded stage is not proven by these logs.
