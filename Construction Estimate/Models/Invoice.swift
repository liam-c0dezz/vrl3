//
//  Invoice.swift
//  Construction Estimate
//

import Foundation
import UIKit

struct InvoiceLineItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var quantity: Double
    var unitPrice: Double
    var unit: String

    var total: Double { quantity * unitPrice }

    var formattedTotal: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: total)) ?? "$0.00"
    }
}

struct InvoicePaymentMethod: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var details: String
}

struct Invoice: Identifiable, Codable {
    var id = UUID()
    var organizationId: UUID? = nil
    var estimateId: UUID? = nil
    var invoiceNumber: String
    var title: String
    var description: String
    var items: [InvoiceLineItem]
    var discount: Double
    var taxPercent: Double
    var status: String  // "Draft", "Sent", "Paid"
    var dueDate: String // "On completion", "Net 15", "Net 30", "Custom"
    var clientId: UUID?
    var projectId: UUID?
    var createdAt: Date
    var coverTransactionFees: Bool
    var termsAndConditions: String
    var attachments: [String] // file names
    var renderId: UUID? = nil
    var includeRender: Bool = false
    var dueAt: Date? = nil
    var companyName: String = ""
    var paymentMethods: [InvoicePaymentMethod] = []
    var disclaimer: String = L("This invoice is an estimate and the final amount may vary based on actual work completed. All prices are subject to change. Payment is due upon receipt unless otherwise agreed.")

    var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    var discountAmount: Double { discount }
    var taxAmount: Double { (subtotal - discountAmount) * (taxPercent / 100) }
    var total: Double { subtotal - discountAmount + taxAmount }

    var formattedTotal: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: total)) ?? "$0.00"
    }

    var formattedSubtotal: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: subtotal)) ?? "$0.00"
    }

    /// Build an invoice from a confirmed estimate. Every estimate line item is
    /// copied at cost, then markup and contingency are appended as their own
    /// lines so the invoice total equals the quoted price the client agreed to.
    static func from(estimate: Estimate, projectId: UUID?, clientId: UUID?, number: Int) -> Invoice {
        let defaults = BusinessSettingsStore.shared.profile
        var items: [InvoiceLineItem] = estimate.categories.flatMap { category in
            category.items.map { item in
                InvoiceLineItem(
                    title: item.name,
                    quantity: item.quantity,
                    unitPrice: item.unitPrice,
                    unit: item.unitLabel
                )
            }
        }

        if estimate.markupAmount > 0 {
            items.append(InvoiceLineItem(
                title: L("Markup (%@%%)", "\(Int(estimate.markupPercent.rounded()))"),
                quantity: 1,
                unitPrice: estimate.markupAmount,
                unit: "EA"
            ))
        }

        if let contingency = estimate.contingency, contingency.amount > 0 {
            items.append(InvoiceLineItem(
                title: L("Contingency (%@%%)", "\(Int(contingency.percent.rounded()))"),
                quantity: 1,
                unitPrice: contingency.amount,
                unit: "EA"
            ))
        }

        return Invoice(
            estimateId: estimate.supabaseEstimateId.flatMap(UUID.init(uuidString:)),
            invoiceNumber: "INV-\(10000 + number)",
            title: estimate.title,
            description: "",
            items: items,
            discount: 0,
            taxPercent: defaults.salesTaxPercent,
            status: "Draft",
            dueDate: defaults.paymentTerms,
            clientId: clientId,
            projectId: projectId,
            createdAt: Date(),
            coverTransactionFees: false,
            termsAndConditions: estimate.paymentTerms ?? defaults.paymentTerms,
            attachments: [],
            dueAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            companyName: defaults.businessName
        )
    }

    static func createNew(number: Int) -> Invoice {
        let defaults = BusinessSettingsStore.shared.profile
        return Invoice(
            invoiceNumber: "INV-\(10000 + number)",
            title: "",
            description: "",
            items: [],
            discount: 0,
            taxPercent: defaults.salesTaxPercent,
            status: "Draft",
            dueDate: defaults.paymentTerms,
            clientId: nil,
            projectId: nil,
            createdAt: Date(),
            coverTransactionFees: false,
            termsAndConditions: defaults.paymentTerms,
            attachments: [],
            dueAt: Calendar.current.date(byAdding: .day, value: 30, to: Date()),
            companyName: defaults.businessName
        )
    }
}

extension Invoice {
    private enum CodingKeys: String, CodingKey {
        case id, organizationId, estimateId, invoiceNumber, title, description
        case items, discount, taxPercent, status, dueDate, clientId, projectId
        case createdAt, coverTransactionFees, termsAndConditions, attachments
        case renderId, includeRender, dueAt, companyName, paymentMethods, disclaimer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        organizationId = try container.decodeIfPresent(UUID.self, forKey: .organizationId)
        estimateId = try container.decodeIfPresent(UUID.self, forKey: .estimateId)
        invoiceNumber = try container.decode(String.self, forKey: .invoiceNumber)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        items = try container.decode([InvoiceLineItem].self, forKey: .items)
        discount = try container.decode(Double.self, forKey: .discount)
        taxPercent = try container.decode(Double.self, forKey: .taxPercent)
        status = try container.decode(String.self, forKey: .status)
        dueDate = try container.decode(String.self, forKey: .dueDate)
        clientId = try container.decodeIfPresent(UUID.self, forKey: .clientId)
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        coverTransactionFees = try container.decode(Bool.self, forKey: .coverTransactionFees)
        termsAndConditions = try container.decode(String.self, forKey: .termsAndConditions)
        attachments = try container.decodeIfPresent([String].self, forKey: .attachments) ?? []
        renderId = try container.decodeIfPresent(UUID.self, forKey: .renderId)
        includeRender = try container.decodeIfPresent(Bool.self, forKey: .includeRender) ?? false
        dueAt = try container.decodeIfPresent(Date.self, forKey: .dueAt)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        paymentMethods = try container.decodeIfPresent([InvoicePaymentMethod].self, forKey: .paymentMethods) ?? []
        disclaimer = try container.decodeIfPresent(String.self, forKey: .disclaimer)
            ?? L("This invoice is an estimate and the final amount may vary based on actual work completed. All prices are subject to change. Payment is due upon receipt unless otherwise agreed.")
    }
}

struct Payment: Identifiable, Codable, Equatable {
    var id = UUID()
    var organizationId: UUID? = nil
    var projectId: UUID
    var invoiceId: UUID? = nil
    var amount: Double
    var method: String
    var receivedAt: Date = Date()
    var createdAt: Date = Date()
}

@Observable
@MainActor
final class PaymentStore {
    static let shared = PaymentStore()

    var payments: [Payment] = []
    var isLoading = false
    var lastError: String?

    private init() {}

    func payments(for projectId: UUID) -> [Payment] {
        payments
            .filter { $0.projectId == projectId }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    func total(for projectId: UUID) -> Double {
        payments(for: projectId).reduce(0) { $0 + $1.amount }
    }

    func save(_ payment: Payment) async throws {
        try await PaymentRepository.upsert(payment)
        if let index = payments.firstIndex(where: { $0.id == payment.id }) {
            payments[index] = payment
        } else {
            payments.insert(payment, at: 0)
        }
        lastError = nil
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            payments = try await PaymentRepository.load()
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "payment refresh")
        }
    }

    func reset() {
        payments = []
        isLoading = false
        lastError = nil
    }
}

@Observable
@MainActor
final class InvoiceStore {
    static let shared = InvoiceStore()

    var invoices: [Invoice] = []
    var isLoading = false
    var lastError: String?
    private var persistenceTasks: [UUID: Task<Void, Never>] = [:]
    private var persistenceRevisions: [UUID: Int] = [:]
    private var unsyncedInvoiceIDs: Set<UUID> = []
    private var mutationVersion = 0

    private init() {}

    func add(_ invoice: Invoice) {
        invoices.insert(invoice, at: 0)
        mutationVersion += 1
        enqueuePersistence(for: invoice)
    }

    func update(_ invoice: Invoice) {
        if let idx = invoices.firstIndex(where: { $0.id == invoice.id }) {
            invoices[idx] = invoice
        } else {
            invoices.insert(invoice, at: 0)
        }
        mutationVersion += 1
        enqueuePersistence(for: invoice)
    }

    func delete(_ id: UUID) {
        invoices.removeAll { $0.id == id }
        unsyncedInvoiceIDs.remove(id)
        mutationVersion += 1
        let previousTask = persistenceTasks[id]
        persistenceTasks[id] = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            do {
                try await InvoiceRepository.delete(id)
                self?.persistenceRevisions[id] = nil
                self?.lastError = nil
            } catch {
                self?.lastError = SafeErrorMessages.data(error, action: "invoice deletion")
                await self?.refresh()
            }
        }
    }

    func invoices(for projectId: UUID) -> [Invoice] {
        invoices.filter { $0.projectId == projectId }
    }

    func invoices(forStatus status: String) -> [Invoice] {
        invoices.filter { $0.status == status }
    }

    var nextNumber: Int {
        invoices.count + 1
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await LegacyDataMigrator.shared.migrateIfNeeded()

            // A screen refresh can happen while a Draft or Sent update is
            // still being saved. Never let an older server snapshot erase
            // that optimistic local change. Wait for queued writes, then
            // retry the load if another mutation arrived during the request.
            for _ in 0..<3 {
                await waitForPendingPersistence()
                let versionAtLoadStart = mutationVersion
                let loadedInvoices = try await InvoiceRepository.load()
                guard versionAtLoadStart == mutationVersion else { continue }

                let unsyncedInvoices = invoices.filter { unsyncedInvoiceIDs.contains($0.id) }
                let unsyncedIDs = Set(unsyncedInvoices.map(\.id))
                invoices = unsyncedInvoices + loadedInvoices.filter { !unsyncedIDs.contains($0.id) }
                if unsyncedInvoices.isEmpty {
                    lastError = nil
                }
                return
            }

            // Local state is newer than every snapshot we fetched. Keeping it
            // is safer than making a newly created invoice disappear.
        } catch {
            lastError = SafeErrorMessages.data(error, action: "invoice refresh")
        }
    }

    private func persist(_ invoice: Invoice, revision: Int) async {
        do {
            try await InvoiceRepository.upsert(invoice)
            if persistenceRevisions[invoice.id] == revision {
                unsyncedInvoiceIDs.remove(invoice.id)
                lastError = nil
            }
        } catch {
            lastError = SafeErrorMessages.data(error, action: "invoice save")
        }
    }

    /// Invoice edits can be saved several times in quick succession (for
    /// example, once before previewing and again after a successful send).
    /// Preserve that order so an older Draft write can never finish after a
    /// newer Sent or Paid write and roll the invoice status backward.
    private func enqueuePersistence(for invoice: Invoice) {
        let revision = (persistenceRevisions[invoice.id] ?? 0) + 1
        persistenceRevisions[invoice.id] = revision
        unsyncedInvoiceIDs.insert(invoice.id)
        let previousTask = persistenceTasks[invoice.id]
        persistenceTasks[invoice.id] = Task { [weak self] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await self?.persist(invoice, revision: revision)
        }
    }

    private func waitForPendingPersistence() async {
        let tasks = Array(persistenceTasks.values)
        for task in tasks {
            await task.value
        }
    }

    func reset() {
        persistenceTasks.values.forEach { $0.cancel() }
        persistenceTasks = [:]
        persistenceRevisions = [:]
        unsyncedInvoiceIDs = []
        invoices = []
        lastError = nil
        isLoading = false
        mutationVersion = 0
    }

}

/// Business-wide branding shared across every invoice (and the future PDF).
/// A contractor has one logo, so it's stored once rather than per invoice.
@Observable
final class BusinessProfile {
    static let shared = BusinessProfile()

    @ObservationIgnored private let logoKey = "business_logo_png"

    var logoData: Data?

    private init() {
        logoData = UserDefaults.standard.data(forKey: logoKey)
    }

    var logoImage: UIImage? {
        guard let logoData else { return nil }
        return UIImage(data: logoData)
    }

    func setLogo(_ image: UIImage?) {
        if let image, let data = image.pngData() {
            logoData = data
            UserDefaults.standard.set(data, forKey: logoKey)
        } else {
            logoData = nil
            UserDefaults.standard.removeObject(forKey: logoKey)
        }
    }
}
