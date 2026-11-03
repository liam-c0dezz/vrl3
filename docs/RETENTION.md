# Retention: notifications, streaks, widgets, email, win-back

Habit loop: **trigger** (reminder at the user's usual hour, home-screen widget,
streak at risk) → **one small action** (send an estimate) → **reward** (streak,
weekly recap) → **investment** (history, streak freezes).

## What ships, and what each piece needs

| Piece | Where | Needs setup? |
|---|---|---|
| Notification permission asked **after the first win** (first estimate/invoice sent), with a pre-prompt; never on launch | `Features/Retention/RetentionViews.swift` | No |
| Weekly streak (Mon–Sun, user's time zone) with **streak freeze**: every 4 active weeks earns one, max 2, spent automatically on a missed week | `Shared/RetentionShared.swift` | No |
| Streak card, weekly recap card ("This week you…") with a **share card** image, trial-ending banner on Home | `RetentionViews.swift` | No |
| Local reminders at the user's usual hour: streak at risk (Friday), weekly recap (Monday), **trial ending (24 h before, always scheduled)** | `RetentionCenter.swift` | No |
| Home-screen + Lock Screen widget (streak, this week's progress, tap → new estimate) | `EasyBidWidget/` | No |
| Live Activity: AI estimate progress on the Lock Screen / Dynamic Island | `EstimateLiveActivity.swift`, `EasyBidWidget/` | No |
| App Store review prompt after a win (3+ wins, 3+ days in, max every 120 days, or right after a client approval) | `RetentionCenter.swift` | No |
| Settings → Notifications: frequency (all / important / off), quiet hours, streak and recap toggles, email opt-out | `NotificationSettingsView` | No |
| Measurement: opt-in rate, push → open, A/B copy variants | `engagement_events`, `retention_metrics` view | No |
| **Remote push** when a client views, approves or asks for changes (APNs, respects quiet hours, time zone, frequency) | `supabase/functions/retention-dispatch` | **APNs key** (below) |
| Lifecycle email: welcome, day-3 tip, trial ending, win-back (localized, unsubscribe link) | same function | Optional: email provider |
| Win-back paywall for lapsed subscribers | `RetentionCenter.checkWinBack()` registers Superwall placement `win_back` | Optional: Superwall campaign |

Everything is in English and Spanish and follows the in-app language switch.

## One-time steps

1. **Database:** apply `supabase/migrations/20261103120000_retention_engagement.sql`
   (`supabase db push`). It enables `pg_net` and `pg_cron`, creates the tables,
   generates its own secrets and schedules the dispatcher every 10 minutes.
2. **Function:** `supabase functions deploy retention-dispatch --no-verify-jwt`
   (the database authenticates with a generated secret, not a user JWT).
3. **Remote push (APNs):** Apple Developer → Certificates, IDs & Profiles →
   Keys → **+** → enable *Apple Push Notifications service (APNs)* → download
   the `.p8`. Then:
   ```bash
   supabase secrets set APNS_KEY_ID=XXXXXXXXXX APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
   ```
   The team ID (`5WLL25W3WQ`) and bundle ID are already filled in. Until this is
   set, client-activity pushes are skipped and everything else keeps working.
4. **Xcode:** open the project and build. Automatic signing registers the Push
   Notifications and App Groups capabilities and the new
   `EasyBidWidgetExtension` target. No manual capability clicks are needed.
5. **Email (optional):** create a [Resend](https://resend.com) account, verify a
   sending domain, then `supabase secrets set RESEND_API_KEY=... EMAIL_FROM="EasyBid <hello@yourdomain.com>"`.
   Without it, lifecycle email is off; the in-app banner and the local
   trial-ending reminder still cover the trial.
6. **Win-back (optional):** in Superwall, add a campaign for the `win_back`
   placement and attach an App Store Connect win-back offer.

## Rules the code enforces

- Every push is useful: client activity, trial ending, a streak that is
  actually at risk, or a recap only when there was activity.
- Quiet hours (default 9 PM–8 AM) and the user's time zone, on device and on
  the server. Server pushes that land in quiet hours wait until they end.
- Users control frequency; "Important only" keeps client activity and the
  trial reminder; "Off" silences notifications.
- The trial-ending reminder is always scheduled (local notification + email +
  Home banner).
- Dead APNs tokens are removed automatically; pushes older than 3 days expire.

## Reading the numbers

```sql
select * from public.retention_metrics;
```

Rows: `opt_in` (granted ÷ answered), `push_open` per copy variant (opens ÷
sent), and opens per local reminder type and variant. Raw events are in
`engagement_events` (`notification_prompt_shown`, `notification_permission`,
`notification_open`, `win`, `review_prompt`, `recap_shared`,
`win_back_placement`, `email_unsubscribed`).

## Why Supabase instead of Cloudflare Workers, D1 and FCM

The app already runs on Supabase, which keeps user data, auth and the
estimate-approval events. `pg_cron` + `pg_net` + an edge function cover what
Cron Triggers, D1, Queues and a Worker would, with no second account, no data
sync and no extra deploy target. FCM is only needed for Android; this app is
iOS-only, so APNs is called directly and nothing from Firebase is used. If an
Android app ships later, add an FCM HTTP v1 sender next to `sendAPNs` (the
`push_devices.platform` column already allows `android`).

## Tests

- `Construction EstimateTests/RetentionTests.swift`: streak engine, freezes,
  quiet hours, usual-hour detection.
- `supabase/functions/retention-dispatch/logic.test.ts`: quiet hours across
  time zones, copy variants, localization, email schedule, unsubscribe tokens.
  Run with `node --experimental-strip-types logic.test.ts`.
