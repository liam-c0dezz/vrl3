import Foundation
import Supabase
import PostgREST

enum EstimatePortalError: LocalizedError {
    case estimateNotSynced
    case invalidPortalURL

    var errorDescription: String? {
        switch self {
        case .estimateNotSynced:
            return "This estimate has not finished syncing. Try again in a moment."
        case .invalidPortalURL:
            return "The estimate review link could not be created."
        }
    }
}

struct EstimateShareLinkResponse: Decodable {
    let token: String
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

enum EstimatePortalService {
    static func createReviewURL(for estimate: Estimate) async throws -> URL {
        guard let rawID = estimate.supabaseEstimateId,
              let estimateID = UUID(uuidString: rawID) else {
            throw EstimatePortalError.estimateNotSynced
        }

        struct AppearancePatch: Encodable { let appearance: EstimateAppearance }
        try await supabase.from("estimates")
            .update(AppearancePatch(appearance: estimate.appearance ?? EstimateAppearance()))
            .eq("id", value: estimateID.uuidString)
            .execute()

        struct Parameters: Encodable {
            let pEstimateID: UUID

            private enum CodingKeys: String, CodingKey {
                case pEstimateID = "p_estimate_id"
            }
        }

        let response: EstimateShareLinkResponse = try await supabase
            .rpc(
                "create_estimate_share_link",
                params: Parameters(pEstimateID: estimateID)
            )
            .execute()
            .value

        guard let portalBaseURL = PrivacyResources.portalBaseURL else {
            throw EstimatePortalError.invalidPortalURL
        }

        guard var components = URLComponents(
            url: portalBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw EstimatePortalError.invalidPortalURL
        }
        components.fragment = "token=\(response.token)"

        guard let url = components.url else {
            throw EstimatePortalError.invalidPortalURL
        }
        return url
    }
    static func confirmSent(reviewURL: URL) async throws {
        guard let fragment = URLComponents(url: reviewURL, resolvingAgainstBaseURL: false)?.fragment,
              let token = URLComponents(string: "?" + fragment)?.queryItems?.first(where: { $0.name == "token" })?.value else {
            throw EstimatePortalError.invalidPortalURL
        }
        struct Parameters: Encodable { let p_token: String }
        try await supabase.rpc("confirm_estimate_share_sent", params: Parameters(p_token: token)).execute()
    }

}
