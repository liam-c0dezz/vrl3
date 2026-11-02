import Foundation
import Supabase
import SuperwallKit

enum PremiumPlacement: String, CaseIterable {
    case createEstimate = "create_estimate"
    case createInvoice = "create_invoice"
    case createRender = "create_render"
    case sendEstimate = "send_estimate"
    case sendInvoice = "send_invoice"
}

enum PremiumSubscriptionAccessState: Equatable {
    case active
    case inactive
    case unknown
}

enum PremiumGateDecision: Equatable {
    case allow
    case presentPaywall
    case failClosed
}

enum PremiumPaywallOutcome: Equatable {
    case purchased
    case restored
    case declined
    case skipped
    case error
}

/// Pure access policy shared by the live Superwall integration and unit tests.
/// Apple/Superwall determines subscription state; this policy determines what
/// EasyBid is allowed to do with that state.
enum PremiumAccessPolicy {
    static func initialDecision(
        isConfigured: Bool,
        subscriptionState: PremiumSubscriptionAccessState
    ) -> PremiumGateDecision {
        guard isConfigured else { return .failClosed }

        switch subscriptionState {
        case .active:
            return .allow
        case .inactive, .unknown:
            return .presentPaywall
        }
    }

    static func decision(after outcome: PremiumPaywallOutcome) -> PremiumGateDecision {
        switch outcome {
        case .purchased, .restored:
            return .allow
        case .declined:
            return .failClosed
        case .skipped, .error:
            return .failClosed
        }
    }
}

@MainActor
enum SuperwallService {
    static let freeTrialDays = 3

    private(set) static var isConfigured = false
    private static let publicAPIKey = "pk_EM_OrZC8yCvMaPwGkc90n"
    private static let unavailableMessage =
        L("The subscription screen isn't available right now. Please try again.")

    static func configure() {
        guard !isConfigured else { return }

        let bundledKey = (Bundle.main.object(forInfoDictionaryKey: "SuperwallAPIKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey: String
        if let bundledKey,
           !bundledKey.isEmpty,
           !bundledKey.contains("SUPERWALL_API_KEY") {
            apiKey = bundledKey
        } else {
            apiKey = publicAPIKey
        }

        let options = SuperwallOptions()
#if DEBUG
        options.testModeBehavior = .always
#endif

        Superwall.configure(apiKey: apiKey, options: options)
        isConfigured = true
    }

    static func identify(session: Session) {
        guard isConfigured else { return }
        Superwall.shared.identify(userId: session.user.id.uuidString)
    }

    static func reset() {
        guard isConfigured else { return }
        Superwall.shared.reset()
    }

    static var subscriptionStatusText: String {
        guard isConfigured else { return L("Unavailable") }
        switch currentSubscriptionAccessState {
        case .active:
            return L("Active")
        case .inactive:
            return L("Not active")
        case .unknown:
            return L("Checking…")
        }
    }

    /// Runs a paid action only for an active subscriber or immediately after a
    /// successful purchase/restore. The action is intentionally not supplied as
    /// Superwall's feature block so a missing or non-gated campaign can never
    /// accidentally unlock paid functionality.
    static func performPremiumAction(
        _ placement: PremiumPlacement,
        params: [String: Any]? = nil,
        onFailure: @escaping (String) -> Void,
        action: @escaping () -> Void
    ) {
        switch PremiumAccessPolicy.initialDecision(
            isConfigured: isConfigured,
            subscriptionState: currentSubscriptionAccessState
        ) {
        case .allow:
            action()
            return
        case .failClosed:
            onFailure(unavailableMessage)
            return
        case .presentPaywall:
            break
        }
        let handler = PaywallPresentationHandler()
        handler.onError { error in
            onFailure(SafeErrorMessages.purchase(error))
        }
        handler.onDismiss { _, result in
            let outcome: PremiumPaywallOutcome
            switch result {
            case .purchased:
                outcome = .purchased
            case .restored:
                outcome = .restored
            case .declined:
                outcome = .declined
            }

            if PremiumAccessPolicy.decision(after: outcome) == .allow {
                action()
            }
        }
        handler.onSkip { reason in
            _ = reason
            if PremiumAccessPolicy.decision(after: .skipped) == .failClosed {
                onFailure(unavailableMessage)
            }
        }

        Superwall.shared.register(
            placement: placement.rawValue,
            params: params,
            handler: handler
        )
    }

    static func presentOnboardingPaywall(
        onComplete: @escaping () -> Void,
        onFailure: @escaping (String) -> Void
    ) {
        switch PremiumAccessPolicy.initialDecision(
            isConfigured: isConfigured,
            subscriptionState: currentSubscriptionAccessState
        ) {
        case .allow:
            onComplete()
            return
        case .failClosed:
            onFailure(
                "Add the Superwall API key to the app's SUPERWALL_API_KEY build setting."
            )
            return
        case .presentPaywall:
            break
        }
        let handler = PaywallPresentationHandler()
        handler.onError { error in
            onFailure(SafeErrorMessages.purchase(error))
        }
        handler.onDismiss { _, result in
            let outcome: PremiumPaywallOutcome
            switch result {
            case .purchased:
                outcome = .purchased
            case .restored:
                outcome = .restored
            case .declined:
                outcome = .declined
            }

            if PremiumAccessPolicy.decision(after: outcome) == .allow {
                onComplete()
            }
        }
        handler.onSkip { reason in
            // Superwall's internal skip reason is useful to developers but can
            // contain provider details that should not be shown to customers.
            _ = reason
            if PremiumAccessPolicy.decision(after: .skipped) == .failClosed {
                onFailure(unavailableMessage)
            }
        }

        Superwall.shared.register(
            placement: "onboarding_complete",
            handler: handler
        )
    }

    private static var currentSubscriptionAccessState: PremiumSubscriptionAccessState {
        guard isConfigured else { return .unknown }

        switch Superwall.shared.subscriptionStatus {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .unknown:
            return .unknown
        }
    }
}
