//
//  ChatView.swift
//  Construction Estimate
//

import SwiftUI
import Observation
import Supabase
import UniformTypeIdentifiers
import UIKit

// MARK: - Models

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String   // "user" | "assistant"
    var content: String
    var attachmentKind: String?   // "photo" | "audio" | "video"
    var thumbnailJpeg: Data?      // compressed thumbnail for photo bubbles

    init(id: UUID = UUID(), role: String, content: String,
         attachmentKind: String? = nil, thumbnailJpeg: Data? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.attachmentKind = attachmentKind
        self.thumbnailJpeg = thumbnailJpeg
    }
}

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var messages: [ChatMessage]
    let createdAt: Date
    var customName: String?

    init(id: UUID = UUID(), messages: [ChatMessage] = [], createdAt: Date = Date(), customName: String? = nil) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.customName = customName
    }

    var title: String {
        if let name = customName, !name.isEmpty { return name }
        return messages.first(where: { $0.role == "user" })
            .map { String($0.content.prefix(36)) }
            ?? L("New Chat")
    }

    var subtitle: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = appLocale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    // Creates a named session and persists it, returning the session ID
    @discardableResult
    static func createAndSave(name: String) -> UUID {
        let key = "chat_sessions"
        let session = ChatSession(customName: name)
        var sessions: [ChatSession] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data) {
            sessions = decoded
        }
        sessions.insert(session, at: 0)
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(session.id.uuidString, forKey: "active_session_id")
        }
        return session.id
    }
}

// MARK: - Screening Models

struct ScreeningOptionDTO: Identifiable, Decodable {
    let id: String
    let label: String
}

struct ScreeningQuestionDTO: Identifiable, Decodable {
    let id: String
    let question: String
    let response_type: String
    let help_text: String?
    let options: [ScreeningOptionDTO]
}

struct ScreeningResponse: Decodable {
    let stage: String?
    let reply: String?
    let job_id: String?
    let job_name: String?
    let questions: [ScreeningQuestionDTO]?
}

struct ScreeningPrompt: Identifiable {
    let id = UUID()
    let jobId: String
    let jobName: String
    let questions: [ScreeningQuestionDTO]
}

struct ScreeningAnswer {
    let questionID: String
    let question: String
    let values: [String]
    let optionID: String?
}

private struct ScreeningQuestionField: View {
    let question: ScreeningQuestionDTO
    @Binding var selectedOptionIDs: Set<String>
    @Binding var textAnswer: String

    private var keyboardType: UIKeyboardType {
        switch question.response_type {
        case "number": return .decimalPad
        case "postal_code": return .numbersAndPunctuation
        default: return .default
        }
    }

    private var placeholder: String {
        switch question.response_type {
        case "measurement": return L("Enter dimensions or measurements")
        case "number": return L("Enter a number")
        case "postal_code": return L("Enter ZIP or postal code")
        default: return L("Enter your answer")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppGray.ink)

            if let help = question.help_text, !help.isEmpty {
                Text(help)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
            }

            if question.options.isEmpty {
                TextField(placeholder, text: $textAnswer, axis: .vertical)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppGray.ink)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(question.response_type == "postal_code" ? .characters : .sentences)
                    .autocorrectionDisabled(question.response_type == "postal_code" || question.response_type == "number")
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
            } else {
                ForEach(question.options) { option in
                    let selected = selectedOptionIDs.contains(option.id)
                    HapticButton {
                        select(option)
                    } label: {
                        HStack(spacing: 12) {
                            Text(option.label)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(selected ? .white : AppGray.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundColor(selected ? .white : AppGray.borderStrong)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? AppGray.ink : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func select(_ option: ScreeningOptionDTO) {
        if question.response_type == "multi" {
            if selectedOptionIDs.contains(option.id) {
                selectedOptionIDs.remove(option.id)
            } else if option.label.caseInsensitiveCompare("None") == .orderedSame {
                selectedOptionIDs = [option.id]
            } else {
                let noneIDs = Set(question.options.filter {
                    $0.label.caseInsensitiveCompare("None") == .orderedSame
                }.map(\.id))
                selectedOptionIDs.subtract(noneIDs)
                selectedOptionIDs.insert(option.id)
            }
        } else {
            selectedOptionIDs = [option.id]
        }
    }
}

// MARK: - Screening Card Flow

struct ScreeningCardView: View {
    let prompt: ScreeningPrompt
    var onSubmit: ([ScreeningAnswer]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selections: [String: Set<String>] = [:]
    @State private var textAnswers: [String: String] = [:]

    private var allAnswered: Bool {
        prompt.questions.allSatisfy { !answerValues(for: $0).isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(prompt.questions) { q in
                        ScreeningQuestionField(
                            question: q,
                            selectedOptionIDs: selectionBinding(for: q.id),
                            textAnswer: textBinding(for: q.id)
                        )
                    }
                }
                .padding(20)
            }
            .background(AppGray.bgPale.ignoresSafeArea())
            .navigationTitle(prompt.jobName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppGray.bgPale, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HapticButton("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HapticButton(action: {
                    onSubmit(answers)
                }) {
                    Text(L("Get Estimate"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(allAnswered ? AppGray.ink : AppGray.border)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!allAnswered)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(AppGray.bgPale.ignoresSafeArea(edges: .bottom))
            }
        }
    }

    private var answers: [ScreeningAnswer] {
        prompt.questions.map { question in
            ScreeningAnswer(
                questionID: question.id,
                question: question.question,
                values: answerValues(for: question),
                optionID: question.options.isEmpty ? nil : selections[question.id]?.first
            )
        }
    }

    private func answerValues(for question: ScreeningQuestionDTO) -> [String] {
        if question.options.isEmpty {
            let value = textAnswers[question.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? [] : [value]
        }
        let selected = selections[question.id, default: []]
        return question.options.filter { selected.contains($0.id) }.map(\.label)
    }

    private func selectionBinding(for questionID: String) -> Binding<Set<String>> {
        Binding(
            get: { selections[questionID, default: []] },
            set: { selections[questionID] = $0 }
        )
    }

    private func textBinding(for questionID: String) -> Binding<String> {
        Binding(
            get: { textAnswers[questionID, default: ""] },
            set: { textAnswers[questionID] = $0 }
        )
    }
}

// MARK: - ViewModel

@Observable
final class ChatViewModel {
    var sessions: [ChatSession] = []
    var activeSessionId: UUID = UUID()
    var inputText: String = ""
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var showSidebar: Bool = false
    var pendingEstimate: [String: Any]? = nil
    var pendingEstimateModel: Estimate? = nil
    var pendingEstimateMessageId: UUID? = nil
    var screeningPrompt: ScreeningPrompt? = nil   // persists so it can be reopened
    private var pendingDraftAnswers: [[String: String]]? = nil
    private var pendingDraftID: String? = nil
    var showScreeningSheet: Bool = false
    var screeningSubmitted: Bool = false

    @ObservationIgnored private let sessionsKey = "chat_sessions"
    @ObservationIgnored private let activeIdKey = "active_session_id"
    @ObservationIgnored private let endpoint = URL(string: "https://tuykoxmpnmrawrknjikr.supabase.co/functions/v1/smart-service-v7")!
    @ObservationIgnored private let projectID: UUID?
    @ObservationIgnored private let consentStore = AIConsentStore.shared

    private func authenticatedRequest(url: URL, body: Data? = nil) async throws -> URLRequest {
        let session = try await supabase.auth.session
        var request = URLRequest(url: url)
        // Allow the server's bounded high-reasoning pipeline to complete.
        request.timeoutInterval = 200
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = body
        return request
    }

    /// Recover an existing result before starting a new attempt after a confirmed failure.
    private func performEstimateRequest(body: Data) async throws -> (Data, URLResponse) {
        guard var payload = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        var recoveryCount = 0
        var checkedFailure = false
        var validationFailed = false
        var networkFailures = 0
        let deadline = Date().addingTimeInterval(420)
        while true {
            try Task.checkCancellation()
            guard consentStore.isGranted else { throw CancellationError() }
            do {
                let requestBody = try JSONSerialization.data(withJSONObject: payload)
                let request = try await authenticatedRequest(url: endpoint, body: requestBody)
                let (data, response) = try await URLSession.shared.data(for: request)
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                let status = json?["http_status"] as? Int ?? (response as? HTTPURLResponse)?.statusCode ?? 500
                let code = json?["code"] as? String ?? ""
                if ["residential_validation", "catalog_resolution"].contains(code) { validationFailed = true }
                if Date() < deadline {
                    if code == "request_in_progress" {
                        try await Task.sleep(for: .seconds(2))
                        continue
                    }
                    let recoverable = ["request_failed", "residential_validation", "catalog_resolution", "estimator_timeout", "internal_error"]
                    if recoverable.contains(code), !checkedFailure {
                        checkedFailure = true
                        // A save may have committed even when its response was lost.
                        try await Task.sleep(for: .seconds(1))
                        continue
                    }
                    if code == "request_failed", recoveryCount < 1, !validationFailed {
                        recoveryCount += 1
                        checkedFailure = false
                        payload["request_id"] = UUID().uuidString
                        try await Task.sleep(for: .seconds(1))
                        continue
                    }
                }
                if status >= 400, let url = response.url,
                   let normalized = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) {
                    return (data, normalized)
                }
                return (data, response)
            } catch let error as URLError {
                let retryable: [URLError.Code] = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost]
                guard retryable.contains(error.code), networkFailures < 3, Date() < deadline else { throw error }
                networkFailures += 1
                try await Task.sleep(for: .seconds(2))
                // Keep the request ID to avoid duplicating saved estimates.
            }
        }
    }

    var activeSession: ChatSession {
        sessions.first(where: { $0.id == activeSessionId }) ?? ChatSession()
    }

    var activeMessages: [ChatMessage] {
        activeSession.messages
    }

    init(projectID: UUID? = nil) {
        self.projectID = projectID
        loadSessions()
    }

    // MARK: - Persistence

    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([ChatSession].self, from: data),
           !decoded.isEmpty {
            sessions = decoded
            if let savedId = UserDefaults.standard.string(forKey: activeIdKey),
               let uuid = UUID(uuidString: savedId),
               sessions.contains(where: { $0.id == uuid }) {
                activeSessionId = uuid
            } else {
                activeSessionId = sessions[0].id
            }
        } else {
            let initial = ChatSession()
            sessions = [initial]
            activeSessionId = initial.id
            saveSessions()
        }
    }

    private func saveSessions() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
        UserDefaults.standard.set(activeSessionId.uuidString, forKey: activeIdKey)
    }

    private func updateActiveSession(_ block: (inout ChatSession) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == activeSessionId }) else { return }
        block(&sessions[idx])
        saveSessions()
    }

    // MARK: - Session Management

    func newChat() {
        let session = ChatSession()
        sessions.insert(session, at: 0)
        activeSessionId = session.id
        inputText = ""
        errorMessage = nil
        showSidebar = false
        pendingDraftAnswers = nil
        pendingDraftID = nil
        pendingEstimate = nil
        pendingEstimateModel = nil
        pendingEstimateMessageId = nil
        screeningPrompt = nil
        showScreeningSheet = false
        screeningSubmitted = false
        saveSessions()
    }

    func switchSession(_ id: UUID) {
        activeSessionId = id
        inputText = ""
        errorMessage = nil
        showSidebar = false
        UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
    }

    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let fresh = ChatSession()
            sessions = [fresh]
            activeSessionId = fresh.id
        } else if activeSessionId == id {
            activeSessionId = sessions[0].id
        }
        saveSessions()
    }

    func clearActiveChat() {
        updateActiveSession { $0.messages = [] }
        errorMessage = nil
    }

    // MARK: - Send (text)

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard requireAIConsent(), !text.isEmpty, !isLoading else { return }

        errorMessage = nil
        inputText = ""
        updateActiveSession { $0.messages.append(ChatMessage(role: "user", content: text)) }

        isLoading = true
        let requestID = UUID()
        Task { await postMessages(requestID: requestID) }
    }

    private func postMessages(requestID: UUID) async {
        defer { isLoading = false }

        let apiMessages = boundedAPIMessages()
        var payload: [String: Any] = [
            "request_id": requestID.uuidString,
            "messages": apiMessages,
            "chat_session_id": activeSessionId.uuidString
        ]
        if let pendingDraftAnswers, let pendingDraftID {
            payload["draft_id"] = pendingDraftID
            payload["draft_answers"] = pendingDraftAnswers
        }
        if let projectID {
            payload["project_id"] = projectID.uuidString
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        do {
            let (data, response) = try await performEstimateRequest(body: body)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = SafeErrorMessages.ai(
                    statusCode: http.statusCode,
                    responseData: data
                )
                return
            }
            guard consentStore.isGranted else {
                errorMessage = L("AI permission was withdrawn before this request completed.")
                return
            }
            applyReply(from: data)
            pendingDraftAnswers = nil
            pendingDraftID = nil
        } catch {
            errorMessage = SafeErrorMessages.network(error)
        }
    }

    #if DEBUG
    /// Uses the production request/recovery path; only synthetic QA scopes are supplied.
    @MainActor
    func acceptanceRequest(scope: String, sessionID: UUID, imageData: Data? = nil) async throws -> (Data, Int, UUID) {
        // A cold launch into Settings has not opened the normal chat consent loader.
        await consentStore.refresh()
        // Retry a failed read, never a denied decision or absent consent record.
        if consentStore.status == .unknown, consentStore.errorMessage != nil {
            try Task.checkCancellation()
            await consentStore.refresh()
        }
        guard consentStore.isGranted else {
            throw NSError(domain: "EstimatorAcceptance", code: 1, userInfo: [
                NSLocalizedDescriptionKey: consentStore.errorMessage ?? L("AI permission is not granted for this test.")
            ])
        }
        guard let projectID else {
            throw NSError(domain: "EstimatorAcceptance", code: 2, userInfo: [
                NSLocalizedDescriptionKey: L("The QA project is no longer available.")
            ])
        }
        let requestID = UUID()
        var payload: [String: Any] = [
            "request_id": requestID.uuidString,
            "messages": [["role": "user", "content": scope]],
            "chat_session_id": sessionID.uuidString,
            "project_id": projectID.uuidString
        ]
        if let imageData {
            payload["attachment_kind"] = "photo"
            payload["attachment_mime_type"] = "image/png"
            payload["attachment_base64"] = imageData.base64EncodedString()
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await performEstimateRequest(body: body)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 500, requestID)
    }
    #endif

    // MARK: - Screening submit

    func submitScreening(_ prompt: ScreeningPrompt, answers: [ScreeningAnswer]) {
        guard !isLoading else { return }
        errorMessage = nil
        screeningSubmitted = true
        showScreeningSheet = false
        screeningPrompt = nil
        pendingDraftID = prompt.jobId
        pendingDraftAnswers = answers.map { answer in
            var entry = ["question_id": answer.questionID]
            if let optionID = answer.optionID {
                entry["option_id"] = optionID
            } else {
                entry["text"] = answer.values.joined(separator: ", ")
            }
            return entry
        }
        inputText = formattedScreeningAnswers(prompt: prompt, answers: answers)
        send()
    }

    // Sheet closed. If the contractor backed out without finishing, drop a
    // chat message so they can reopen the questions later.
    func onScreeningSheetDismissed() {
        guard !screeningSubmitted, screeningPrompt != nil else { return }
        updateActiveSession {
            $0.messages.append(ChatMessage(
                role: "assistant",
                content: L("Answer a few questions to finish your estimate."),
                attachmentKind: "screening_prompt"
            ))
        }
    }

    func reopenScreening() {
        guard screeningPrompt != nil else { return }
        screeningSubmitted = false
        showScreeningSheet = true
    }

    private func formattedScreeningAnswers(
        prompt: ScreeningPrompt,
        answers: [ScreeningAnswer]
    ) -> String {
        let details = answers.map { answer in
            "[\(answer.questionID)] \(answer.question): \(answer.values.joined(separator: ", "))"
        }.joined(separator: "\n")
        return "Project details for \(prompt.jobName):\n\(details)"
    }

    func editEstimate(estimateID: String, instruction: String) async throws -> ([String: Any], String) {
        guard requireAIConsent() else {
            throw NSError(
                domain: "EasyBid.AIEdit",
                code: 403,
                userInfo: [NSLocalizedDescriptionKey: L("Allow AI features before editing with AI.")]
            )
        }
        guard let projectID else {
            throw NSError(
                domain: "EasyBid.AIEdit",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: L("This estimate is not connected to a project.")]
            )
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        let payload: [String: Any] = [
            "request_id": UUID().uuidString,
            "operation": "edit_estimate",
            "project_id": projectID.uuidString,
            "estimate_id": estimateID,
            "edit_instruction": String(instruction.prefix(2_000))
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = try await authenticatedRequest(url: endpoint, body: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200...299).contains(statusCode) else {
            throw NSError(
                domain: "EasyBid.AIEdit",
                code: statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: SafeErrorMessages.ai(
                        statusCode: statusCode,
                        responseData: data
                    )
                ]
            )
        }
        guard consentStore.isGranted else {
            throw NSError(
                domain: "EasyBid.AIEdit",
                code: 403,
                userInfo: [
                    NSLocalizedDescriptionKey: L("AI permission was withdrawn before this request completed.")
                ]
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let estimate = json["structured_estimate"] as? [String: Any],
              let returnedID = json["estimate_id"] as? String,
              returnedID == estimateID else {
            throw NSError(
                domain: "EasyBid.AIEdit",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: L("The edited estimate could not be loaded. Please try again.")]
            )
        }
        return (estimate, returnedID)
    }

    // MARK: - Send (photo)

    func sendWithPhoto(caption: String, imageData: Data) {
        guard requireAIConsent(), !isLoading else { return }
        errorMessage = nil
        inputText = ""
        let thumbnail = UIImage(data: imageData).flatMap { $0.jpegData(compressionQuality: 0.25) }
        let displayContent = caption.isEmpty ? L("📷 Photo") : caption
        let msg = ChatMessage(role: "user", content: displayContent,
                              attachmentKind: "photo", thumbnailJpeg: thumbnail)
        updateActiveSession { $0.messages.append(msg) }
        isLoading = true
        let sendBase64 = (UIImage(data: imageData)?.jpegData(compressionQuality: 0.6) ?? imageData)
            .base64EncodedString()
        Task {
            await postWithImage(
                requestID: UUID(),
                caption: displayContent,
                base64: sendBase64
            )
        }
    }

    private func postWithImage(requestID: UUID, caption: String, base64: String) async {
        defer { isLoading = false }
        let history = boundedAPIMessages(droppingLast: true)
        var payload: [String: Any] = [
            "request_id": requestID.uuidString,
            "messages": history,
            "attachment_kind": "photo",
            "attachment_mime_type": "image/jpeg",
            "attachment_base64": base64,
            "image_caption": String(caption.prefix(2_000))
        ]
        if let projectID {
            payload["project_id"] = projectID.uuidString
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        do {
            let (data, response) = try await performEstimateRequest(body: body)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = SafeErrorMessages.ai(
                    statusCode: http.statusCode,
                    responseData: data
                )
                return
            }
            guard consentStore.isGranted else {
                errorMessage = L("AI permission was withdrawn before this request completed.")
                return
            }
            applyReply(from: data)
        } catch {
            errorMessage = SafeErrorMessages.network(error)
        }
    }

    func sendWithMedia(caption: String, attachment: PreparedAIAttachment) {
        guard requireAIConsent(), !isLoading else { return }
        errorMessage = nil
        inputText = ""
        let content = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayContent = content.isEmpty ? attachment.displayName : content
        updateActiveSession {
            $0.messages.append(ChatMessage(
                role: "user",
                content: displayContent,
                attachmentKind: attachment.kind.rawValue,
                thumbnailJpeg: attachment.thumbnailJPEG
            ))
        }
        isLoading = true
        Task {
            await postWithMedia(
                requestID: UUID(),
                caption: displayContent,
                attachment: attachment
            )
        }
    }

    private func postWithMedia(
        requestID: UUID,
        caption: String,
        attachment: PreparedAIAttachment
    ) async {
        defer { isLoading = false }
        let history = boundedAPIMessages(droppingLast: true)
        var payload = attachment.requestPayload
        payload["request_id"] = requestID.uuidString
        payload["messages"] = Array(history)
        payload["image_caption"] = String(caption.prefix(2_000))
        if let projectID { payload["project_id"] = projectID.uuidString }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            errorMessage = L("That attachment couldn't be prepared. Please try another file.")
            return
        }

        do {
            let (data, response) = try await performEstimateRequest(body: body)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                errorMessage = SafeErrorMessages.ai(
                    statusCode: http.statusCode,
                    responseData: data
                )
                return
            }
            guard consentStore.isGranted else {
                errorMessage = L("AI permission was withdrawn before this request completed.")
                return
            }
            applyReply(from: data)
        } catch {
            errorMessage = SafeErrorMessages.network(error)
        }
    }

    private func requireAIConsent() -> Bool {
        guard consentStore.isGranted else {
            errorMessage = L("Allow AI features before using AI Chat.")
            return false
        }
        return true
    }

    private func boundedAPIMessages(droppingLast: Bool = false) -> [[String: String]] {
        let source = droppingLast ? Array(activeMessages.dropLast()) : activeMessages
        var remainingCharacters = 50_000
        var reversedMessages: [[String: String]] = []
        for message in source.suffix(50).reversed() {
            guard remainingCharacters > 0 else { break }
            let maximum = min(5_000, remainingCharacters)
            let content = String(message.content.prefix(maximum))
            remainingCharacters -= content.count
            reversedMessages.append(["role": message.role, "content": content])
        }
        return Array(reversedMessages.reversed())
    }

    // MARK: - Shared reply handler (never changes — preserves all existing estimate logic)

    private func applyReply(from data: Data) {
        // Screening stage: server returned questions, not an estimate.
        if let resp = try? JSONDecoder().decode(ScreeningResponse.self, from: data),
           resp.stage == "screening",
           let jobId = resp.job_id,
           let questions = resp.questions, !questions.isEmpty {
            screeningPrompt = ScreeningPrompt(
                jobId: jobId,
                jobName: resp.job_name ?? L("Job"),
                questions: questions
            )
            screeningSubmitted = false
            showScreeningSheet = true
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = json["reply"] as? String else {
            errorMessage = L("Couldn't parse response from server.")
            return
        }
        let newMsg = ChatMessage(role: "assistant", content: reply)
        updateActiveSession { $0.messages.append(newMsg) }
        if (json["turn_stage"] as? String) == "intake" {
            errorMessage = reply
        }
        let isStage3Server = (json["stage"] as? Int) == 3
        let replyLower = reply.lowercased().replacingOccurrences(of: "*", with: "")
        let isStage3Client = replyLower.contains("recommended quote") || replyLower.contains("total range")
        if (isStage3Server || isStage3Client),
           let estDict = json["structured_estimate"] as? [String: Any] {
            pendingEstimate = estDict
            pendingEstimateMessageId = newMsg.id
            pendingEstimateModel = Estimate.from(
                dict: estDict,
                chatSessionId: activeSessionId,
                estimateNumber: "EST-DRAFT",
                supabaseEstimateId: json["estimate_id"] as? String
            )
        }
    }
}

// MARK: - Chat Screen

struct ChatView: View {
    var initialSessionId: UUID? = nil
    var projectID: UUID? = nil
    var onEstimateConfirmed: (([String: Any], String?) -> Void)? = nil
    @State private var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    // Address (persisted)
    @State private var selectedAddress: String = UserDefaults.standard.string(forKey: "saved_address") ?? ""
    @State private var showAddressSheet: Bool = false
    @State private var addressDraft: String = ""

    // Media attachment
    @State private var showAttachmentSheet: Bool = false
    @State private var showPhotoPicker: Bool = false
    @State private var showCameraPicker: Bool = false
    @State private var pendingImageData: Data? = nil
    @State private var showMediaFilePicker = false
    @State private var pendingMediaAttachment: PreparedAIAttachment?
    @State private var isPreparingAttachment = false
    @State private var attachmentErrorMessage: String?
    @State private var consentStore = AIConsentStore.shared
    @State private var showAIConsentPrompt = false
    @State private var deniedPermission: AppProtectedResource?

    private let brandBlue = AppBrand.accent
    private let sidebarWidth: CGFloat = UIScreen.main.bounds.width * 0.82

    init(
        initialSessionId: UUID? = nil,
        projectID: UUID? = nil,
        onEstimateConfirmed: (([String: Any], String?) -> Void)? = nil,
        viewModel: ChatViewModel? = nil
    ) {
        self.initialSessionId = initialSessionId
        self.projectID = projectID
        self.onEstimateConfirmed = onEstimateConfirmed
        _vm = State(initialValue: viewModel ?? ChatViewModel(projectID: projectID))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Chat view — never moves
            VStack(spacing: 0) {
                chatNavBar

                ZStack {
                    messageList
                    if vm.activeMessages.isEmpty && !vm.isLoading {
                        emptyState
                    }
                }
                .background(Color.white)

                if let err = vm.errorMessage {
                    Text(L(err))
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(UIColor.systemRed).opacity(0.08))
                }

                inputBar
                    .background(Color(UIColor.systemBackground))
            }
            .allowsHitTesting(!vm.showSidebar)

            // Dim — covers the chat, tap to close
            Color.black
                .opacity(vm.showSidebar ? 0.35 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(vm.showSidebar)
                .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { vm.showSidebar = false } }

            // Sidebar — slides over the top
            ChatSidebarView(vm: vm)
                .frame(width: sidebarWidth)
                .offset(x: vm.showSidebar ? 0 : -sidebarWidth)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.showSidebar)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        // Photo library
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView { data in
                pendingImageData = data
                pendingMediaAttachment = nil
            }
        }
        // Camera
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPickerView { data in
                pendingImageData = data
                pendingMediaAttachment = nil
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showMediaFilePicker,
            allowedContentTypes: [.audio, .movie],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else {
                if case .failure = result {
                    attachmentErrorMessage = L("That attachment couldn't be opened.")
                }
                return
            }
            isPreparingAttachment = true
            attachmentErrorMessage = nil
            Task {
                defer { isPreparingAttachment = false }
                do {
                    pendingMediaAttachment = try await AIAttachmentPreparer.prepare(url: url)
                    pendingImageData = nil
                } catch let error as LocalizedError {
                    attachmentErrorMessage = error.errorDescription ??
                        L("That attachment couldn't be prepared.")
                } catch {
                    attachmentErrorMessage = L("That attachment couldn't be prepared.")
                }
            }
        }
        // Screening questions (card flow)
        .sheet(isPresented: Binding(
            get: { vm.showScreeningSheet },
            set: { vm.showScreeningSheet = $0 }
        ), onDismiss: { vm.onScreeningSheetDismissed() }) {
            if let prompt = vm.screeningPrompt {
                ScreeningCardView(prompt: prompt) { answers in
                    vm.submitScreening(prompt, answers: answers)
                }
            }
        }
        .sheet(isPresented: $showAIConsentPrompt) {
            AIConsentPromptView(consentStore: consentStore)
        }
        .task {
            await consentStore.refresh()
            showAIConsentPrompt = consentStore.status == .unknown
        }
        .alert(item: $deniedPermission) { resource in
            Alert(
                title: Text(L("%@ Access Needed", "\(resource.displayName)")),
                message: Text(resource.deniedMessage),
                primaryButton: .default(Text(L("Open Settings"))) {
                    AppPermissions.openSettings()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Nav Bar

    private var chatNavBar: some View {
        ZStack {
            // True center title
            Text(vm.activeSession.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            // Buttons pinned to edges
            HStack {
                HapticButton(action: { withAnimation { vm.showSidebar.toggle() } }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                }

                Spacer()

                HapticButton(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.white)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(vm.activeMessages) { msg in
                        let isPendingEstimateMsg = msg.id == vm.pendingEstimateMessageId
                        // Show the confirm button on whichever message produced the pending estimate,
                        // not just the most recent assistant message — otherwise any follow-up reply
                        // (revisions, clarifications) hides the button until a new estimate is generated.
                        let showConfirm = isPendingEstimateMsg && vm.pendingEstimate != nil && !vm.isLoading
                        BubbleView(
                            message: msg,
                            address: selectedAddress,
                            structuredEstimate: isPendingEstimateMsg ? vm.pendingEstimateModel : nil,
                            showConfirmButtons: showConfirm,
                            screeningActive: vm.screeningPrompt != nil,
                            onFinishScreening: { vm.reopenScreening() },
                            onConfirm: {
                                if let est = vm.pendingEstimate {
                                    onEstimateConfirmed?(est, vm.pendingEstimateModel?.supabaseEstimateId)
                                    vm.pendingEstimate = nil
                                    vm.pendingEstimateModel = nil
                                    vm.pendingEstimateMessageId = nil
                                    dismiss()
                                }
                            }
                        )
                        .id(msg.id)
                    }
                    if vm.isLoading {
                        TypingIndicator()
                            .id("typing")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: vm.activeMessages) { _, _ in scrollToBottom(proxy: proxy) }
            .onChange(of: vm.isLoading) { _, _ in scrollToBottom(proxy: proxy) }
            .onChange(of: vm.activeSessionId) { _, _ in scrollToBottom(proxy: proxy) }
        }
        // Tap anywhere in the message area to dismiss the keyboard. simultaneousGesture
        // keeps message-bubble buttons (links, confirm, etc.) tappable.
        .simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if vm.isLoading {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = vm.activeMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(L("How can I help you?"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppBrand.accent)
                .multilineTextAlignment(.center)

            if consentStore.status == .denied {
                Text(L("AI features are off. Non-AI EasyBid features still work normally."))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HapticButton("Enable AI Features") {
                    showAIConsentPrompt = true
                }
                .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        normalInputBar
            .background(Color(UIColor.systemBackground))
            .sheet(isPresented: $showAddressSheet) {
                AddressInputSheet(address: $selectedAddress, draft: $addressDraft)
                    .presentationDetents([.height(200)])
            }
            .onAppear {
                if let id = initialSessionId,
                   vm.sessions.contains(where: { $0.id == id }) {
                    vm.switchSession(id)
                }
            }
    }

    private var normalInputBar: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Image preview (shown when a photo is staged)
            if let imgData = pendingImageData, let uiImg = UIImage(data: imgData) {
                HStack(spacing: 10) {
                    Image(uiImage: uiImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(L("Photo attached"))
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                    Spacer()
                    HapticButton(action: { pendingImageData = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppGray.borderStrong)
                    }
                }
                .padding(.horizontal, 4)
            }

            if let attachment = pendingMediaAttachment {
                HStack(spacing: 10) {
                    if let thumbnail = attachment.thumbnailJPEG,
                       let image = UIImage(data: thumbnail) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: attachment.kind == .video ? "video.fill" : "waveform")
                            .font(.system(size: 22))
                            .frame(width: 56, height: 56)
                            .background(AppGray.bgSubtle)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Text(attachment.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                    Spacer()
                    HapticButton {
                        pendingMediaAttachment = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppGray.borderStrong)
                    }
                }
                .padding(.horizontal, 4)
            }

            if isPreparingAttachment {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("Preparing attachment…"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            if let attachmentErrorMessage {
                Text(L(attachmentErrorMessage))
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            // Text field
            TextField(L("Ask anything about your estimate…"), text: $vm.inputText, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 15))
                .foregroundColor(Color(UIColor.label))
                .onSubmit { sendMessage() }

            // Bottom row
            HStack(spacing: 8) {

                // Attach (photo / camera / files)
                HapticButton(action: { showAttachmentSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black.opacity(0.5))
                        .frame(width: 34, height: 34)
                        .background(AppGray.bgSubtle)
                        .clipShape(Circle())
                }
                .confirmationDialog(L("Add Attachment"), isPresented: $showAttachmentSheet) {
                    HapticButton("Take Photo") {
                        requestPermission(.camera) {
                            showCameraPicker = true
                        }
                    }
                    HapticButton("Photo Library") { showPhotoPicker = true }
                    HapticButton("Audio or Video File") { showMediaFilePicker = true }
                    HapticButton("Cancel", role: .cancel) {}
                }

                // Address pill
                HapticButton(action: { showAddressSheet = true }) {
                    HStack(spacing: 5) {
                        Image("location pin")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundColor(.black.opacity(0.5))
                            .frame(width: 18, height: 18)
                        if !selectedAddress.isEmpty {
                            Text(selectedAddress)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.black.opacity(0.6))
                                .lineLimit(1)
                            HapticButton(action: {
                                selectedAddress = ""
                                UserDefaults.standard.removeObject(forKey: "saved_address")
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black.opacity(0.4))
                            }
                        }
                    }
                    .padding(.horizontal, selectedAddress.isEmpty ? 0 : 10)
                    .frame(height: 34)
                    .frame(minWidth: 34)
                    .background(AppGray.bgSubtle)
                    .clipShape(Capsule())
                }

                Spacer()

                // Send
                HapticButton(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? brandBlue : AppGray.border)
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(brandBlue.opacity(0.5), lineWidth: 1.5))
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 36)
    }

    private var canSend: Bool {
        consentStore.isGranted &&
            !vm.isLoading &&
            !isPreparingAttachment &&
            (!vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                pendingImageData != nil ||
                pendingMediaAttachment != nil)
    }

    private func requestPermission(
        _ resource: AppProtectedResource,
        onGranted: @escaping @MainActor () -> Void
    ) {
        Task {
            if await AppPermissions.request(resource) {
                onGranted()
            } else {
                deniedPermission = resource
            }
        }
    }

    private func sendMessage() {
        attachmentErrorMessage = nil
        if let attachment = pendingMediaAttachment {
            pendingMediaAttachment = nil
            vm.sendWithMedia(caption: vm.inputText, attachment: attachment)
        } else if let imgData = pendingImageData {
            pendingImageData = nil
            vm.sendWithPhoto(caption: vm.inputText, imageData: imgData)
        } else {
            vm.send()
        }
    }
}

// MARK: - Guided Estimate Creation

private enum GuidedEstimateStep {
    case description
    case questions
    case result
}

struct GuidedEstimateFlowView: View {
    let initialSessionId: UUID?
    let projectID: UUID
    let onEstimateConfirmed: ([String: Any], String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vm: ChatViewModel
    @State private var step: GuidedEstimateStep = .description
    @State private var projectDescription = ""
    @State private var selections: [String: Set<String>] = [:]
    @State private var textAnswers: [String: String] = [:]
    @State private var activeScreeningPrompt: ScreeningPrompt?
    @State private var resultEstimate: Estimate?
    @State private var resultPayload: [String: Any]?
    @State private var resultSupabaseID: String?
    @State private var estimateRows: [EstimateItemRow]? = nil
    @State private var showAIEditor = false
    @State private var showGenerationProgress = false
    @State private var showAIConsentPrompt = false
    @State private var consentStore = AIConsentStore.shared
    @State private var showPhotoPicker = false
    @State private var showCameraPicker = false
    @State private var pendingImageData: Data?
    @State private var deniedPermission: AppProtectedResource?
    #if DEBUG
    @State private var showAcceptanceRunner = false
    #endif

    init(
        initialSessionId: UUID?,
        projectID: UUID,
        onEstimateConfirmed: @escaping ([String: Any], String?) -> Void
    ) {
        self.initialSessionId = initialSessionId
        self.projectID = projectID
        self.onEstimateConfirmed = onEstimateConfirmed
        _vm = State(initialValue: ChatViewModel(projectID: projectID))
    }

    private var trimmedDescription: String {
        projectDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allQuestionsAnswered: Bool {
        guard let prompt = activeScreeningPrompt else { return false }
        return prompt.questions.allSatisfy { !answerValues(for: $0).isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            switch step {
            case .description:
                descriptionStep
            case .questions:
                questionsStep
            case .result:
                resultStep
            }
        }
        .background(AppGray.bgPale.ignoresSafeArea())
        #if DEBUG
        .sheet(isPresented: $showAcceptanceRunner) {
            EstimatorAcceptanceRunnerView(projectID: projectID)
        }
        #endif
        .overlay {
            if showGenerationProgress {
                EstimateGenerationProgressView(isComplete: !vm.isLoading && step == .result)
            }
        }
        .interactiveDismissDisabled(showGenerationProgress)
        .task(id: vm.isLoading) {
            if vm.isLoading {
                guard step != .result, !showAIEditor else { return }
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                showGenerationProgress = true
            } else if showGenerationProgress {
                if vm.pendingEstimateModel != nil {
                    // Let the counter reach 100 only after a successful response.
                    do { try await Task.sleep(for: .milliseconds(600)) }
                    catch { return }
                }
                guard !Task.isCancelled else { return }
                showGenerationProgress = false
            }
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView { data in
                pendingImageData = data
            }
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPickerView { data in
                pendingImageData = data
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAIEditor) {
            EstimateAIEditSheet { instruction in
                guard let estimateID = resultSupabaseID else {
                    throw NSError(
                        domain: "EasyBid.AIEdit",
                        code: 400,
                        userInfo: [NSLocalizedDescriptionKey: L("The estimate draft is still loading. Please try again.")]
                    )
                }
                let (payload, returnedID) = try await vm.editEstimate(
                    estimateID: estimateID,
                    instruction: instruction
                )
                await MainActor.run {
                    applyEditedEstimate(payload, returnedID)
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showAIConsentPrompt) {
            AIConsentPromptView(consentStore: consentStore)
        }
        .alert(item: $deniedPermission) { resource in
            Alert(
                title: Text(L("%@ Access Needed", "\(resource.displayName)")),
                message: Text(resource.deniedMessage),
                primaryButton: .default(Text(L("Open Settings"))) {
                    AppPermissions.openSettings()
                },
                secondaryButton: .cancel()
            )
        }
        .task {
            if let initialSessionId,
               vm.sessions.contains(where: { $0.id == initialSessionId }) {
                vm.switchSession(initialSessionId)
            }
            await consentStore.refresh()
            showAIConsentPrompt = consentStore.status == .unknown
        }
        .onChange(of: vm.screeningPrompt?.id) { _, promptID in
            guard promptID != nil, let prompt = vm.screeningPrompt else { return }
            activeScreeningPrompt = prompt
            vm.showScreeningSheet = false
            selections = [:]
            textAnswers = [:]
            withAnimation(.easeInOut(duration: 0.2)) {
                step = .questions
            }
        }
        .onChange(of: vm.pendingEstimateMessageId) { _, messageID in
            guard messageID != nil,
                  let estimate = vm.pendingEstimateModel,
                  let payload = vm.pendingEstimate else { return }
            showResult(estimate: estimate, payload: payload, supabaseID: estimate.supabaseEstimateId)
        }
    }

    private var navigationBar: some View {
        ZStack {
            Text(L(navigationTitle))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            HStack {
                HapticButton(action: navigateBack) {
                    Image(systemName: step == .description ? "xmark" : "arrow.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
                #if DEBUG
                HapticButton("QA") { showAcceptanceRunner = true }
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(vm.isLoading)
                #endif
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppGray.bgPale.ignoresSafeArea(edges: .top))
    }

    private var navigationTitle: String {
        switch step {
        case .description: return L("New Estimate")
        case .questions: return L("Project Details")
        case .result: return L("Estimate Preview")
        }
    }

    private func navigateBack() {
        switch step {
        case .description:
            dismiss()
        case .questions:
            withAnimation(.easeInOut(duration: 0.2)) { step = .description }
        case .result:
            withAnimation(.easeInOut(duration: 0.2)) { step = .questions }
        }
    }

    private var descriptionStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Project Description"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppGray.ink)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $projectDescription)
                                .font(.system(size: 16))
                                .foregroundColor(AppGray.ink)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 180)
                                .padding(10)

                            if projectDescription.isEmpty {
                                Text(L("Describe the project, including the work needed, measurements, materials, site conditions, and any other details you already know."))
                                    .font(.system(size: 16))
                                    .foregroundColor(AppGray.muted)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Attach Photo"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppGray.ink)

                        HStack(spacing: 12) {
                            attachmentButton(title: L("Add photo"), icon: "photo") {
                                showPhotoPicker = true
                            }
                            attachmentButton(title: L("Take photo"), icon: "camera") {
                                requestCamera()
                            }
                        }
                    }

                    if let pendingImageData,
                       let image = UIImage(data: pendingImageData) {
                        HStack(spacing: 12) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            Text(L("Photo attached"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppGray.ink)
                            Spacer()
                            HapticButton {
                                self.pendingImageData = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppGray.borderStrong)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    }

                    if consentStore.status == .denied {
                        HapticButton("Enable AI Features") {
                            showAIConsentPrompt = true
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                    }

                    errorMessage
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomButton(
                title: vm.isLoading ? L("Preparing questions…") : L("Next"),
                enabled: !trimmedDescription.isEmpty && !vm.isLoading,
                action: beginEstimate
            )
        }
    }

    private var questionsStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(L("A few project details"))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(AppGray.ink)
                        Text(L("Answer the details needed for this job. You can edit the finished estimate before saving it."))
                            .font(.system(size: 15))
                            .foregroundColor(AppGray.secondary)
                    }

                    if let prompt = activeScreeningPrompt {
                        ForEach(prompt.questions) { question in
                            ScreeningQuestionField(
                                question: question,
                                selectedOptionIDs: selectionBinding(for: question.id),
                                textAnswer: textBinding(for: question.id)
                            )
                        }
                    }

                    errorMessage
                }
                .padding(20)
            }

            bottomButton(
                title: vm.isLoading ? L("Generating estimate…") : L("Generate Estimate"),
                enabled: allQuestionsAnswered && !vm.isLoading,
                action: generateEstimate
            )
        }
    }

    private var resultStep: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                if let estimate = resultEstimate {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(L("Review your estimate"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppGray.ink)
                            Text(L("Check the scope, quantities, pricing, and terms before saving."))
                                .font(.system(size: 15))
                                .foregroundColor(AppGray.secondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            if let note = estimate.sanityCheckNote, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 14, weight: .medium))
                            }
                            Text(L("Tax not included. Location-based tax calculation is not configured yet."))
                                .font(.system(size: 14))
                            if let exclusions = estimate.exclusions, !exclusions.isEmpty {
                                Text(L("Scope and exclusions"))
                                    .font(.system(size: 14, weight: .semibold))
                                ForEach(Array(exclusions.enumerated()), id: \.offset) { _, exclusion in
                                    Text(exclusion)
                                        .font(.system(size: 14))
                                }
                            }
                        }
                        .foregroundColor(AppGray.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppGray.border, lineWidth: 0.5))

                        ItemizedEstimateCard(
                            estimate: estimate,
                            rows: $estimateRows,
                            onTapEstimate: {},
                            onNewEstimate: {},
                            onViewChat: {}
                        )

                        errorMessage
                    }
                    .padding(20)
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)

            VStack(spacing: 10) {
                if let total = reviewTotalText {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(L("Total before tax"))
                            .font(.system(size: 16, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(total)
                            .font(.system(size: 20, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundColor(AppGray.ink)
                    .padding(.vertical, 14)
                    .accessibilityElement(children: .combine)
                }

                HapticButton {
                    if resultSupabaseID == nil {
                        vm.errorMessage = L("The estimate draft is still loading. Please try again.")
                    } else {
                        showAIEditor = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles.2")
                            .font(.system(size: 15, weight: .semibold))
                        Text(L("Edit with AI"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(AppGray.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                HapticButton(action: saveEstimate) {
                    Text(L("Save Estimate"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppGray.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(resultPayload == nil)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(Color.white)
        }
    }

    @ViewBuilder
    private var errorMessage: some View {
        if let error = vm.errorMessage {
            Text(L(error))
                .font(.system(size: 13))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func templateButton(_ title: String) -> some View {
        HapticButton {
            projectDescription = L(title)
        } label: {
            Text(L(title))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppGray.secondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .frame(height: 46)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func attachmentButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        HapticButton(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(AppGray.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func bottomButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        HapticButton(action: action) {
            HStack(spacing: 8) {
                if vm.isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(L(title))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(enabled ? AppGray.ink : AppGray.borderStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    private func beginEstimate() {
        guard !trimmedDescription.isEmpty else { return }
        guard consentStore.isGranted else {
            showAIConsentPrompt = true
            return
        }

        // The description screen supplies a complete job, including after Back.
        // Refinements belong in Edit with AI; do not append this job to an old draft.
        vm.newChat()
        activeScreeningPrompt = nil
        resultEstimate = nil
        resultPayload = nil
        resultSupabaseID = nil
        selections = [:]
        textAnswers = [:]
        vm.inputText = trimmedDescription
        if let imageData = pendingImageData {
            vm.sendWithPhoto(caption: trimmedDescription, imageData: imageData)
            pendingImageData = nil
        } else {
            vm.send()
        }
    }

    private func generateEstimate() {
        guard let prompt = activeScreeningPrompt, allQuestionsAnswered else { return }
        let answers = prompt.questions.map { question in
            ScreeningAnswer(
                questionID: question.id,
                question: question.question,
                values: answerValues(for: question),
                optionID: question.options.isEmpty ? nil : selections[question.id]?.first
            )
        }
        vm.submitScreening(prompt, answers: answers)
    }

    private func answerValues(for question: ScreeningQuestionDTO) -> [String] {
        if question.options.isEmpty {
            let value = textAnswers[question.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? [] : [value]
        }
        let selected = selections[question.id, default: []]
        return question.options.filter { selected.contains($0.id) }.map(\.label)
    }

    private func selectionBinding(for questionID: String) -> Binding<Set<String>> {
        Binding(
            get: { selections[questionID, default: []] },
            set: { selections[questionID] = $0 }
        )
    }

    private func textBinding(for questionID: String) -> Binding<String> {
        Binding(
            get: { textAnswers[questionID, default: ""] },
            set: { textAnswers[questionID] = $0 }
        )
    }

    private func showResult(
        estimate: Estimate,
        payload: [String: Any],
        supabaseID: String?
    ) {
        resultEstimate = estimate
        resultPayload = payload
        resultSupabaseID = supabaseID
        estimateRows = nil
        withAnimation(.easeInOut(duration: 0.2)) { step = .result }
        Task { await loadEstimateRows(estimateID: supabaseID) }
    }

    private func applyEditedEstimate(_ payload: [String: Any], _ supabaseID: String?) {
        let estimateNumber = resultEstimate?.estimateNumber ?? "EST-DRAFT"
        guard let estimate = Estimate.from(
            dict: payload,
            chatSessionId: vm.activeSessionId,
            estimateNumber: estimateNumber,
            supabaseEstimateId: supabaseID
        ) else { return }
        showResult(estimate: estimate, payload: payload, supabaseID: supabaseID)
    }

    /// Uses the save payload so the pinned total follows manual and AI edits.
    private var reviewTotalText: String? {
        guard let estimate = resultEstimate else { return nil }
        guard let payload = resultPayload,
              let total = payloadApplyingCurrentRows(to: payload)["total"] as? Double else {
            return estimate.formattedTotal
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: total)) ?? estimate.formattedTotal
    }

    private func saveEstimate() {
        guard let payload = resultPayload else { return }
        onEstimateConfirmed(payloadApplyingCurrentRows(to: payload), resultSupabaseID)
        vm.pendingEstimate = nil
        vm.pendingEstimateModel = nil
        vm.pendingEstimateMessageId = nil
        dismiss()
    }

    private func loadEstimateRows(estimateID: String?) async {
        guard let estimateID else {
            estimateRows = nil
            return
        }
        do {
            let rows: [EstimateItemRow] = try await supabase
                .from("estimate_items")
                .select()
                .eq("estimate_id", value: estimateID)
                .execute()
                .value
            estimateRows = rows
        } catch {
            // The generated in-memory estimate remains fully reviewable.
            estimateRows = nil
        }
    }

    private func payloadApplyingCurrentRows(to original: [String: Any]) -> [String: Any] {
        guard let estimate = resultEstimate,
              let rows = estimateRows else { return original }

        var categoryOrder: [String] = []
        for row in rows {
            let category = row.category ?? "Other"
            if !categoryOrder.contains(category) { categoryOrder.append(category) }
        }
        let categories: [[String: Any]] = categoryOrder.map { category in
            let categoryRows = rows.filter { ($0.category ?? "Other") == category }
            let items: [[String: Any]] = categoryRows.map { row in
                var item: [String: Any] = [
                    "name": row.name,
                    "quantity": row.quantity,
                    "unitLabel": row.unit_label ?? "EA",
                    "unitPrice": row.unit_price,
                    "total": row.total,
                    "onHand": row.on_hand
                ]
                if let source = row.source { item["source"] = source }
                if let url = row.url { item["url"] = url }
                if let description = row.description { item["description"] = description }
                return item
            }
            return [
                "name": category,
                "items": items,
                "subtotal": categoryRows.reduce(0) { $0 + $1.total }
            ]
        }
        let subtotal = rows.reduce(0) { $0 + $1.total }
        let markupAmount = (subtotal * estimate.markupPercent / 100 * 100).rounded() / 100
        let contingencyPercent = estimate.contingency?.percent ?? 0
        let contingencyAmount = (subtotal * contingencyPercent / 100 * 100).rounded() / 100
        let total = (subtotal + markupAmount + contingencyAmount) * 100

        var payload = original
        payload["categories"] = categories
        payload["subtotal"] = subtotal
        payload["markupAmount"] = markupAmount
        payload["contingencyPercent"] = contingencyPercent
        payload["contingencyAmount"] = contingencyAmount
        payload["total"] = total.rounded() / 100
        return payload
    }

    private func requestCamera() {
        Task {
            if await AppPermissions.request(.camera) {
                showCameraPicker = true
            } else {
                deniedPermission = .camera
            }
        }
    }
}

private struct EstimateAIEditSheet: View {
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Edit with AI"))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(AppGray.ink)
                            Text(L("Describe exactly what should change. Everything else in the estimate will stay the same."))
                                .font(.system(size: 15))
                                .foregroundColor(AppGray.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $instruction)
                                .font(.system(size: 16))
                                .foregroundColor(AppGray.ink)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 150)
                                .padding(10)

                            if instruction.isEmpty {
                                Text(L("For example: add two hours of labor, remove the disposal fee, or change the faucet quantity to two."))
                                    .font(.system(size: 16))
                                    .foregroundColor(AppGray.borderStrong)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(AppGray.border, lineWidth: 1)
                        )

                        if let errorMessage {
                            Text(L(errorMessage))
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.red.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)

                HapticButton(action: submit) {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                        Text(isSubmitting ? L("Updating estimate…") : L("Update Estimate"))
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSubmit ? AppGray.ink : AppGray.borderStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSubmit)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(L("Edit with AI"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HapticButton("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private var canSubmit: Bool {
        !trimmedInstruction.isEmpty && !isSubmitting
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        let request = trimmedInstruction
        Task {
            do {
                try await onSubmit(request)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Address Input Sheet

private struct AddressInputSheet: View {
    @Binding var address: String
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Estimate Address"))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                HapticButton("Done") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    address = trimmed
                    UserDefaults.standard.set(trimmed, forKey: "saved_address")
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(brandBlue)
            }

            HStack(spacing: 10) {
                Image("location pin")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundColor(.black)
                    .frame(width: 20, height: 20)
                TextField(L("Enter address or location"), text: $draft)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        address = trimmed
                        UserDefaults.standard.set(trimmed, forKey: "saved_address")
                        dismiss()
                    }
            }
            .padding(14)
            .background(AppGray.bgFaint)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(24)
        .onAppear {
            draft = address
            focused = true
        }
    }
}

// MARK: - Sidebar

struct ChatSidebarView: View {
    let vm: ChatViewModel

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            chatList
        }
        .background(Color(UIColor.systemBackground))
        .ignoresSafeArea(edges: .vertical)
    }

    private var sidebarHeader: some View {
        VStack(spacing: 16) {
            HStack {
                Text(L("Chats"))
                    .font(.system(size: 26, weight: .bold))
                Spacer()
            }

            HapticButton(action: { vm.newChat() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text(L("New Chat"))
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    AppBrand.accent
                )
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 64)
        .padding(.bottom, 20)
    }

    private var chatList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(vm.sessions) { session in
                    ChatSessionRow(
                        session: session,
                        isActive: session.id == vm.activeSessionId,
                        onTap: { vm.switchSession(session.id) },
                        onClear: { vm.clearActiveChat() },
                        onDelete: { vm.deleteSession(session.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Session Row

private struct ChatSessionRow: View {
    let session: ChatSession
    let isActive: Bool
    let onTap: () -> Void
    let onClear: () -> Void
    let onDelete: () -> Void

    @State private var showActions = false

    var body: some View {
        HapticButton(action: onTap) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 15, weight: isActive ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(session.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                }

                Spacer()

                HapticButton(action: { showActions = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(AppGray.borderStrong)
                        .rotationEffect(.degrees(90))
                        .frame(width: 32, height: 32)
                }
                .confirmationDialog(L("Chat Options"), isPresented: $showActions) {
                    if isActive {
                        HapticButton("Clear Messages", role: .destructive) { onClear() }
                    }
                    HapticButton("Delete Chat", role: .destructive) { onDelete() }
                    HapticButton("Cancel", role: .cancel) {}
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .background(Color(UIColor.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Product Link Card (embedded inside expanded estimate section)

private struct ProductLinkCard: View {
    let productName: String
    let quantity: String
    let price: String
    let store: String

    private var storeImageName: String {
        let s = store.lowercased()
        if s.contains("home depot") || s.contains("homedepot") { return "home depot" }
        if s.contains("lowe") { return "lowes" }
        return ""
    }

    var body: some View {
        HStack(spacing: 12) {
            if !storeImageName.isEmpty {
                Image(storeImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(productName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppGray.secondary)
                    .lineLimit(1)
                if !quantity.isEmpty {
                    Text(quantity)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.muted)
                }
            }
            Spacer()
            Text(price)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppGray.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Estimate Section Parser

private struct EstimateSection {
    let header: String        // e.g. "Materials", "Labor"
    let bodyLines: [String]   // lines between header and subtotal/next section
    let subtotalLine: String? // e.g. "Subtotal: $1,500"
}

private func parseEstimateSections(from text: String) -> (title: String, sections: [EstimateSection], footer: String)? {
    let rawLines = text.components(separatedBy: "\n")
    let lines = rawLines.map { line -> String in
        var l = line
        while l.hasPrefix("#") { l = String(l.dropFirst()) }
        if l.hasPrefix(" ") { l = String(l.dropFirst()) }
        return l
    }

    // Known section headers
    let sectionHeaders = ["materials", "labor", "overhead & markup", "overhead", "markup"]

    func isSectionHeader(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "").lowercased()
        return sectionHeaders.contains(where: { stripped.hasPrefix($0) })
    }

    func isRecommendedQuote(_ line: String) -> Bool {
        let stripped = line.lowercased().replacingOccurrences(of: "*", with: "")
        return stripped.contains("recommended quote")
    }

    // Find title (first non-empty line)
    var titleLine = ""
    var titleEndIdx = 0
    for (i, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            titleLine = trimmed
            titleEndIdx = i + 1
            break
        }
    }

    // Parse sections
    var sections: [EstimateSection] = []
    var currentHeader = ""
    var currentBody: [String] = []
    var currentSubtotal: String? = nil
    var footerStart = lines.count

    for i in titleEndIdx..<lines.count {
        let line = lines[i]
        let stripped = line.trimmingCharacters(in: .whitespaces)

        if isRecommendedQuote(line) {
            // Save current section
            if !currentHeader.isEmpty {
                sections.append(EstimateSection(header: currentHeader, bodyLines: currentBody, subtotalLine: currentSubtotal))
            }
            footerStart = i
            break
        }

        if isSectionHeader(line) {
            // Save previous section
            if !currentHeader.isEmpty {
                sections.append(EstimateSection(header: currentHeader, bodyLines: currentBody, subtotalLine: currentSubtotal))
            }
            currentHeader = stripped.replacingOccurrences(of: "*", with: "")
            currentBody = []
            currentSubtotal = nil
            continue
        }

        if !currentHeader.isEmpty {
            let lower = stripped.lowercased().replacingOccurrences(of: "*", with: "")
            if lower.hasPrefix("subtotal") || lower.hasPrefix("amount") {
                currentSubtotal = stripped
            } else if !stripped.isEmpty {
                currentBody.append(stripped)
            }
        }
    }
    // Save last section
    if !currentHeader.isEmpty {
        sections.append(EstimateSection(header: currentHeader, bodyLines: currentBody, subtotalLine: currentSubtotal))
    }

    let footer = lines[footerStart...].joined(separator: "\n")
    guard !sections.isEmpty else { return nil }
    return (title: titleLine, sections: sections, footer: footer)
}

// MARK: - Product line parser

private struct ParsedProduct {
    let name: String
    let quantity: String
    let price: String
    let store: String
}

/// Extracts product references like:
/// "- Product Name (24 x $120.45 from Home Depot): $2,890.78"
/// or "- Product Name (24 units x $120.45 from Lowe's): $2,890.78"
private func parseProducts(from text: String) -> [ParsedProduct] {
    var results: [ParsedProduct] = []
    let lines = text.components(separatedBy: "\n")

    // Pattern: captures product name, qty info, and store, with total price
    // Matches lines like: "- Product source oak cabinets (24 x $120.45/unit from Home Depot): $2,890.78"
    let pattern = #"-\s+(.+?)\s*\((\d+[\w\s]*)\s*x\s*\$[\d,.]+(?:/\w+)?\s+from\s+([^)]+)\):\s*\$([\d,.]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return results }

    for line in lines {
        let range = NSRange(line.startIndex..., in: line)
        if let match = regex.firstMatch(in: line, range: range) {
            let name = String(line[Range(match.range(at: 1), in: line)!]).trimmingCharacters(in: .whitespaces)
            let qty = String(line[Range(match.range(at: 2), in: line)!]).trimmingCharacters(in: .whitespaces)
            let store = String(line[Range(match.range(at: 3), in: line)!]).trimmingCharacters(in: .whitespaces)
            let total = String(line[Range(match.range(at: 4), in: line)!])
            results.append(ParsedProduct(name: name, quantity: qty, price: "$\(total)", store: store))
        }
    }

    // Fallback: simpler pattern "from Home Depot" or "from Lowe's" with a $ amount nearby
    if results.isEmpty {
        let simplePattern = #"-\s+(.+?)\s*\(.*?from\s+(Home Depot|Lowe'?s)[^)]*\).*?\$([\d,.]+)"#
        guard let simpleRegex = try? NSRegularExpression(pattern: simplePattern, options: .caseInsensitive) else { return results }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = simpleRegex.firstMatch(in: line, range: range) {
                let name = String(line[Range(match.range(at: 1), in: line)!]).trimmingCharacters(in: .whitespaces)
                let store = String(line[Range(match.range(at: 2), in: line)!])
                let price = String(line[Range(match.range(at: 3), in: line)!])
                results.append(ParsedProduct(name: name, quantity: "", price: "$\(price)", store: store))
            }
        }
    }

    return results
}

// MARK: - Bubble

private struct BubbleView: View {
    let message: ChatMessage
    var address: String = ""
    var structuredEstimate: Estimate? = nil
    var showConfirmButtons: Bool = false
    var screeningActive: Bool = false
    var onFinishScreening: (() -> Void)? = nil
    var onConfirm: (() -> Void)? = nil

    private let brandBlue = AppBrand.accent
    private let aiBubble = AppGray.bgSubtle
    private var isUser: Bool { message.role == "user" }

    private var isEstimateMessage: Bool {
        guard !isUser else { return false }
        let lower = message.content.lowercased().replacingOccurrences(of: "*", with: "")
        return lower.contains("recommended quote") || lower.contains("total range")
    }

    private var parsedSections: (title: String, sections: [EstimateSection], footer: String)? {
        guard isEstimateMessage else { return nil }
        return parseEstimateSections(from: message.content)
    }

    private func renderMarkdown(_ text: String) -> AttributedString {
        let lines = text.components(separatedBy: "\n")
        let processed = lines.map { line -> String in
            var l = line
            while l.hasPrefix("#") { l = String(l.dropFirst()) }
            if l.hasPrefix(" ") { l = String(l.dropFirst()) }
            return l
        }.joined(separator: "\n")
        if var attributed = try? AttributedString(
            markdown: processed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            for run in attributed.runs {
                if let intent = run.inlinePresentationIntent,
                   intent.contains(.stronglyEmphasized) {
                    attributed[run.range].font = .system(size: 18, weight: .bold)
                }
            }
            return attributed
        }
        return AttributedString(processed)
    }

    private var renderedContent: AttributedString {
        renderMarkdown(message.content)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            if message.attachmentKind == "screening_prompt" {
                // ---- Reopen-screening prompt (assistant bubble + Finish button) ----
                ScreeningPromptBubble(
                    content: message.content,
                    showButton: screeningActive,
                    onFinish: onFinishScreening
                )
            } else if let est = structuredEstimate {
                // ---- Structured estimate card (driven by server JSON — preferred path) ----
                ChatEstimateCard(
                    estimate: est,
                    address: address,
                    showConfirmButtons: showConfirmButtons,
                    onConfirm: onConfirm
                )
            } else if let parsed = parsedSections {
                // ---- Fallback: parse from text (if structured JSON missing) ----
                EstimateCardView(
                    parsed: parsed,
                    messageContent: message.content,
                    address: address,
                    showConfirmButtons: showConfirmButtons,
                    onConfirm: onConfirm
                )
            } else if isUser {
                // ---- User chat bubble ----
                VStack(alignment: .trailing, spacing: 6) {
                    // Photo/video thumbnail
                    if (message.attachmentKind == "photo" || message.attachmentKind == "video"),
                       let jpegData = message.thumbnailJpeg,
                       let uiImg = UIImage(data: jpegData) {
                        Image(uiImage: uiImg)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    if message.attachmentKind == "audio" || message.attachmentKind == "video" {
                        HStack(spacing: 8) {
                            Image(systemName: message.attachmentKind == "video" ? "video.fill" : "waveform")
                                .font(.system(size: 13, weight: .medium))
                            Text(message.content)
                                .font(.system(size: 16))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(brandBlue)
                        .clipShape(.rect(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 10, topTrailingRadius: 18))
                    } else if message.attachmentKind != "photo" || !message.content.isEmpty {
                        // Regular text (skip if it's just the photo placeholder "📷 Photo")
                        let showText = message.attachmentKind == nil ||
                                      (message.attachmentKind == "photo" && !message.content.hasPrefix("📷"))
                        if showText {
                            Text(renderedContent)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(brandBlue)
                                .clipShape(.rect(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 10, topTrailingRadius: 18))
                        }
                    }
                }
            } else {
                // ---- Assistant chat bubble (structured) ----
                AssistantBubbleView(
                    content: message.content,
                    renderedContent: renderedContent,
                    showConfirmButtons: showConfirmButtons,
                    onConfirm: onConfirm
                )
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Screening Prompt Bubble (reopen the questions)

private struct ScreeningPromptBubble: View {
    let content: String
    var showButton: Bool = true
    var onFinish: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content)
                .font(.system(size: 16))
                .foregroundColor(Color(UIColor.label))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(AppGray.bgSubtle)
                .clipShape(.rect(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: 10,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 18
                ))

            if showButton {
                HapticButton(action: { onFinish?() }) {
                    Text(L("Finish estimate"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .background(
                            AppBrand.accent
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Assistant Bubble View

private struct AssistantBubbleView: View {
    let content: String
    let renderedContent: AttributedString
    var showConfirmButtons: Bool = false
    var onConfirm: (() -> Void)? = nil

    private let brandBlue = AppBrand.accent

    /// A bullet line under a numbered item — e.g. "- Product: Quikrete 80 lb..." or "- URL: [text](url)"
    fileprivate struct ResearchBullet: Identifiable {
        let id = UUID()
        let key: String?
        let value: String
        let linkText: String?
        let url: String?
    }

    /// A numbered item, optionally with sub-bullets parsed from following "- " lines.
    fileprivate struct ResearchItem: Identifiable {
        let id = UUID()
        let number: Int
        let title: String
        let bullets: [ResearchBullet]
    }

    /// Free-floating key-value lines (not under a numbered item)
    fileprivate struct KeyValueItem: Identifiable {
        let id = UUID()
        let key: String
        let value: String
    }

    private static let numberedRegex = try? NSRegularExpression(pattern: #"^\s*(\d+)[.)]\s+(.+)"#)
    private static let bulletRegex = try? NSRegularExpression(pattern: #"^\s*[-•]\s+(.+)"#)
    private static let kvRegex = try? NSRegularExpression(pattern: #"^(.+?):\s+(.+)$"#)
    private static let mdLinkRegex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#)

    /// Detects schema-style keys the model leaks from the system prompt
    /// (e.g. "MATERIALS_ON_HAND", "TRADE_TYPE", "site_access"). These should always
    /// be promoted to numbered items rather than rendered as key/value rows.
    private static func isSchemaKey(_ key: String) -> Bool {
        guard !key.isEmpty, key.count <= 40, !key.contains(" ") else { return false }
        // Contains an underscore, and is all-caps or all-lowercase letters/digits/underscores
        guard key.contains("_") else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
            && (key == key.uppercased() || key == key.lowercased())
    }

    /// Converts a raw key like "MATERIALS_ON_HAND" or "material_quality" into "Materials On Hand" / "Material Quality"
    private static func humanizeKey(_ raw: String) -> String {
        let parts = raw
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
        return parts.map { word -> String in
            let lower = word.lowercased()
            guard let first = lower.first else { return "" }
            return String(first).uppercased() + String(lower.dropFirst())
        }.joined(separator: " ")
    }

    private static func parseBullet(_ raw: String) -> ResearchBullet {
        var s = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Extract markdown link [text](url) if present
        var linkText: String? = nil
        var url: String? = nil
        if let r = mdLinkRegex,
           let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           m.numberOfRanges == 3,
           let lr = Range(m.range(at: 1), in: s),
           let ur = Range(m.range(at: 2), in: s),
           let fullR = Range(m.range(at: 0), in: s) {
            linkText = String(s[lr])
            url = String(s[ur])
            s.replaceSubrange(fullR, with: linkText ?? "")
            s = s.trimmingCharacters(in: .whitespaces)
        }

        // Try key: value
        if let kvr = kvRegex,
           let km = kvr.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           km.numberOfRanges == 3,
           let kr = Range(km.range(at: 1), in: s),
           let vr = Range(km.range(at: 2), in: s) {
            let key = String(s[kr]).trimmingCharacters(in: .whitespaces)
            let value = String(s[vr]).trimmingCharacters(in: .whitespaces)
            if key.count <= 24 {
                return ResearchBullet(key: key, value: value, linkText: linkText, url: url)
            }
        }

        return ResearchBullet(key: nil, value: s, linkText: linkText, url: url)
    }

    private var parsedContent: (intro: String, items: [ResearchItem], keyValues: [KeyValueItem], outro: String) {
        let lines = content.components(separatedBy: "\n")
        var introLines: [String] = []
        var outroLines: [String] = []
        var topLevelKVs: [KeyValueItem] = []
        var items: [ResearchItem] = []

        var curNum: Int? = nil
        var curTitle: String = ""
        var curBullets: [ResearchBullet] = []
        var seenAnyItem = false
        var lastNumberSeen = 0
        var inListContext = false  // true while we're still inside a numbered list (no blank-line break yet)

        func closeCurrent() {
            if let n = curNum {
                items.append(ResearchItem(number: n, title: curTitle, bullets: curBullets))
                curNum = nil
                curTitle = ""
                curBullets = []
            }
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                inListContext = false
                continue
            }

            // Numbered item?
            if let r = Self.numberedRegex,
               let m = r.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               m.numberOfRanges == 3,
               let numR = Range(m.range(at: 1), in: line),
               let textR = Range(m.range(at: 2), in: line),
               let num = Int(line[numR]) {
                closeCurrent()
                curNum = num
                lastNumberSeen = max(lastNumberSeen, num)
                curTitle = String(line[textR])
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                curBullets = []
                seenAnyItem = true
                inListContext = true
                continue
            }

            // Bullet under current item?
            if curNum != nil,
               let br = Self.bulletRegex,
               let bm = br.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               bm.numberOfRanges == 2,
               let bodyR = Range(bm.range(at: 1), in: line) {
                curBullets.append(Self.parseBullet(String(line[bodyR])))
                inListContext = true
                continue
            }

            // Strip leading ### / # for heading lines
            var cleaned = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
            while cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            if cleaned.isEmpty { continue }

            if !seenAnyItem {
                introLines.append(cleaned)
            } else {
                // Look for "KEY: value" shape
                if let kvr = Self.kvRegex,
                   let km = kvr.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
                   km.numberOfRanges == 3,
                   let kr = Range(km.range(at: 1), in: cleaned),
                   let vr = Range(km.range(at: 2), in: cleaned) {
                    let key = String(cleaned[kr]).trimmingCharacters(in: .whitespaces)
                    let value = String(cleaned[vr]).trimmingCharacters(in: .whitespaces)

                    // Promote to a numbered item if either:
                    //  (a) we're still inside an active numbered list, OR
                    //  (b) the key looks like a schema/field identifier (UPPER_SNAKE_CASE etc.)
                    //      — e.g. MATERIALS_ON_HAND, MATERIAL_QUALITY, TRADE_TYPE
                    let looksLikeFieldId = Self.isSchemaKey(key)
                    if (inListContext || looksLikeFieldId), key.count < 40 {
                        closeCurrent()
                        lastNumberSeen += 1
                        let prettyKey = Self.humanizeKey(key)
                        items.append(ResearchItem(
                            number: lastNumberSeen,
                            title: "\(prettyKey): \(value)",
                            bullets: []
                        ))
                        inListContext = true
                        continue
                    }

                    // Otherwise treat as a free-floating key/value row
                    closeCurrent()
                    inListContext = false
                    if key.count < 30 {
                        topLevelKVs.append(KeyValueItem(key: key, value: value))
                        continue
                    }
                }

                closeCurrent()
                inListContext = false
                outroLines.append(cleaned)
            }
        }
        closeCurrent()

        return (
            intro: introLines.joined(separator: "\n"),
            items: items,
            keyValues: topLevelKVs,
            outro: outroLines.joined(separator: "\n")
        )
    }

    private var hasStructuredContent: Bool {
        !parsedContent.items.isEmpty
    }

    var body: some View {
        if hasStructuredContent {
            structuredBubble
        } else {
            plainBubble
        }
    }

    private var plainBubble: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(renderedContent)
                .font(.system(size: 16))
                .foregroundColor(AppGray.textDark)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)

            if showConfirmButtons { confirmButtons }
        }
        .background(AppGray.bgSubtle)
        .clipShape(
            .rect(
                topLeadingRadius: 18,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 18,
                topTrailingRadius: 18
            )
        )
    }

    private var structuredBubble: some View {
        let parsed = parsedContent

        return VStack(alignment: .leading, spacing: 0) {
            // Intro text
            if !parsed.intro.isEmpty {
                Text(parsed.intro)
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.textDark)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
            }

            // Research items (numbered title + sub-bullets + URL buttons)
            ForEach(Array(parsed.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, 60)
                }
                ResearchItemView(item: item)
            }

            // Key-value rows
            if !parsed.keyValues.isEmpty {
                Divider()
                    .padding(.horizontal, 24)

                ForEach(parsed.keyValues) { kv in
                    HStack {
                        Text(kv.key)
                            .font(.system(size: 14))
                            .foregroundColor(AppGray.secondary)
                        Spacer()
                        Text(kv.value)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                }
            }

            // Outro text
            if !parsed.outro.isEmpty {
                Divider()
                    .padding(.horizontal, 24)
                Text(parsed.outro)
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.textDark)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
            }

            if showConfirmButtons { confirmButtons }
        }
        .background(AppGray.bgSubtle)
        .clipShape(
            .rect(
                topLeadingRadius: 18,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 18,
                topTrailingRadius: 18
            )
        )
    }

    private var confirmButtons: some View {
        HStack(spacing: 10) {
            HapticButton(action: { onConfirm?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                    Text(L("Confirm Estimate"))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black)
                .clipShape(Capsule())
            }
            .buttonStyle(PlainButtonStyle())

            HapticButton(action: {}) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppGray.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color.clear)
                    .overlay(
                        Circle()
                            .strokeBorder(AppGray.borderStrong, lineWidth: 1.5)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 19)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }
}

// MARK: - Research Item View (numbered title + bullets + URL link button)

private struct ResearchItemView: View {
    let item: AssistantBubbleView.ResearchItem

    private var storeImageName: String {
        let lookup = item.bullets.first(where: { ($0.key ?? "").lowercased().contains("source") })?.value.lowercased() ?? ""
        if lookup.contains("home depot") || lookup.contains("homedepot") { return "home depot" }
        if lookup.contains("lowe") { return "lowes" }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(item.number)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
                    .frame(width: 26, height: 26)
                    .background(AppGray.bgSubtle)
                    .clipShape(Circle())

                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            if !item.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.bullets) { bullet in
                        bulletRow(bullet)
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func bulletRow(_ bullet: AssistantBubbleView.ResearchBullet) -> some View {
        let isUrlKey = (bullet.key ?? "").lowercased().contains("url") || (bullet.key ?? "").lowercased().contains("link")

        if let urlStr = bullet.url, let url = URL(string: urlStr), isUrlKey {
            Link(destination: url) {
                HStack(spacing: 8) {
                    if !storeImageName.isEmpty {
                        Image(storeImageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppGray.secondary)
                    }
                    Text(bullet.linkText ?? L("View product"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppBrand.accent)
                        .lineLimit(1)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(AppBrand.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                )
            }
        } else if let key = bullet.key {
            HStack(alignment: .top, spacing: 8) {
                Text("\(key):")
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
                Text(bullet.value)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppGray.textDark)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } else {
            Text(bullet.value)
                .font(.system(size: 13))
                .foregroundColor(AppGray.textDark)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Chat Estimate Card (driven by structured JSON)

private struct ChatEstimateCard: View {
    let estimate: Estimate
    var address: String = ""
    var showConfirmButtons: Bool = false
    var onConfirm: (() -> Void)? = nil

    @State private var expanded: Set<UUID> = []

    private let darkText = AppGray.ink
    private let navyDark = Color(red: 0.110, green: 0.169, blue: 0.227)

    private func formatted(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formattedQty(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func isMaterials(_ cat: EstimateCategory) -> Bool {
        cat.name.lowercased().contains("material")
    }

    private func pctText(_ v: Double) -> String {
        v == v.rounded() ? "\(Int(v))%" : String(format: "%.1f%%", v)
    }

    @ViewBuilder private func breakdownRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(L(label))
                .font(.system(size: 14))
                .foregroundColor(AppGray.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppGray.itemText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Estimate"))
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)
                Text(estimate.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(darkText)
                    .padding(.top, -6)

                HStack(spacing: 8) {
                    if !address.isEmpty {
                        AddressTagPill(text: address)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "circle")
                            .font(.system(size: 12))
                            .foregroundColor(AppGray.secondary)
                        Text(L(estimate.status))
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppGray.bgSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            ForEach(estimate.categories) { category in
                let isExpanded = expanded.contains(category.id)
                let materials = isMaterials(category)

                HapticButton(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        if isExpanded { expanded.remove(category.id) }
                        else { expanded.insert(category.id) }
                    }
                }) {
                    HStack {
                        Text(category.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppGray.itemText)
                        Spacer()
                        Text(formatted(category.subtotal))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppGray.itemText)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppGray.borderStrong)
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(Array(category.items.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { Divider() }
                            ChatEstimateItemRow(
                                item: item,
                                showProductCard: materials,
                                qtyFormatted: formattedQty(item.quantity),
                                priceFormatted: formatted(item.unitPrice),
                                totalFormatted: formatted(item.total)
                            )
                        }
                    }
                    .background(AppGray.bgPale)
                }

                Divider()
            }

            // Pricing breakdown
            VStack(spacing: 10) {
                breakdownRow(L("Subtotal"), formatted(estimate.subtotal))
                breakdownRow(L("Markup (%@)", "\(pctText(estimate.markupPercent))"), formatted(estimate.markupAmount))
                if let c = estimate.contingency, c.amount > 0 {
                    breakdownRow(L("Contingency (%@)", "\(pctText(c.percent))"), formatted(c.amount))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            RecommendedQuoteRow(total: estimate.formattedTotal)
            Divider()

            if showConfirmButtons {
                HapticButton(action: { onConfirm?() }) {
                    Text(L("Confirm Estimate"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppBrand.accent)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 22)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

private struct ChatEstimateItemRow: View {
    let item: EstimateLineItem
    let showProductCard: Bool
    let qtyFormatted: String
    let priceFormatted: String
    let totalFormatted: String
    var onSave: ((EstimateLineItem) -> Void)? = nil

    @State private var showEdit = false

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppGray.textDark)
                    Text("\(qtyFormatted) \(item.unitLabel) × \(priceFormatted)")
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.muted)
                }
                Spacer()
                Text(item.onHand ? L("On Hand") : totalFormatted)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.textDark)
            }

            if showProductCard {
                HapticButton(action: { showEdit = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(brandBlue)
                        Text(L("Edit"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(brandBlue)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sheet(isPresented: $showEdit) {
            MaterialEditSheet(item: item, onSave: { updated in
                onSave?(updated)
                showEdit = false
            })
        }
    }
}

// MARK: - Material Edit Sheet (edit a line item: name, qty, price, description)
struct MaterialEditSheet: View {
    var title: String = "Edit Item"
    let item: EstimateLineItem
    var onSave: (EstimateLineItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var quantity: String
    @State private var unitPrice: String
    @State private var descriptionText: String

    private let brandBlue = AppBrand.accent

    init(
        title: String = "Edit Item",
        item: EstimateLineItem,
        onSave: @escaping (EstimateLineItem) -> Void
    ) {
        self.title = title
        self.item = item
        self.onSave = onSave
        _name = State(initialValue: item.name)
        _quantity = State(initialValue: String(item.quantity))
        _unitPrice = State(initialValue: title == "Add Item" && item.unitPrice == 0 ? "" : String(item.unitPrice))
        _descriptionText = State(initialValue: item.description ?? "")
    }

    private var liveTotal: Double {
        (Double(quantity) ?? 0) * (Double(unitPrice) ?? 0)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Double(quantity) ?? 0) > 0 &&
        ((unitPrice.isEmpty && title == "Add Item") || (Double(unitPrice) ?? -1) >= 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    card(L("Product")) {
                        TextField(L("Name"), text: $name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                    }
                    card(L("Quantity")) {
                        TextField("0", text: $quantity)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                    }
                    card(L("Unit price")) {
                        HStack(spacing: 4) {
                            Text("$").foregroundColor(AppGray.secondary)
                            TextField("0.0", text: $unitPrice)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                    }
                    HStack {
                        Text(L("Line total"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", liveTotal))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppGray.textDark)
                    }
                    .padding(.horizontal, 4)
                    card(L("Description")) {
                        TextField(L("Optional notes"), text: $descriptionText, axis: .vertical)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                            .lineLimit(2...5)
                    }
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(L(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HapticButton("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HapticButton("Save") {
                        var updated = item
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.quantity = Double(quantity) ?? item.quantity
                        updated.unitPrice = Double(unitPrice) ?? item.unitPrice
                        updated.total = liveTotal
                        updated.description = descriptionText.isEmpty ? nil : descriptionText
                        onSave(updated)
                    }
                    .foregroundColor(brandBlue)
                    .disabled(!canSave)
                }
            }
        }
    }

    // Card matching the screening form: titled section + white rounded
    // field with a stroke border.
    @ViewBuilder
    private func card<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L(title))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppGray.textDark)
            content()
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                )
        }
    }
}

// MARK: - Estimate Card View

private struct EstimateCardView: View {
    let parsed: (title: String, sections: [EstimateSection], footer: String)
    let messageContent: String
    var address: String = ""
    var showConfirmButtons: Bool = false
    var onConfirm: (() -> Void)? = nil

    @State private var expandedSections: Set<Int> = []

    private let brandBlue = AppBrand.accent
    private let navyDark  = Color(red: 0.110, green: 0.169, blue: 0.227)
    private let darkText  = AppGray.ink

    private var products: [ParsedProduct] { parseProducts(from: messageContent) }

    private func cleanBodyLines(for section: EstimateSection) -> [String] {
        let linkPattern = #"\[([^\]]+)\]\([^)]+\)"#
        let linkRegex = try? NSRegularExpression(pattern: linkPattern)
        return section.bodyLines
            .map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line -> String? in
                var s = line.hasPrefix("-") ? String(line.dropFirst()).trimmingCharacters(in: .whitespaces) : line
                if let regex = linkRegex {
                    s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
                }
                if let r = s.range(of: "https://", options: .caseInsensitive) { s = String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
                if let r = s.range(of: "URL:", options: .caseInsensitive) { s = String(s[s.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
                return s.isEmpty ? nil : s
            }
    }

    // Deduplicate sections by header
    private var uniqueSections: [EstimateSection] {
        var seen = Set<String>()
        return parsed.sections.filter { seen.insert($0.header.lowercased()).inserted }
    }

    // Strip " — Estimate" suffixes and markdown asterisks the AI appends
    private var cleanTitle: String {
        var t = parsed.title
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "*", with: "")
        for suffix in [" \u{2014} Estimate", " - Estimate", " \u{2013} Estimate", "\u{2014} Estimate"] {
            if t.hasSuffix(suffix) { t = String(t.dropLast(suffix.count)); break }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private var footerLines: [String] {
        parsed.footer
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var totalPrice: String {
        for line in footerLines {
            let lower = line.lowercased()
            if lower.contains("recommended quote") || lower.contains("total") {
                if let p = extractDollarAmount(from: line) { return p }
            }
        }
        return ""
    }

    private var assumptionsText: String {
        footerLines
            .filter { line in
                let lower = line.lowercased()
                return !lower.hasPrefix("recommended") && !lower.contains("total range") && !lower.hasPrefix("total")
            }
            .map { line in
                var s = line
                    .replacingOccurrences(of: "**", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("- ") { s = String(s.dropFirst(2)) }
                if s.hasPrefix("• ") { s = String(s.dropFirst(2)) }
                return s
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func extractDollarAmount(from line: String) -> String? {
        let s = line.replacingOccurrences(of: "*", with: "")
        guard let idx = s.firstIndex(of: "$") else { return nil }
        return String(s[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func subtotalPrice(for section: EstimateSection) -> String? {
        guard let sub = section.subtotalLine else { return nil }
        return extractDollarAmount(from: sub)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Estimate"))
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)
                Text(L(cleanTitle))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(darkText)
                    .padding(.top, -6)

                // Pills row
                HStack(spacing: 8) {
                    if !address.isEmpty {
                        AddressTagPill(text: address)
                    }
                    TagPill(icon: "circle", text: L("Draft"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // ── Line item rows ───────────────────────────────────
            ForEach(Array(uniqueSections.enumerated()), id: \.offset) { index, section in
                let isExpanded = expandedSections.contains(index)
                let isMaterials = section.header.lowercased().contains("material")
                let sectionProducts = isMaterials ? products : []

                // Tappable header row with chevron
                HapticButton(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if isExpanded { expandedSections.remove(index) }
                        else { expandedSections.insert(index) }
                    }
                }) {
                    HStack {
                        Text(section.header)
                            .font(.system(size: 14))
                            .foregroundColor(AppGray.secondary)
                        Spacer()
                        if let price = subtotalPrice(for: section) {
                            Text(price)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(darkText)
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppGray.borderStrong)
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .buttonStyle(PlainButtonStyle())

                // Expanded dropdown content
                if isExpanded {
                    Divider()
                    VStack(spacing: 0) {
                        if !sectionProducts.isEmpty {
                            ForEach(Array(sectionProducts.enumerated()), id: \.offset) { idx, product in
                                if idx > 0 { Divider().padding(.leading, 20) }
                                ProductLinkCard(
                                    productName: product.name,
                                    quantity: product.quantity,
                                    price: product.price,
                                    store: product.store
                                )
                            }
                        } else {
                            let lines = cleanBodyLines(for: section)
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                if idx > 0 { Divider().padding(.leading, 20) }
                                Text(L(line))
                                    .font(.system(size: 14))
                                    .foregroundColor(AppGray.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                    .background(AppGray.bgPale)
                    .transition(.opacity)
                }

                Divider()
            }

            // ── Total row ────────────────────────────────────────
            HStack(alignment: .center) {
                Text(L("Recommended Quote"))
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)
                Spacer()
                Text(totalPrice)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(darkText)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)

            // ── Assumptions ──────────────────────────────────────
            if !assumptionsText.isEmpty {
                Text(assumptionsText)
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.itemText)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, showConfirmButtons ? 10 : 26)
            }

            // ── Confirm button ───────────────────────────────────
            if showConfirmButtons {
                HapticButton(action: { onConfirm?() }) {
                    Text(L("Confirm Estimate"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppBrand.accent)
                        .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.top, assumptionsText.isEmpty ? 18 : 8)
                .padding(.bottom, 16)
            } else if assumptionsText.isEmpty {
                Spacer().frame(height: 22)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundColor(AppGray.borderStrong)
                        .offset(y: animating ? -4 : 0)
                        .animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppGray.bgSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 60)
        }
        .onAppear { animating = true }
    }
}

// (Confirm button is now embedded inside BubbleView for estimate messages)

#Preview {
    ChatView()
}


/// The API does not report fractional completion. Ease toward 95% while waiting;
/// only a successful estimate response can complete the ring.
private struct EstimateGenerationProgressView: View {
    let isComplete: Bool
    @State private var progress = 0

    var body: some View {
        VStack(spacing: 28) {
            EstimatorProgressRing(progress: progress, foreground: AppGray.ink)
                .frame(width: 156, height: 156)
            VStack(spacing: 10) {
                Text(isComplete ? L("Your estimate is ready") : L("Creating your estimate"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppGray.ink)
                Text(isComplete ? L("Opening your estimate…") : L("Estimated progress · This may take a moment"))
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .task(id: isComplete) {
            if isComplete {
                progress = 100
                return
            }
            progress = 0
            let start = ContinuousClock.now
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) }
                catch { return }
                let elapsed = start.duration(to: .now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                progress = min(95, Int(96 * (1 - exp(-seconds / 22))))
            }
        }
    }
}
