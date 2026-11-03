import Foundation

enum AuthenticationOperation {
    case signIn
    case signUp
    case passwordResetEmail
    case passwordUpdate
    case oauth
}

enum SafeErrorMessages {
    static func authentication(
        _ error: Error,
        operation: AuthenticationOperation
    ) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return L("You're offline. Check your connection and try again.")
            case .timedOut:
                return L("The request timed out. Please try again.")
            default:
                break
            }
        }

        // Provider text is inspected only to classify common cases. It is
        // never returned directly to the user.
        let providerText = String(describing: error).lowercased()
        if providerText.contains("invalid login credentials") ||
            providerText.contains("invalid_credentials") {
            return L("The email or password is incorrect.")
        }
        if providerText.contains("email not confirmed") {
            return L("Confirm your email before signing in.")
        }
        if providerText.contains("already registered") ||
            providerText.contains("user_already_exists") {
            return L("An account with that email already exists. Try signing in instead.")
        }
        if providerText.contains("rate limit") ||
            providerText.contains("over_email_send_rate_limit") ||
            providerText.contains("429") {
            return L("Too many attempts. Wait a moment and try again.")
        }
        if providerText.contains("expired") || providerText.contains("otp_expired") {
            return L("This link has expired. Request a new one and try again.")
        }
        if providerText.contains("weak_password") || providerText.contains("password should") {
            return L("Choose a stronger password with at least 8 characters.")
        }

        switch operation {
        case .signIn:
            return L("Sign in couldn't be completed. Please try again.")
        case .signUp:
            return L("Your account couldn't be created. Please try again.")
        case .passwordResetEmail:
            return L("The reset email couldn't be sent. Please wait and try again.")
        case .passwordUpdate:
            return L("Your password couldn't be updated. Request a new reset link and try again.")
        case .oauth:
            return L("Sign in couldn't be completed. Please try again.")
        }
    }

    static func ai(statusCode: Int, responseData: Data) -> String {
        let payload = try? JSONDecoder().decode(
            SafeServerErrorPayload.self,
            from: responseData
        )
        let code = payload?.code

        switch code {
        case "ai_consent_required", "ai_consent_revoked":
            return L("Allow AI features in Privacy & Permissions to continue.")
        case "rate_limited":
            return L("Too many requests. Wait a moment and try again.")
        case "ai_quota_exceeded":
            return L("You've reached the current AI usage limit.")
        case "request_in_progress":
            return L("Your previous request is still processing.")
        case "request_failed", "request_expired":
            return L("That request couldn't be completed. Please try again.")
        case "ai_disabled", "ai_busy", "ai_temporarily_unavailable", "ai_invalid_response":
            return L("AI assistance is temporarily unavailable. Please try again.")
        case "catalog_scope_unmatched", "catalog_selection_incomplete", "catalog_selection_invalid",
             "clarification_not_applied", "pricing_configuration_missing":
            return L(payload?.error ?? "I need a more specific work description before I can create this estimate.")
        default:
            if statusCode == 401 {
                return L("Your session expired. Sign in again and retry.")
            }
            if statusCode == 413 {
                return L("That attachment is too large. Choose a smaller file.")
            }
            if statusCode == 429 {
                return L("Too many requests. Wait a moment and try again.")
            }
            return L("That request couldn't be completed. Please try again.")
        }
    }

    static func network(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return L("You're offline. Check your connection and try again.")
            case .timedOut:
                return L("The request timed out. Please try again.")
            default:
                break
            }
        }
        return L("The request couldn't be completed. Please try again.")
    }

    static func data(_ error: Error, action: String = "change") -> String {
        if let urlError = error as? URLError {
            return network(urlError)
        }
        return L("That %@ couldn't be completed. Please try again.", L(action))
    }

    static func purchase(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return network(urlError)
        }
        return L("The subscription screen couldn't be completed. Please try again.")
    }
}

private struct SafeServerErrorPayload: Decodable {
    let code: String?
    let error: String?
}
