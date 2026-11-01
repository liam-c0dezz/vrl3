//
//  ClientStore.swift
//  Construction Estimate
//

import SwiftUI
import Observation

struct Client: Identifiable, Codable {
    var id: UUID = UUID()
    var organizationId: UUID? = nil
    var name: String
    var company: String
    var email: String
    var phone: String
    var address: String
    var referralSource: String

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

@Observable
@MainActor
final class ClientStore {
    static let shared = ClientStore()

    var clients: [Client] = []
    var isLoading = false
    var lastError: String?

    private init() {}

    func add(_ client: Client) {
        clients.insert(client, at: 0)
        Task {
            do {
                try await ClientRepository.upsert(client)
                lastError = nil
            } catch {
                lastError = SafeErrorMessages.data(error, action: "client save")
            }
        }
    }

    func update(_ client: Client) {
        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            clients[index] = client
        } else {
            clients.insert(client, at: 0)
        }
        Task {
            do {
                try await ClientRepository.upsert(client)
                lastError = nil
            } catch {
                lastError = SafeErrorMessages.data(error, action: "client update")
            }
        }
    }

    func delete(_ id: UUID) {
        clients.removeAll { $0.id == id }
        Task {
            do {
                try await ClientRepository.delete(id)
                lastError = nil
            } catch {
                lastError = SafeErrorMessages.data(error, action: "client deletion")
                await refresh()
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await LegacyDataMigrator.shared.migrateIfNeeded()
            clients = try await ClientRepository.load()
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "client refresh")
        }
    }

    func reset() {
        clients = []
        lastError = nil
        isLoading = false
    }

}
