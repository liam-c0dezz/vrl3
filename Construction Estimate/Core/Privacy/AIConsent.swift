import Observation
import Supabase
import SwiftUI

enum AIConsentStatus: Equatable {
    case unknown
    case loading
    case granted
    case denied
}

struct AIConsentRecord: Decodable {
    let userID: UUID
    let isGranted: Bool
    let consentVersion: String
    let grantedAt: Date?
    let revokedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case isGranted = "is_granted"
        case consentVersion = "consent_version"
        case grantedAt = "granted_at"
        case revokedAt = "revoked_at"
    }
}

@Observable
@MainActor
final class AIConsentStore {
    static let shared = AIConsentStore()
    static let currentVersion = "2026-07-31"

    private(set) var status: AIConsentStatus = .unknown
    private(set) var isSaving = false
    var errorMessage: String?

    var isGranted: Bool { status == .granted }
    var hasRecordedDecision: Bool { status == .granted || status == .denied }

    private init() {}

    func refresh() async {
        guard !isSaving else { return }
        status = .loading
        errorMessage = nil
        do {
            let session = try await supabase.auth.session
            let rows: [AIConsentRecord] = try await supabase
                .from("ai_consents")
                .select()
                .eq("user_id", value: session.user.id)
                .limit(1)
                .execute()
                .value

            guard let record = rows.first,
                  record.consentVersion == Self.currentVersion else {
                status = .unknown
                return
            }
            status = record.isGranted ? .granted : .denied
        } catch {
            status = .unknown
            errorMessage = "AI permission couldn't be loaded. Please try again."
        }
    }

    @discardableResult
    func setConsent(granted: Bool) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        struct Parameters: Encodable {
            let granted: Bool
            let consentVersion: String
            let appVersion: String

            private enum CodingKeys: String, CodingKey {
                case granted = "p_granted"
                case consentVersion = "p_consent_version"
                case appVersion = "p_app_version"
            }
        }

        let appVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"

        do {
            let record: AIConsentRecord = try await supabase
                .rpc(
                    "set_ai_consent",
                    params: Parameters(
                        granted: granted,
                        consentVersion: Self.currentVersion,
                        appVersion: appVersion
                    )
                )
                .execute()
                .value
            guard record.consentVersion == Self.currentVersion,
                  record.isGranted == granted else {
                throw AIConsentError.unexpectedResponse
            }
            status = granted ? .granted : .denied
            return true
        } catch {
            errorMessage = "AI permission couldn't be updated. Please try again."
            return false
        }
    }

    func reset() {
        status = .unknown
        errorMessage = nil
        isSaving = false
    }
}

private enum AIConsentError: Error {
    case unexpectedResponse
}

struct AIConsentPromptView: View {
    @Bindable var consentStore: AIConsentStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AppBrand.accent)

                Text("Use AI assistance")
                    .font(.system(size: 25, weight: .bold))

                Text(
                    "When you use AI Chat or Renders, EasyBid sends your messages, relevant project information, and any photos, video frames, or audio you intentionally attach to OpenAI to produce an answer, estimate, or project visualization."
                )
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

                Text("Review AI results before using them in a customer estimate, invoice, or render.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                if let errorMessage = consentStore.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task {
                        if await consentStore.setConsent(granted: true) {
                            dismiss()
                        }
                    }
                } label: {
                    Group {
                        if consentStore.isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text("Allow AI Features")
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppBrand.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(consentStore.isSaving)

                Button("Not Now") {
                    Task {
                        if await consentStore.setConsent(granted: false) {
                            dismiss()
                        }
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .disabled(consentStore.isSaving)

                HStack(spacing: 14) {
                    if let policyURL = PrivacyResources.policyURL {
                        Link("Privacy Policy", destination: policyURL)
                    }
                    Link("Terms of Use", destination: PrivacyResources.termsURL)
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationTitle("AI Permission")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(consentStore.status == .unknown)
    }
}
