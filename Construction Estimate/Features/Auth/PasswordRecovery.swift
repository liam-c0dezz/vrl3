import Supabase
import SwiftUI

enum PasswordRules {
    static func isValid(_ password: String) -> Bool {
        password.count >= 8 &&
            password.rangeOfCharacter(from: .letters) != nil &&
            password.rangeOfCharacter(from: .decimalDigits) != nil
    }
}

struct ForgotPasswordView: View {
    let initialEmail: String

    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @State private var errorMessage: String?

    init(initialEmail: String = "") {
        self.initialEmail = initialEmail
        _email = State(initialValue: initialEmail)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if didSubmit {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(AppBrand.accent)
                    Text(L("Check your email"))
                        .font(.system(size: 24, weight: .bold))
                    Text(
                        L("If an EasyBid account exists for that email, a password-reset link is on its way. The link can be used only once and may expire.")
                    )
                    .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Done")) { dismiss() }
                        .buttonStyle(PrimaryAuthButtonStyle())
                } else {
                    Text(L("Enter your account email and we'll send a secure reset link."))
                        .foregroundStyle(.secondary)

                    TextField(L("Email"), text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        .authFieldStyle()

                    if let errorMessage {
                        Text(L(errorMessage))
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(L("Send Reset Link"))
                        }
                    }
                    .buttonStyle(PrimaryAuthButtonStyle())
                    .disabled(!normalizedEmail.contains("@") || isSubmitting)
                    Spacer()
                }
            }
            .padding(24)
            .navigationTitle(L("Forgot Password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard normalizedEmail.contains("@"), !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await supabase.auth.resetPasswordForEmail(
                normalizedEmail,
                redirectTo: SupabaseConfig.passwordRecoveryURL
            )
            didSubmit = true
        } catch {
            errorMessage = SafeErrorMessages.authentication(
                error,
                operation: .passwordResetEmail
            )
        }
    }
}

struct PasswordResetView: View {
    var onFinished: ((Bool) -> Void)?

    @Environment(AuthStore.self) private var authStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        PasswordRules.isValid(password) &&
            password == confirmation &&
            !isSubmitting
    }

    init(onFinished: ((Bool) -> Void)? = nil) {
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text(L("Choose a new password"))
                    .font(.system(size: 26, weight: .bold))
                Text(L("Use at least 8 characters with both a letter and a number."))
                    .foregroundStyle(.secondary)

                SecureField(L("New password"), text: $password)
                    .textContentType(.newPassword)
                    .authFieldStyle()

                SecureField(L("Confirm new password"), text: $confirmation)
                    .textContentType(.newPassword)
                    .authFieldStyle()

                if !confirmation.isEmpty && password != confirmation {
                    Text(L("Passwords do not match."))
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }
                if let errorMessage {
                    Text(L(errorMessage))
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await updatePassword() }
                } label: {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text(L("Update Password"))
                    }
                }
                .buttonStyle(PrimaryAuthButtonStyle())
                .disabled(!canSubmit)

                Spacer()
            }
            .padding(24)
            .navigationTitle(L("Reset Password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel")) {
                        Task {
                            try? await supabase.auth.signOut(scope: .local)
                            authStore.completePasswordRecovery()
                            onFinished?(false)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }

    private func updatePassword() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await supabase.auth.update(
                user: UserAttributes(password: password)
            )
            password = ""
            confirmation = ""
            authStore.completePasswordRecovery()
            onFinished?(true)
        } catch {
            errorMessage = SafeErrorMessages.authentication(
                error,
                operation: .passwordUpdate
            )
        }
    }
}

private struct PrimaryAuthButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppBrand.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
