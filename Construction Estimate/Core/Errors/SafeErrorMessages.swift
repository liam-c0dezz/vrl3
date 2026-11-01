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
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                break
            }
        }

        // Provider text is inspected only to classify common cases. It is
        // never returned directly to the user.
        let providerText = String(describing: error).lowercased()
        if providerText.contains("invalid login credentials") ||
            providerText.contains("invalid_credentials") {
            return "The email or password is incorrect."
        }
        if providerText.contains("email not confirmed") {
            return "Confirm your email before signing in."
        }
        if providerText.contains("already registered") ||
            providerText.contains("user_already_exists") {
            return "An account with that email already exists. Try signing in instead."
        }
        if providerText.contains("rate limit") ||
            providerText.contains("over_email_send_rate_limit") ||
            providerText.contains("429") {
            return "Too many attempts. Wait a moment and try again."
        }
        if providerText.contains("expired") || providerText.contains("otp_expired") {
            return "This link has expired. Request a new one and try again."
        }
        if providerText.contains("weak_password") || providerText.contains("password should") {
            return "Choose a stronger password with at least 8 characters."
        }

        switch operation {
        case .signIn:
            return "Sign in couldn't be completed. Please try again."
        case .signUp:
            return "Your account couldn't be created. Please try again."
        case .passwordResetEmail:
            return "The reset email couldn't be sent. Please wait and try again."
        case .passwordUpdate:
            return "Your password couldn't be updated. Request a new reset link and try again."
        case .oauth:
            return "Sign in couldn't be completed. Please try again."
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
            return "Allow AI features in Privacy & Permissions to continue."
        case "rate_limited":
            return "Too many requests. Wait a moment and try again."
        case "ai_quota_exceeded":
            return "You've reached the current AI usage limit."
        case "request_in_progress":
            return "Your previous request is still processing."
        case "request_failed", "request_expired":
            return "That request couldn't be completed. Please try again."
        case "ai_disabled", "ai_busy", "ai_temporarily_unavailable", "ai_invalid_response":
            return "AI assistance is temporarily unavailable. Please try again."
        case "catalog_scope_unmatched", "catalog_selection_incomplete", "catalog_selection_invalid",
             "clarification_not_applied", "pricing_configuration_missing":
            return payload?.error ?? "I need a more specific work description before I can create this estimate."
        default:
            if statusCode == 401 {
                return "Your session expired. Sign in again and retry."
            }
            if statusCode == 413 {
                return "That attachment is too large. Choose a smaller file."
            }
            if statusCode == 429 {
                return "Too many requests. Wait a moment and try again."
            }
            return "That request couldn't be completed. Please try again."
        }
    }

    static func network(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Check your connection and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                break
            }
        }
        return "The request couldn't be completed. Please try again."
    }

    static func data(_ error: Error, action: String = "change") -> String {
        if let urlError = error as? URLError {
            return network(urlError)
        }
        return "That \(action) couldn't be completed. Please try again."
    }

    static func purchase(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return network(urlError)
        }
        return "The subscription screen couldn't be completed. Please try again."
    }
}

private struct SafeServerErrorPayload: Decodable {
    let code: String?
    let error: String?
}
