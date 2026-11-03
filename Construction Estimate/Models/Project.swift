//
//  Project.swift
//  Construction Estimate
//
//

import Foundation
import Observation

struct Project: Identifiable, Codable {
    let id: UUID
    let organizationId: UUID?
    let clientId: UUID?
    let propertyId: UUID?
    let projectNumber: String
    let title: String
    let price: Double
    let status: String
    let clientName: String?
    let clientPhone: String?
    let clientEmail: String?
    let address: String?
    let assignee: String?
    let estimateChatSessionId: UUID?
    let estimate: Estimate?

    init(
        id: UUID = UUID(),
        organizationId: UUID? = nil,
        clientId: UUID? = nil,
        propertyId: UUID? = nil,
        projectNumber: String,
        title: String,
        price: Double,
        status: String,
        clientName: String? = nil,
        clientPhone: String? = nil,
        clientEmail: String? = nil,
        address: String? = nil,
        assignee: String? = nil,
        estimateChatSessionId: UUID? = nil,
        estimate: Estimate? = nil
    ) {
        self.id = id
        self.organizationId = organizationId
        self.clientId = clientId
        self.propertyId = propertyId
        self.projectNumber = projectNumber
        self.title = title
        self.price = price
        self.status = status
        self.clientName = clientName
        self.clientPhone = clientPhone
        self.clientEmail = clientEmail
        self.address = address
        self.assignee = assignee
        self.estimateChatSessionId = estimateChatSessionId
        self.estimate = estimate
    }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: price)) ?? "$0.00"
    }

    var workflowStatus: String {
        guard let estimateStatus = estimate?.status.lowercased() else {
            return status
        }

        if ["accepted", "approved", "won"].contains(estimateStatus) {
            return "Approved"
        }
        if ["sent", "viewed", "delivered"].contains(estimateStatus) {
            return "Sent"
        }
        return status
    }
}

@Observable
@MainActor
final class ProjectStore {
    static let shared = ProjectStore()

    var projects: [Project] = []
    var isLoading = false
    var lastError: String?

    private init() {}

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await LegacyDataMigrator.shared.migrateIfNeeded()
            projects = try await ProjectRepository.load()
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "project refresh")
        }
    }

    func add(_ project: Project) {
        if !projects.contains(where: { $0.id == project.id }) {
            projects.insert(project, at: 0)
        }
        Task { await persist(project) }
    }

    func update(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
        Task { await persist(project) }
    }

    func delete(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        Task {
            do {
                try await ProjectRepository.delete(project.id)
                lastError = nil
            } catch {
                lastError = SafeErrorMessages.data(error, action: "project save")
                await refresh()
            }
        }
    }

    func persistAndWait(_ project: Project) async throws {
        try await ProjectRepository.upsert(project)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.insert(project, at: 0)
        }
    }

    func reset() {
        projects = []
        lastError = nil
        isLoading = false
    }

    private func persist(_ project: Project) async {
        do {
            try await persistAndWait(project)
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "project deletion")
        }
    }
}
