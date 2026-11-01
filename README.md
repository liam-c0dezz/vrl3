# EasyBid — Construction Estimate

iOS app (SwiftUI) for contractors to build estimates, send invoices and manage
clients, backed by Supabase, plus a web portal for clients to view estimates.

## Repository layout

```
Construction Estimate.xcodeproj   Xcode project (open this)
Construction Estimate/            iOS app sources (Xcode synchronized folder)
├── App/                          App entry point and root tab container
├── Core/
│   ├── Components/               Shared UI (top nav bar, language toggle)
│   ├── DesignSystem/             Brand colors, grays, haptics
│   ├── Errors/                   User-safe error messages
│   ├── Localization/             In-app English ⇄ Spanish switching
│   └── Privacy/                  Privacy center, AI consent
├── Models/                       Estimate, Invoice, Project, Client, Render
├── Services/                     Supabase client & data store, Superwall, portal
├── Features/
│   ├── Onboarding/               First-run onboarding flow (EN/ES toggle, top right)
│   ├── Auth/                     Sign in / sign up / password recovery
│   ├── Home/                     Dashboard, project list, notifications
│   ├── Projects/                 Project detail, documents, renders, sending
│   ├── Chat/                     AI estimate chat, photo/voice inputs
│   ├── Invoices/                 Invoice list, editor, rich text
│   ├── Clients/                  Client list & pickers
│   ├── Settings/                 Settings & business setup
│   └── Estimator/                Apache estimator preview & acceptance runner
├── Resources/                    Bundled JSON/PNG, licenses, privacy manifest
├── Info.plist
└── Construction_Estimate.entitlements
Construction EstimateTests/       Unit tests
Construction EstimateUITests/     UI tests
Media.xcassets/                   App icon and image assets
estimate-portal/                  Client-facing estimate web portal (vinext)
supabase/                         Edge functions, migrations, SQL tests
construction-scope-flow/          Estimating research harness and evaluations
scripts/                          Admin/import helper scripts (Python)
third_party/                      Upstream licensed code and notices
distribution/                     App Store export settings from past archives
docs/                             Release notes, privacy, operations docs
```

The app target uses Xcode's synchronized folder groups, so any file added under
`Construction Estimate/` is picked up automatically — no project file edits
needed. `Features/Chat/LiveWalkthroughView.swift` is intentionally excluded from
the target (see the exception set in the project file).

## Language

Onboarding can be switched between English and Spanish with the EN/ES toggle in
the top-right corner. The choice is stored under the `app.language` user default
and defaults to the device language. To translate another screen, read
`@Environment(\.appLanguage) private var lang`, wrap text in `lang("…")`, and
add the Spanish string to `Core/Localization/AppLanguage.swift`.
