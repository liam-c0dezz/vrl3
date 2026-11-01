import Foundation
import Observation
import Supabase
import UIKit

struct ProjectRender: Identifiable, Codable, Equatable {
    let id: UUID
    let organizationId: UUID
    let projectId: UUID
    let originalImagePath: String
    let currentImagePath: String
    let acceptedImagePath: String?
    let initialPrompt: String
    let status: String
    let createdBy: UUID
    let createdAt: String
    let updatedAt: String
    let acceptedAt: String?

    var isAccepted: Bool {
        status == "accepted" && acceptedImagePath != nil
    }

    var isInvoiceReady: Bool {
        !originalImagePath.isEmpty && !currentImagePath.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case projectId = "project_id"
        case originalImagePath = "original_image_path"
        case currentImagePath = "current_image_path"
        case acceptedImagePath = "accepted_image_path"
        case initialPrompt = "initial_prompt"
        case status
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case acceptedAt = "accepted_at"
    }
}

struct ProjectRenderImages {
    let before: UIImage
    let after: UIImage
}

enum ProjectRenderRecoveryContext: Equatable {
    case create(projectID: UUID, prompt: String, existingRenderIDs: Set<UUID>)
    case revise(renderID: UUID, previousImagePath: String)
    case accept(renderID: UUID)
}

enum ProjectRenderRecovery {
    static func match(
        _ context: ProjectRenderRecoveryContext,
        in renders: [ProjectRender]
    ) -> ProjectRender? {
        switch context {
        case let .create(projectID, prompt, existingRenderIDs):
            return renders.first {
                $0.projectId == projectID &&
                    $0.initialPrompt == prompt &&
                    !existingRenderIDs.contains($0.id)
            }
        case let .revise(renderID, previousImagePath):
            return renders.first {
                $0.id == renderID && $0.currentImagePath != previousImagePath
            }
        case let .accept(renderID):
            return renders.first {
                $0.id == renderID && $0.isAccepted
            }
        }
    }
}

private struct RenderServiceResponse: Decodable {
    let render: ProjectRender
}

private struct RenderServiceError: Decodable {
    let error: String?
    let code: String?
}

private struct RenderServiceRequest: Encodable {
    let requestId: UUID
    let operation: String
    let projectId: UUID
    let renderId: UUID?
    let prompt: String?
    let imageBase64: String?
    let imageMimeType: String?

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case operation
        case projectId = "project_id"
        case renderId = "render_id"
        case prompt
        case imageBase64 = "image_base64"
        case imageMimeType = "image_mime_type"
    }
}

private enum ProjectRenderError: LocalizedError {
    case invalidPhoto
    case invalidResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .invalidPhoto:
            return "That photo could not be prepared. Choose another photo and try again."
        case .invalidResponse:
            return "The render could not be loaded. Please try again."
        case .service(let message):
            return message
        }
    }
}

enum ProjectRenderRepository {
    static func load(projectID: UUID) async throws -> [ProjectRender] {
        try await supabase
            .from("project_renders")
            .select()
            .eq("project_id", value: projectID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func imageData(path: String) async throws -> Data {
        try await supabase.storage
            .from("project-files")
            .download(path: path)
    }
}

@Observable
@MainActor
final class ProjectRenderStore {
    static let shared = ProjectRenderStore()

    private static let requestTimeoutInterval: TimeInterval = 145
    private static let recoveryAttempts = 12
    private static let recoveryDelayNanoseconds: UInt64 = 2_000_000_000

    private let endpoint = URL(
        string: "https://tuykoxmpnmrawrknjikr.supabase.co/functions/v1/render-service"
    )!

    var renders: [ProjectRender] = []
    var isLoading = false
    var isGenerating = false
    var lastError: String?

    @ObservationIgnored private var imageDataCache: [String: Data] = [:]
    @ObservationIgnored private var refreshTasks: [UUID: Task<[ProjectRender], Error>] = [:]

    private init() {}

    func renders(for projectID: UUID) -> [ProjectRender] {
        renders.filter { $0.projectId == projectID }
    }

    func latestAccepted(for projectID: UUID) -> ProjectRender? {
        renders(for: projectID).first(where: \.isAccepted)
    }

    func latestInvoiceReady(for projectID: UUID) -> ProjectRender? {
        renders(for: projectID).first(where: \.isInvoiceReady)
    }

    func refresh(projectID: UUID) async {
        if let existingTask = refreshTasks[projectID] {
            do {
                let loaded = try await existingTask.value
                replaceRenders(loaded, for: projectID)
            } catch {
                lastError = SafeErrorMessages.data(error, action: "render refresh")
            }
            return
        }

        let task = Task { try await ProjectRenderRepository.load(projectID: projectID) }
        refreshTasks[projectID] = task
        isLoading = true
        do {
            let loaded = try await task.value
            replaceRenders(loaded, for: projectID)
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "render refresh")
        }
        refreshTasks[projectID] = nil
        isLoading = !refreshTasks.isEmpty
    }

    private func replaceRenders(_ loaded: [ProjectRender], for projectID: UUID) {
        renders.removeAll { $0.projectId == projectID }
        renders.append(contentsOf: loaded)
    }

    func images(for render: ProjectRender) async throws -> ProjectRenderImages {
        async let beforeData = imageData(for: render.originalImagePath)
        async let afterData = imageData(for: render.acceptedImagePath ?? render.currentImagePath)
        guard let before = UIImage(data: try await beforeData),
              let after = UIImage(data: try await afterData) else {
            throw ProjectRenderError.invalidResponse
        }
        return ProjectRenderImages(before: before, after: after)
    }

    func create(projectID: UUID, photoData: Data, prompt: String) async throws -> ProjectRender {
        guard let prepared = preparedJPEGData(from: photoData) else {
            throw ProjectRenderError.invalidPhoto
        }

        let remoteBaseline = (try? await ProjectRenderRepository.load(projectID: projectID)) ?? []
        let existingRenderIDs = Set(
            (remoteBaseline + renders(for: projectID)).map(\.id)
        )
        return try await perform(
            RenderServiceRequest(
                requestId: UUID(),
                operation: "create",
                projectId: projectID,
                renderId: nil,
                prompt: prompt,
                imageBase64: prepared.base64EncodedString(),
                imageMimeType: "image/jpeg"
            ),
            recoveryContext: .create(
                projectID: projectID,
                prompt: prompt,
                existingRenderIDs: existingRenderIDs
            )
        )
    }

    func revise(_ render: ProjectRender, prompt: String) async throws -> ProjectRender {
        try await perform(
            RenderServiceRequest(
                requestId: UUID(),
                operation: "revise",
                projectId: render.projectId,
                renderId: render.id,
                prompt: prompt,
                imageBase64: nil,
                imageMimeType: nil
            ),
            recoveryContext: .revise(
                renderID: render.id,
                previousImagePath: render.currentImagePath
            )
        )
    }

    func accept(_ render: ProjectRender) async throws -> ProjectRender {
        try await perform(
            RenderServiceRequest(
                requestId: UUID(),
                operation: "accept",
                projectId: render.projectId,
                renderId: render.id,
                prompt: nil,
                imageBase64: nil,
                imageMimeType: nil
            ),
            showsGeneratingState: false,
            recoveryContext: .accept(renderID: render.id)
        )
    }

    private func imageData(for path: String) async throws -> Data {
        if let cached = imageDataCache[path] { return cached }
        let data = try await ProjectRenderRepository.imageData(path: path)
        imageDataCache[path] = data
        return data
    }

    private func perform(
        _ body: RenderServiceRequest,
        showsGeneratingState: Bool = true,
        recoveryContext: ProjectRenderRecoveryContext
    ) async throws -> ProjectRender {
        if showsGeneratingState { isGenerating = true }
        defer { if showsGeneratingState { isGenerating = false } }

        let session = try await supabase.auth.session
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = Self.requestTimeoutInterval

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            if isRecoverableTimeout(error),
               let recovered = await recoverCompletedRender(
                   for: body.projectId,
                   context: recoveryContext
               ) {
                return recovered
            }
            if isRecoverableTimeout(error) {
                throw ProjectRenderError.service(
                    "The render is taking longer than expected. Check the project render page in a moment."
                )
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProjectRenderError.invalidResponse
        }
        if httpResponse.statusCode == 504,
           let recovered = await recoverCompletedRender(
               for: body.projectId,
               context: recoveryContext
           ) {
            return recovered
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let serverError = try? JSONDecoder().decode(RenderServiceError.self, from: data)
            let safeMessage: String
            switch serverError?.code {
            case "consent_required":
                safeMessage = "Allow AI features in Privacy & Permissions to create a render."
            case "rate_limited", "quota_exceeded":
                safeMessage = "You've reached the current AI usage limit. Try again later."
            case "missing_photo", "invalid_photo", "photo_too_large", "invalid_prompt":
                safeMessage = serverError?.error ?? "Check the photo and description, then try again."
            default:
                safeMessage = "The render couldn't be completed. Please try again."
            }
            throw ProjectRenderError.service(safeMessage)
        }

        let render = try JSONDecoder().decode(RenderServiceResponse.self, from: data).render
        if let index = renders.firstIndex(where: { $0.id == render.id }) {
            renders[index] = render
        } else {
            renders.insert(render, at: 0)
        }
        lastError = nil
        return render
    }

    private func recoverCompletedRender(
        for projectID: UUID,
        context: ProjectRenderRecoveryContext
    ) async -> ProjectRender? {
        for attempt in 0..<Self.recoveryAttempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: Self.recoveryDelayNanoseconds)
            }

            guard !Task.isCancelled else { return nil }
            guard let loaded = try? await ProjectRenderRepository.load(projectID: projectID) else {
                continue
            }
            replaceRenders(loaded, for: projectID)

            if let recovered = ProjectRenderRecovery.match(context, in: loaded) {
                lastError = nil
                return recovered
            }
        }
        return nil
    }

    private func isRecoverableTimeout(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .timedOut
    }

    private func preparedJPEGData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 2_048
        let largestDimension = max(image.size.width, image.size.height)
        guard largestDimension > maxDimension else {
            return image.jpegData(compressionQuality: 0.82)
        }

        let scale = maxDimension / largestDimension
        let targetSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }
}
