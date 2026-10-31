# EasyBid App Store privacy submission guide

Prepared from the app and SDK code audit on July 31, 2026. Recheck this document whenever an SDK, data flow, permission, or feature changes.

## App Store Connect URLs

- Privacy Policy URL: `https://easybid.viralappdev.com/privacy`
- User Privacy Choices URL: `https://easybid.viralappdev.com/privacy#your-choices`
- Support URL: `https://easybid.viralappdev.com/support`
- Terms of Use: `https://easybid.viralappdev.com/terms`

Do not submit the app or publish these metadata fields until the same neutral
HTTPS base URL is configured as `EASYBID_PORTAL_BASE_URL` in both Xcode build
configurations and the custom domain is active on the portal.

## Required before App Store submission

- Keep the custom-domain DNS and TLS validation active.
- Keep the published EasyBid support/privacy contact monitored.
- Rebuild and verify the generated Info.plist after changing the portal origin.
- Enter the final Privacy Policy, Privacy Choices, and Support URLs in App Store
  Connect.
- Publish every data type and purpose listed below in App Store Connect.
- Deploy and verify the account-deletion function and portal-security database
  migration in production.
- Give App Review a working demo account and a valid sample estimate link.
- Confirm the Camera purpose string in the archived build.
- Generate and inspect Xcode's privacy report for the release archive, including
  manifests supplied by Supabase, Superwall, and their
  dependencies.

## Initial App Privacy answer

Select **Yes, we collect data from this app**.

For every data type below, select **No** for “used for tracking.” EasyBid does not link app data with third-party data for targeted advertising, does not share data with a data broker, and does not use ATT/IDFA.

## Data types to select

| App Store data type | Purpose selections | Linked to identity | Source/use |
|---|---|---:|---|
| Contact Info → Name | App Functionality | Yes | Account profile, client records, approval signer |
| Contact Info → Email Address | App Functionality | Yes | Authentication and client records |
| Contact Info → Phone Number | App Functionality | Yes | Optional phone authentication and client records |
| Contact Info → Physical Address | App Functionality | Yes | Client, property, and project records |
| Financial Info → Other Financial Info | App Functionality | Yes | Estimate/invoice amounts, pricing, discounts, taxes, and payment terms |
| Location → Coarse Location | App Functionality; Product Personalization; Analytics | Yes | User-entered ZIP/job area and Superwall IP-derived region |
| User Content → Photos or Videos | App Functionality | Yes | Optional job photos and video files intentionally attached to AI Chat or used to create project renders |
| User Content → Audio Data | App Functionality | Yes | Optional audio files and audio extracted from an attached video |
| User Content → Other User Content | App Functionality | Yes | Chats, project details, estimates, invoices, documents, change requests |
| Identifiers → User ID | App Functionality; Analytics | Yes | Supabase account ID and Superwall app user ID |
| Identifiers → Device ID | App Functionality; Analytics | Yes | Superwall vendor/device identifier |
| Purchases → Purchase History | App Functionality; Analytics | Yes | Apple subscription status and Superwall purchase/paywall reporting |
| Usage Data → Product Interaction | App Functionality; Analytics | Yes | Paywall views, purchase events, and related Superwall interactions |

## Do not select

Based on the audited version, do not select:

- Payment Info or Credit Info: Apple handles subscription payment credentials; EasyBid does not receive card or bank details.
- Precise Location: EasyBid does not request Core Location.
- Contacts: EasyBid does not read the device address book.
- Emails or Text Messages: EasyBid opens Apple’s compose interface but does not collect the resulting correspondence.
- Search History or Browsing History.
- Health, Fitness, Sensitive Info, Environment Scanning, Hands, or Head.
- Advertising Data.
- Crash Data, Performance Data, or Other Diagnostic Data unless a future SDK begins collecting them.

## Permission declarations

| Permission | Info.plist purpose | Request timing |
|---|---|---|
| Camera | Photograph jobs for estimate assistance or a project render | Only after the user chooses Take Photo |

Do not add permission prompts for Microphone, Photos, Location, Contacts, or Notifications in the first release:

- Photos use `PhotosPicker`/`PHPickerViewController`, which grants access only to selected items.
- Audio, video, and documents use the system file importer. EasyBid does not record voice notes or expose Live Walkthrough in the first release.
- Addresses and ZIP codes are manually entered.
- Current notifications are in-app activity polling, not push notifications.

## Privacy manifest

`Construction Estimate/PrivacyInfo.xcprivacy` declares:

- the collected data types above;
- no tracking and no tracking domains; and
- `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, because app-only preferences, local chats, and migration flags are stored in `UserDefaults`.

Superwall and Swift Crypto also supply their own SDK privacy manifests.

## App Review notes

Use wording similar to:

> EasyBid requests Camera access only when the reviewer selects Take Photo. Photo, audio, video, and document selection use Apple system pickers without broad library access. The first release does not expose voice recording or Live Walkthrough. AI Chat requires a one-time server-recorded permission before any request can reach OpenAI, and that permission can be withdrawn in Privacy & Permissions. The Privacy Policy and Privacy & Permissions screen are available from the account menu. Account deletion is available from Account → Delete Account. EasyBid does not use advertising tracking.

## Maintenance triggers

Re-audit App Store privacy answers before release if you add:

- crash or performance analytics;
- push notifications;
- contact import;
- Core Location;
- marketing attribution or advertising integrations;
- a new authentication provider;
- payment processing outside Apple;
- a new AI, storage, analytics, or support vendor; or
- server-side storage of chat, photo, or audio history.
