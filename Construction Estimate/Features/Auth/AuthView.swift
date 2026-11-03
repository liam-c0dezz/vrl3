import AuthenticationServices
import CryptoKit
import Observation
import Supabase
import SwiftUI

private struct AccountDeletionRequest: Encodable {
    let apple_authorization_code: String?
}

private struct AccountDeletionResponse: Decodable {
    let deleted: Bool
}

private enum AccountDeletionError: LocalizedError {
    case incomplete
    case server(String)

    var errorDescription: String? {
        switch self {
        case .incomplete:
            return L("Account deletion did not complete. Your account is still active.")
        case let .server(message):
            return message
        }
    }
}

@MainActor
private final class AppleAccountDeletionAuthorizer: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var completion: ((Result<String, Error>) -> Void)?
    private var authorizationController: ASAuthorizationController?

    func requestAuthorization(
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        self.completion = completion

        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(
            authorizationRequests: [request]
        )
        authorizationController = controller
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func presentationAnchor(
        for controller: ASAuthorizationController
    ) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential
            as? ASAuthorizationAppleIDCredential,
            let codeData = credential.authorizationCode,
            let code = String(data: codeData, encoding: .utf8),
            !code.isEmpty else {
            finish(
                with: .failure(
                    AccountDeletionError.server(
                        L("Apple did not return a confirmation code. Please try again.")
                    )
                )
            )
            return
        }
        finish(with: .success(code))
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<String, Error>) {
        let completion = completion
        self.completion = nil
        authorizationController = nil
        completion?(result)
    }
}

@Observable
@MainActor
final class AuthStore {
    private static let onboardingCompletedKey = "onboarding_completed"

    var session: Session?
    var isReady = false
    var isPasswordRecoveryFlow = false
    var isCompletingOnboarding = UserDefaults.standard.bool(forKey: "isCompletingOnboarding")
    var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

    @ObservationIgnored private var authTask: Task<Void, Never>?

    init() {
        authTask = Task {
            for await (event, session) in supabase.auth.authStateChanges {
                if event == .passwordRecovery {
                    self.session = session
                    self.isReady = true
                    self.isPasswordRecoveryFlow = true
                    continue
                }
                guard [.initialSession, .signedIn, .signedOut, .tokenRefreshed].contains(event) else {
                    continue
                }
                self.session = session

                if let session {
                    SuperwallService.identify(session: session)
                    await restoreOnboardingState(from: session)
                } else if event == .signedOut {
                    AIConsentStore.shared.reset()
                    SuperwallService.reset()
                    ProjectStore.shared.reset()
                    ClientStore.shared.reset()
                    InvoiceStore.shared.reset()
                    PaymentStore.shared.reset()
                    BusinessSettingsStore.shared.reset()
                    isCompletingOnboarding = false
                    hasCompletedOnboarding = false
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
                self.isReady = true
            }
        }
    }

    func signOut() async {
        try? await supabase.auth.signOut()
    }

    func acceptAuthenticatedSession(_ session: Session) {
        self.session = session
        isReady = true
    }

    func handleIncomingAuthURL(_ url: URL) async {
        do {
            let incomingSession = try await supabase.auth.session(from: url)
            session = incomingSession
            isReady = true

            if url.host?.lowercased() == SupabaseConfig.passwordRecoveryURL.host?.lowercased() {
                isPasswordRecoveryFlow = true
            }
        } catch {
            // Invalid, expired, already-used, or malformed auth links must not
            // create a recovery state. The user can safely request a new link.
            isPasswordRecoveryFlow = false
        }
    }

    func completePasswordRecovery() {
        isPasswordRecoveryFlow = false
    }

    func usesAppleSignIn() async throws -> Bool {
        let identities = try await supabase.auth.userIdentities()
        return identities.contains { $0.provider == "apple" }
    }

    func deleteAccount(appleAuthorizationCode: String? = nil) async throws {
        let response: AccountDeletionResponse
        do {
            response = try await supabase.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(
                    body: AccountDeletionRequest(
                        apple_authorization_code: appleAuthorizationCode
                    )
                )
            )
        } catch FunctionsError.httpError(_, let data) {
            let message = (try? JSONDecoder().decode(
                AccountDeletionServerError.self,
                from: data
            ))?.error ?? L("Account deletion failed. Your account is still active.")
            throw AccountDeletionError.server(message)
        }

        guard response.deleted else {
            throw AccountDeletionError.incomplete
        }

        BusinessProfile.shared.setLogo(nil)
        // The backend has removed the auth user, so this clears the local
        // Supabase session even though the remote logout endpoint may now
        // report that the user no longer exists.
        try? await supabase.auth.signOut(scope: .local)
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        URLCache.shared.removeAllCachedResponses()
        session = nil
        isCompletingOnboarding = false
        hasCompletedOnboarding = false
    }

    func beginOnboarding() {
        isCompletingOnboarding = true
        UserDefaults.standard.set(true, forKey: "isCompletingOnboarding")
    }

    func completeOnboarding() {
        isCompletingOnboarding = false
        hasCompletedOnboarding = true
        UserDefaults.standard.set(false, forKey: "isCompletingOnboarding")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        Task {
            _ = try? await supabase.auth.update(
                user: UserAttributes(
                    data: [Self.onboardingCompletedKey: .bool(true)]
                )
            )
        }
    }

    private func restoreOnboardingState(from session: Session) async {
        let isCompletedRemotely = session.user.userMetadata[
            Self.onboardingCompletedKey
        ] == .bool(true)
        let isCompletedLocally = UserDefaults.standard.bool(
            forKey: "hasCompletedOnboarding"
        )
        let shouldRestore = isCompletedRemotely
            || isCompletedLocally
            || isReturningAppleAccount(session.user)

        guard shouldRestore else { return }

        isCompletingOnboarding = false
        hasCompletedOnboarding = true
        UserDefaults.standard.set(false, forKey: "isCompletingOnboarding")
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        // Migrate pre-metadata installs so later reinstalls can restore this
        // decision without relying on device-local preferences.
        if !isCompletedRemotely {
            _ = try? await supabase.auth.update(
                user: UserAttributes(
                    data: [Self.onboardingCompletedKey: .bool(true)]
                )
            )
        }
    }

    private func isReturningAppleAccount(_ user: User) -> Bool {
        guard let appleIdentity = user.identities?.first(where: {
            $0.provider == "apple"
        }),
        let identityCreatedAt = appleIdentity.createdAt,
        let lastAppleSignInAt = appleIdentity.lastSignInAt else {
            return false
        }

        // On first authorization these timestamps are effectively identical.
        // A later Apple authorization identifies an existing linked account,
        // including after the app has been reinstalled. The account-age check
        // also migrates Apple users who completed onboarding before the remote
        // completion marker existed and whose Keychain session survived reinstall.
        let hasSignedInAgain = lastAppleSignInAt.timeIntervalSince(
            identityCreatedAt
        ) > 60
        let isEstablishedAccount = Date().timeIntervalSince(user.createdAt) > 86_400
        return hasSignedInAgain || isEstablishedAccount
    }

    deinit {
        authTask?.cancel()
    }
}

private struct AccountDeletionServerError: Decodable {
    let error: String
}

struct AuthRootView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        Group {
            if !authStore.isReady {
                ProgressView()
            } else if authStore.isPasswordRecoveryFlow {
                PasswordResetView()
            } else if authStore.session != nil && authStore.hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView(
                    initialPage: authStore.session != nil && authStore.isCompletingOnboarding
                        ? OnboardingView.firstFeaturePageIndex
                        : 0,
                    onFinish: authStore.completeOnboarding
                )
                .onAppear {
                    authStore.beginOnboarding()
                }
            }
        }
    }
}

struct AuthenticationView: View {
    var onAuthenticated: () -> Void = {}

    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount: Bool
    @State private var isSubmitting = false
    @State private var message: String?
    @State private var appleNonce: String?
    @State private var showForgotPassword = false
    @State private var passwordRecoverySucceeded = false

    private let brandBlue = AppBrand.accent

    init(
        startsInSignInMode: Bool = false,
        onAuthenticated: @escaping () -> Void = {}
    ) {
        self.onAuthenticated = onAuthenticated
        _isCreatingAccount = State(initialValue: !startsInSignInMode)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSubmit: Bool {
        let passwordIsValid = isCreatingAccount
            ? PasswordRules.isValid(password)
            : password.count >= 6
        return normalizedEmail.contains("@") && passwordIsValid && !isSubmitting
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, AppGray.bgPale], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L("Construction Estimate"))
                            .font(.system(size: 29, weight: .bold))
                            .foregroundColor(AppGray.ink)
                        Text(isCreatingAccount ? L("Create your account") : L("Welcome back"))
                            .font(.system(size: 16))
                            .foregroundColor(AppGray.secondary)
                    }

                    VStack(spacing: 12) {
                        TextField(L("Email"), text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .authFieldStyle()

                        SecureField(L("Password"), text: $password)
                            .textContentType(isCreatingAccount ? .newPassword : .password)
                            .authFieldStyle()

                        if isCreatingAccount {
                            Text(L("Use at least 8 characters with a letter and a number."))
                                .font(.system(size: 12))
                                .foregroundStyle(AppGray.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let message {
                        Text(L(message))
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    Button(action: submitEmail) {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(isCreatingAccount ? L("Create Account") : L("Sign In"))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundColor(.white)
                        .background(canSubmit ? brandBlue : AppGray.border)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)

                    if !isCreatingAccount {
                        Button(L("Forgot password?")) {
                            showForgotPassword = true
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brandBlue)
                        .frame(maxWidth: .infinity)
                    }

                    HStack {
                        Rectangle().fill(AppGray.border).frame(height: 1)
                        Text(L("or"))
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                        Rectangle().fill(AppGray.border).frame(height: 1)
                    }

                    SignInWithAppleButton(.continue) { request in
                        let nonce = UUID().uuidString
                        appleNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = sha256(nonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    HStack(spacing: 16) {
                        if let policyURL = PrivacyResources.policyURL {
                            Link(L("Privacy Policy"), destination: policyURL)
                        }
                        Link(L("Terms of Use"), destination: PrivacyResources.termsURL)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(brandBlue)
                    .frame(maxWidth: .infinity)

                    if isCreatingAccount {
                        Text(L("By creating an account, you agree to the Privacy Policy and Terms of Use."))
                            .font(.system(size: 12))
                            .foregroundStyle(AppGray.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }

                    Button(isCreatingAccount ? L("Already have an account? Sign in") : L("Need an account? Create one")) {
                        isCreatingAccount.toggle()
                        message = nil
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(brandBlue)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 28)
                .padding(.top, 90)
            }
        }
        .sheet(isPresented: $showForgotPassword) {
            if authStore.isPasswordRecoveryFlow {
                PasswordResetView { succeeded in
                    passwordRecoverySucceeded = succeeded
                    showForgotPassword = false
                }
            } else {
                ForgotPasswordView(initialEmail: normalizedEmail)
            }
        }
        .onChange(of: showForgotPassword) { _, isPresented in
            guard !isPresented, passwordRecoverySucceeded else { return }
            passwordRecoverySucceeded = false
            onAuthenticated()
            dismiss()
        }
    }

    private func submitEmail() {
        guard canSubmit else { return }
        isSubmitting = true
        message = nil

        Task {
            defer { isSubmitting = false }
            do {
                if isCreatingAccount {
                    let response = try await supabase.auth.signUp(email: normalizedEmail, password: password)
                    if let session = response.session {
                        authStore.acceptAuthenticatedSession(session)
                        onAuthenticated()
                        dismiss()
                    } else {
                        message = L("Check your email to confirm your account, then sign in.")
                    }
                } else {
                    let session = try await supabase.auth.signIn(
                        email: normalizedEmail,
                        password: password
                    )
                    authStore.acceptAuthenticatedSession(session)
                    onAuthenticated()
                    dismiss()
                }
            } catch {
                message = SafeErrorMessages.authentication(
                    error,
                    operation: isCreatingAccount ? .signUp : .signIn
                )
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        guard case let .success(authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce = appleNonce else {
            if case let .failure(error) = result {
                message = SafeErrorMessages.authentication(error, operation: .oauth)
            }
            return
        }

        isSubmitting = true
        message = nil
        Task {
            defer { isSubmitting = false }
            do {
                let session = try await supabase.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(
                        provider: .apple,
                        idToken: idToken,
                        nonce: nonce
                    )
                )
                // Keep navigation deterministic instead of waiting for the
                // auth-state stream to deliver `.signedIn` on a later turn.
                authStore.acceptAuthenticatedSession(session)
                onAuthenticated()
                dismiss()
            } catch {
                message = SafeErrorMessages.authentication(error, operation: .oauth)
            }
        }
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension View {
    func authFieldStyle() -> some View {
        self
            .font(.system(size: 16))
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppGray.border, lineWidth: 1))
    }
}

struct DeleteAccountView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmation = ""
    @State private var usesApple = false
    @State private var isCheckingProvider = true
    @State private var isConfirmingWithApple = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var appleAuthorizer: AppleAccountDeletionAuthorizer?

    private var isConfirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() == "DELETE"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.red)
                        Text(L("Delete your account permanently"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppGray.ink)
                        Text(
                            L("This removes your company workspace, clients, projects, estimates, invoices, chat history stored on this device, and uploaded project files. This cannot be undone.")
                        )
                        .font(.system(size: 15))
                        .foregroundColor(AppGray.secondary)
                    }

                    Text(
                        L("Apple subscriptions are managed separately. To cancel: open iPhone Settings, tap your name, choose Subscriptions, select EasyBid, then tap Cancel Subscription.")
                    )
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Type DELETE to confirm"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                        TextField(L("DELETE"), text: $confirmation)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .authFieldStyle()
                    }

                    if let errorMessage {
                        Text(L(errorMessage))
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                    }

                    if isCheckingProvider {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 52)
                    } else {
                        if usesApple {
                            Text(
                                L("Apple will ask you to confirm so EasyBid can revoke its account access before deletion.")
                            )
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                        }

                        Button(role: .destructive) {
                            if usesApple {
                                requestAppleConfirmation()
                            } else {
                                Task { await performDeletion() }
                            }
                        } label: {
                            Group {
                                if isDeleting || isConfirmingWithApple {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(L("Delete My Account"))
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundColor(.white)
                            .background(isConfirmed ? Color.red : AppGray.border)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            !isConfirmed || isDeleting || isConfirmingWithApple
                        )
                    }
                }
                .padding(24)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(L("Delete Account"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
        .interactiveDismissDisabled(isDeleting)
        .task {
            do {
                usesApple = try await authStore.usesAppleSignIn()
            } catch {
                // Prefer the provider data already present in the session when
                // the identities request is temporarily unavailable.
                usesApple = authStore.session?.user.identities?
                    .contains { $0.provider == "apple" } == true
            }
            isCheckingProvider = false
        }
    }

    private func requestAppleConfirmation() {
        guard isConfirmed, !isDeleting, !isConfirmingWithApple else { return }
        errorMessage = nil
        isConfirmingWithApple = true

        let authorizer = AppleAccountDeletionAuthorizer()
        appleAuthorizer = authorizer
        authorizer.requestAuthorization { result in
            isConfirmingWithApple = false
            appleAuthorizer = nil

            switch result {
            case let .success(code):
                Task { await performDeletion(appleAuthorizationCode: code) }
            case let .failure(error):
                if let authorizationError = error as? ASAuthorizationError,
                   authorizationError.code == .canceled {
                    errorMessage = L("Apple confirmation was canceled.")
                } else if let deletionError = error as? AccountDeletionError {
                    errorMessage = deletionError.localizedDescription
                } else {
                    errorMessage = SafeErrorMessages.authentication(
                        error,
                        operation: .oauth
                    )
                }
            }
        }
    }

    private func performDeletion(appleAuthorizationCode: String? = nil) async {
        guard isConfirmed, !isDeleting else { return }
        isDeleting = true
        errorMessage = nil
        do {
            try await authStore.deleteAccount(
                appleAuthorizationCode: appleAuthorizationCode
            )
            dismiss()
        } catch {
            if let deletionError = error as? AccountDeletionError {
                errorMessage = deletionError.localizedDescription
            } else {
                errorMessage = L("Account deletion couldn't be completed. Please try again.")
            }
            isDeleting = false
        }
    }
}
