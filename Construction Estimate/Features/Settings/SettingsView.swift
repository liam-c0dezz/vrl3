import Supabase
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var consentStore = AIConsentStore.shared
    @State private var showAIConsentPrompt = false
    @State private var showDeleteAccount = false
    @State private var showLogoutConfirmation = false
    @State private var businessSetupDestination: BusinessSetupDestination?
    @State private var refreshID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                #if DEBUG
                Section(L("Development")) {
                    NavigationLink(L("Estimator QA")) {
                        EstimatorAcceptanceProjectPickerView()
                    }
                }
                #endif

                Section(L("Account")) {
                    LabeledContent(L("Signed in as")) {
                        Text(authStore.session?.user.email ?? L("Apple Account"))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section(L("Language")) {
                    LabeledContent(L("App language")) {
                        LanguageToggle(usesLightBackground: true)
                    }
                }

                Section(L("Business")) {
                    HapticButton("Business details") {
                        businessSetupDestination = .business
                    }
                    HapticButton("Hourly rates") {
                        businessSetupDestination = .hourlyRates
                    }
                    HapticButton("Upsells") {
                        businessSetupDestination = .upsells
                    }
                }

                Section {
                    LabeledContent(L("Free Trial")) {
                        Text(L("%@ days", SuperwallService.freeTrialDays.formatted()))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent(L("Subscription")) {
                        Text(SuperwallService.subscriptionStatusText)
                            .foregroundStyle(
                                SuperwallService.subscriptionStatusText == L("Active")
                                    ? Color.green
                                    : Color.secondary
                            )
                    }

                    Text(
                        L("To manage or cancel, open iPhone Settings, tap your name, choose Subscriptions, then select EasyBid.")
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                } header: {
                    Text(L("Plan"))
                }

                Section {
                    HStack {
                        Label(L("AI Features"), systemImage: "sparkles")
                        Spacer()
                        Text(aiStatusText)
                            .foregroundStyle(.secondary)
                    }

                    switch consentStore.status {
                    case .granted:
                        HapticButton("Withdraw AI Consent", role: .destructive) {
                            Task { _ = await consentStore.setConsent(granted: false) }
                        }
                    case .denied:
                        HapticButton("Allow AI Features") {
                            Task { _ = await consentStore.setConsent(granted: true) }
                        }
                    case .unknown:
                        HapticButton("Review AI Consent") {
                            showAIConsentPrompt = true
                        }
                    case .loading:
                        EmptyView()
                    }

                    if let errorMessage = consentStore.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(L("AI Consent"))
                } footer: {
                    Text(
                        L("AI requests can include messages, relevant project details, and media you intentionally attach. Turning consent off blocks new AI requests.")
                    )
                }

                Section(L("Privacy & Support")) {
                    NavigationLink(L("Privacy & Permissions")) {
                        PrivacyCenterView()
                    }

                    if let supportURL = PrivacyResources.supportURL {
                        Link(L("EasyBid Support"), destination: supportURL)
                    }
                    if let policyURL = PrivacyResources.policyURL {
                        Link(L("Privacy Policy"), destination: policyURL)
                    }
                    Link(L("Terms of Use"), destination: PrivacyResources.termsURL)
                }

                Section {
                    HapticButton("Log Out", role: .destructive) {
                        showLogoutConfirmation = true
                    }

                    HapticButton("Delete Account", role: .destructive) {
                        showDeleteAccount = true
                    }
                } footer: {
                    Text(L("Deleting your account permanently removes its EasyBid workspace data. It does not cancel an Apple subscription."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
        }
        .background(Color.white.ignoresSafeArea())
        .id(refreshID)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await consentStore.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshID = UUID()
        }
        .confirmationDialog(
            L("Log out of EasyBid?"),
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            HapticButton("Log Out", role: .destructive) {
                Task { await authStore.signOut() }
            }
            HapticButton("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAIConsentPrompt) {
            AIConsentPromptView(consentStore: consentStore)
        }
        .sheet(isPresented: $showDeleteAccount) {
            DeleteAccountView()
                .environment(authStore)
        }
        .sheet(item: $businessSetupDestination) { destination in
            switch destination {
            case .business:
                BusinessSetupView()
            case .hourlyRates:
                NavigationStack {
                    HourlyRatesSetupView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                HapticButton("Cancel") { businessSetupDestination = nil }
                            }
                        }
                }
            case .upsells:
                NavigationStack {
                    BusinessUpsellsSetupView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                HapticButton("Cancel") { businessSetupDestination = nil }
                            }
                        }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                HapticButton {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .frame(height: 50)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            HStack {
                Text(L("Settings"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppGray.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea(edges: .top))
    }

    private var aiStatusText: String {
        switch consentStore.status {
        case .unknown: L("Not chosen")
        case .loading: L("Loading…")
        case .granted: L("Allowed")
        case .denied: L("Off")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthStore())
    }
}
