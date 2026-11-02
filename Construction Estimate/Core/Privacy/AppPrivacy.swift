import AVFoundation
import SwiftUI
import UIKit

enum PrivacyResources {
    static let portalBaseURL: URL? = {
        guard
            let rawValue = Bundle.main.object(
                forInfoDictionaryKey: "EasyBidPortalBaseURL"
            ) as? String,
            let url = URL(string: rawValue),
            url.scheme == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }()

    static let policyURL = portalBaseURL?.appending(path: "privacy")
    static let supportURL = portalBaseURL?.appending(path: "support")
    static let choicesURL = policyURL.flatMap {
        URL(string: "\($0.absoluteString)#your-choices")
    }
    static let termsURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!
}

enum AppProtectedResource: String, Identifiable {
    case camera
    case microphone

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .camera: L("Camera")
        case .microphone: L("Microphone")
        }
    }

    var deniedMessage: String {
        switch self {
        case .camera:
            L("Camera access is off. Enable it in Settings to photograph jobs for an estimate.")
        case .microphone:
            L("Microphone access is off. Enable it in Settings when a feature asks to record job audio.")
        }
    }
}

@MainActor
enum AppPermissions {
    static func request(_ resource: AppProtectedResource) async -> Bool {
        let mediaType: AVMediaType = resource == .camera ? .video : .audio
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: mediaType)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func statusText(for resource: AppProtectedResource) -> String {
        let mediaType: AVMediaType = resource == .camera ? .video : .audio
        return switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: L("Allowed")
        case .denied: L("Off")
        case .restricted: L("Restricted")
        case .notDetermined: L("Not requested")
        @unknown default: L("Unknown")
        }
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct PrivacyCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var refreshID = UUID()
    @State private var consentStore = AIConsentStore.shared
    @State private var showConsentPrompt = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        L("EasyBid uses your information to provide accounts, projects, AI-assisted estimates and renders, invoices, client approvals, document storage, and subscriptions. We do not sell personal information or use it for cross-app advertising tracking.")
                    )
                    .font(.system(size: 15))
                } header: {
                    Text(L("Privacy"))
                }

                Section {
                    permissionRow(.camera)

                    Button(L("Open iOS Settings")) {
                        AppPermissions.openSettings()
                    }
                } header: {
                    Text(L("Device permissions"))
                } footer: {
                    Text(
                        L("EasyBid asks for camera access only when you choose to take a job photo. Photo, video, audio, and file selection use Apple’s private system pickers and do not require broad library access.")
                    )
                }

                Section {
                    HStack {
                        Label(L("AI Features"), systemImage: "sparkles")
                        Spacer()
                        Text(aiStatusText)
                            .foregroundStyle(.secondary)
                    }

                    if consentStore.status == .granted {
                        Button(L("Withdraw AI Permission"), role: .destructive) {
                            Task { _ = await consentStore.setConsent(granted: false) }
                        }
                    } else if consentStore.status == .denied {
                        Button(L("Allow AI Features")) {
                            Task { _ = await consentStore.setConsent(granted: true) }
                        }
                    } else if consentStore.status == .unknown {
                        Button(L("Review AI Permission")) {
                            showConsentPrompt = true
                        }
                    }

                    if let errorMessage = consentStore.errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(L("AI permission"))
                } footer: {
                    Text(
                        L("AI Chat and Renders send your messages, relevant project information, and media you intentionally attach to OpenAI. Withdrawing permission immediately blocks new AI requests.")
                    )
                }

                Section(L("Policies and choices")) {
                    if let policyURL = PrivacyResources.policyURL {
                        Link(L("Privacy Policy"), destination: policyURL)
                    }
                    if let choicesURL = PrivacyResources.choicesURL {
                        Link(L("Privacy Choices"), destination: choicesURL)
                    }
                    if let supportURL = PrivacyResources.supportURL {
                        Link(L("EasyBid Support"), destination: supportURL)
                    }
                    Link(L("Terms of Use"), destination: PrivacyResources.termsURL)
                    Text(
                        L("To cancel a subscription: open iPhone Settings, tap your name, choose Subscriptions, select EasyBid, then tap Cancel Subscription.")
                    )
                    .font(.system(size: 14))
                }

                Section {
                    Text(
                        L("To delete your account and associated workspace data, return to the account menu and choose Delete Account.")
                    )
                    .font(.system(size: 14))
                } header: {
                    Text(L("Account deletion"))
                }
            }
            .id(refreshID)
            .navigationTitle(L("Privacy & Permissions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIApplication.didBecomeActiveNotification
                )
            ) { _ in
                refreshID = UUID()
            }
            .task {
                await consentStore.refresh()
            }
            .sheet(isPresented: $showConsentPrompt) {
                AIConsentPromptView(consentStore: consentStore)
            }
        }
    }

    private var aiStatusText: String {
        switch consentStore.status {
        case .unknown: L("Not chosen")
        case .loading: L("Loading…")
        case .granted: L("Allowed")
        case .denied: L("Off")
        }
    }

    private func permissionRow(_ resource: AppProtectedResource) -> some View {
        HStack {
            Label(
                resource.displayName,
                systemImage: resource == .camera ? "camera.fill" : "mic.fill"
            )
            Spacer()
            Text(AppPermissions.statusText(for: resource))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}
