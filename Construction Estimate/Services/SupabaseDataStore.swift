import Foundation
import Supabase

enum SupabaseDataError: LocalizedError {
    case noOrganization
    case invoiceRequiresProject
    case projectNotSaved

    var errorDescription: String? {
        switch self {
        case .noOrganization:
            return "No company workspace is available for this account."
        case .invoiceRequiresProject:
            return "An invoice must belong to a project before it can be saved."
        case .projectNotSaved:
            return "Save the project before adding project records."
        }
    }
}

private struct OrganizationMembershipRow: Decodable {
    let organization_id: UUID
}

enum WorkspaceContext {
    static func organizationID() async throws -> UUID {
        let session = try await supabase.auth.session
        let rows: [OrganizationMembershipRow] = try await supabase
            .from("organization_members")
            .select("organization_id")
            .eq("user_id", value: session.user.id.uuidString)
            .limit(1)
            .execute()
            .value

        guard let id = rows.first?.organization_id else {
            throw SupabaseDataError.noOrganization
        }
        return id
    }
}

private enum SupabaseDate {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard = ISO8601DateFormatter()

    static func parse(_ value: String?) -> Date {
        guard let value else { return Date() }
        return fractional.date(from: value) ?? standard.date(from: value) ?? Date()
    }
}

// MARK: - Clients

private struct ClientDatabaseRow: Decodable {
    let id: UUID
    let organization_id: UUID
    let name: String
    let company: String
    let email: String
    let phone: String
    let address: String
    let referral_source: String

    var model: Client {
        Client(
            id: id,
            organizationId: organization_id,
            name: name,
            company: company,
            email: email,
            phone: phone,
            address: address,
            referralSource: referral_source
        )
    }
}

private struct ClientPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let name: String
    let company: String
    let email: String
    let phone: String
    let address: String
    let referral_source: String

    init(client: Client, organizationID: UUID) {
        id = client.id
        organization_id = organizationID
        name = client.name
        company = client.company
        email = client.email
        phone = client.phone
        address = client.address
        referral_source = client.referralSource
    }
}

enum ClientRepository {
    static func load() async throws -> [Client] {
        let rows: [ClientDatabaseRow] = try await supabase
            .from("clients")
            .select()
            .order("updated_at", ascending: false)
            .execute()
            .value
        return rows.map(\.model)
    }

    static func upsert(_ client: Client) async throws {
        let organizationID: UUID
        if let existingID = client.organizationId {
            organizationID = existingID
        } else {
            organizationID = try await WorkspaceContext.organizationID()
        }
        try await supabase
            .from("clients")
            .upsert(ClientPayload(client: client, organizationID: organizationID))
            .execute()
    }

    static func delete(_ id: UUID) async throws {
        try await supabase
            .from("clients")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

// MARK: - Projects and estimates

private struct ProjectRow: Decodable {
    let id: UUID
    let organization_id: UUID
    let client_id: UUID?
    let property_id: UUID?
    let project_number: String
    let title: String
    let price: Double
    let status: String
    let address: String?
}

private struct ProjectPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let client_id: UUID?
    let property_id: UUID?
    let project_number: String
    let title: String
    let price: Double
    let status: String
    let address: String?

    init(project: Project, organizationID: UUID) {
        id = project.id
        organization_id = organizationID
        client_id = project.clientId
        property_id = project.propertyId
        project_number = project.projectNumber
        title = project.title
        price = project.price
        status = project.status
        address = project.address
    }
}

private struct PropertyPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let client_id: UUID?
    let label: String
    let address_line1: String
}

private struct RemoteEstimateRow: Decodable {
    let id: UUID
    let project_id: UUID?
    let estimate_number: String?
    let title: String?
    let subtotal: Double?
    let markup_pct: Double?
    let markup_amount: Double?
    let contingency_pct: Double?
    let contingency_amount: Double?
    let total: Double?
    let exclusions: [String]?
    let payment_terms: String?
    let sanity_check: String?
    let work_plan: [EstimatePlanSection]?
    let notes: String?
    let appearance: EstimateAppearance?
    let status: String?
    let created_at: String?
}

private struct RemoteEstimateItemRow: Decodable {
    let id: UUID
    let estimate_id: UUID
    let category: String?
    let name: String?
    let quantity: Double?
    let unit_label: String?
    let unit_price: Double?
    let total: Double?
    let source: String?
    let url: String?
    let description: String?
    let on_hand: Bool?
}

private struct EstimateProjectPatch: Encodable {
    let project_id: UUID
    let organization_id: UUID
}

enum ProjectRepository {
    static func loadEstimates(projectID: UUID) async throws -> [Estimate] {
        async let estimateRequest: [RemoteEstimateRow] = supabase
            .from("estimates")
            .select()
            .eq("project_id", value: projectID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value
        async let itemRequest: [RemoteEstimateItemRow] = supabase
            .from("estimate_items")
            .select()
            .eq("project_id", value: projectID.uuidString)
            .order("created_at", ascending: true)
            .execute()
            .value

        let (estimateRows, itemRows) = try await (estimateRequest, itemRequest)
        let itemsByEstimate = Dictionary(grouping: itemRows, by: \.estimate_id)
        return estimateRows.map { row in
            makeEstimate(row: row, items: itemsByEstimate[row.id] ?? [])
        }
    }

    static func deleteEstimate(_ estimateID: UUID) async throws {
        try await supabase
            .from("estimates")
            .delete()
            .eq("id", value: estimateID.uuidString)
            .execute()
    }

    static func load() async throws -> [Project] {
        async let projectRequest: [ProjectRow] = supabase
            .from("projects")
            .select()
            .order("updated_at", ascending: false)
            .execute()
            .value
        async let clientRequest: [ClientDatabaseRow] = supabase
            .from("clients")
            .select()
            .execute()
            .value
        async let estimateRequest: [RemoteEstimateRow] = supabase
            .from("estimates")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        async let itemRequest: [RemoteEstimateItemRow] = supabase
            .from("estimate_items")
            .select()
            .order("created_at", ascending: true)
            .execute()
            .value

        let (projectRows, clientRows, estimateRows, itemRows) = try await (
            projectRequest,
            clientRequest,
            estimateRequest,
            itemRequest
        )

        let clientsByID = Dictionary(uniqueKeysWithValues: clientRows.map { ($0.id, $0.model) })
        let itemsByEstimate = Dictionary(grouping: itemRows, by: \.estimate_id)
        var latestEstimateByProject: [UUID: Estimate] = [:]

        for row in estimateRows {
            guard let projectID = row.project_id, latestEstimateByProject[projectID] == nil else {
                continue
            }
            latestEstimateByProject[projectID] = makeEstimate(
                row: row,
                items: itemsByEstimate[row.id] ?? []
            )
        }

        return projectRows.map { row in
            let client = row.client_id.flatMap { clientsByID[$0] }
            let estimate = latestEstimateByProject[row.id]
            return Project(
                id: row.id,
                organizationId: row.organization_id,
                clientId: row.client_id,
                propertyId: row.property_id,
                projectNumber: row.project_number,
                title: row.title,
                price: estimate?.total ?? row.price,
                status: row.status,
                clientName: client?.name,
                clientPhone: client?.phone,
                clientEmail: client?.email,
                address: row.address,
                assignee: nil,
                estimateChatSessionId: estimate?.chatSessionId,
                estimate: estimate
            )
        }
    }

    static func upsert(_ project: Project) async throws {
        let organizationID: UUID
        if let existingID = project.organizationId {
            organizationID = existingID
        } else {
            organizationID = try await WorkspaceContext.organizationID()
        }
        try await supabase
            .from("projects")
            .upsert(ProjectPayload(project: project, organizationID: organizationID))
            .execute()
    }

    static func delete(_ id: UUID) async throws {
        try await supabase
            .from("projects")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    static func linkEstimate(
        estimateID: UUID,
        projectID: UUID,
        organizationID: UUID
    ) async throws {
        let patch = EstimateProjectPatch(
            project_id: projectID,
            organization_id: organizationID
        )
        try await supabase
            .from("estimates")
            .update(patch)
            .eq("id", value: estimateID.uuidString)
            .execute()
        try await supabase
            .from("estimate_items")
            .update(patch)
            .eq("estimate_id", value: estimateID.uuidString)
            .execute()
    }

    private static func makeEstimate(
        row: RemoteEstimateRow,
        items: [RemoteEstimateItemRow]
    ) -> Estimate {
        let grouped = Dictionary(grouping: items) { $0.category ?? "Other" }
        let categories = grouped.keys.sorted().map { categoryName in
            let categoryItems = (grouped[categoryName] ?? []).map { item in
                EstimateLineItem(
                    id: item.id,
                    name: item.name ?? "Item",
                    quantity: item.quantity ?? 0,
                    unitLabel: item.unit_label ?? "EA",
                    unitPrice: item.unit_price ?? 0,
                    total: item.total ?? 0,
                    source: item.source,
                    url: item.url,
                    description: item.description,
                    onHand: item.on_hand ?? false
                )
            }
            return EstimateCategory(
                name: categoryName,
                items: categoryItems,
                subtotal: categoryItems.reduce(0) { $0 + $1.total }
            )
        }

        let contingency: ContingencyInfo? = {
            let amount = row.contingency_amount ?? 0
            let percent = row.contingency_pct ?? 0
            guard amount > 0 || percent > 0 else { return nil }
            return ContingencyInfo(percent: percent, amount: amount, reason: nil)
        }()

        var estimate = Estimate(
            estimateNumber: row.estimate_number ?? "EST-\(row.id.uuidString.prefix(8).uppercased())",
            title: row.title ?? "Estimate",
            categories: categories,
            subtotal: row.subtotal ?? categories.reduce(0) { $0 + $1.subtotal },
            markupPercent: row.markup_pct ?? 0,
            markupAmount: row.markup_amount ?? 0,
            total: row.total ?? 0,
            status: row.status ?? "Draft",
            createdAt: SupabaseDate.parse(row.created_at),
            chatSessionId: row.id,
            siteConditions: nil,
            permitInfo: nil,
            contingency: contingency,
            toolRental: nil,
            wasteFactors: nil,
            exclusions: row.exclusions,
            paymentTerms: row.payment_terms,
            sanityCheckNote: row.sanity_check,
            crossReferenceNotes: nil,
            workPlan: row.work_plan,
            notes: row.notes,
            appearance: row.appearance
        )
        estimate.supabaseEstimateId = row.id.uuidString
        return estimate
    }
}

// MARK: - Estimate proposal details and media

private struct EstimateProposalPatch: Encodable {
    let work_plan: [EstimatePlanSection]
    let notes: String
}

private struct EstimatePlanGenerationRequest: Encodable {
    let request_id: UUID
    let operation: String
    let project_id: UUID
    let estimate_id: UUID
}

private struct EstimatePlanGenerationResponse: Decodable {
    let work_plan: [EstimatePlanSection]
    let estimate_id: UUID
}

struct EstimateMedia: Identifiable, Decodable, Equatable {
    let id: UUID
    let organizationId: UUID
    let projectId: UUID
    let estimateId: UUID
    let kind: String
    let displayName: String
    let storagePath: String?
    let renderId: UUID?
    let mimeType: String?
    let sortOrder: Int
    let createdAt: String

    var isRender: Bool { kind == "render" }
    var isPDF: Bool { mimeType == "application/pdf" }

    private enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case projectId = "project_id"
        case estimateId = "estimate_id"
        case kind
        case displayName = "display_name"
        case storagePath = "storage_path"
        case renderId = "render_id"
        case mimeType = "mime_type"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

private struct EstimateMediaPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let estimate_id: UUID
    let kind: String
    let display_name: String
    let storage_path: String?
    let render_id: UUID?
    let mime_type: String?
    let sort_order: Int
}

enum EstimateProposalRepository {
    static func generatePlan(
        projectID: UUID,
        estimateID: UUID
    ) async throws -> [EstimatePlanSection] {
        let response: EstimatePlanGenerationResponse = try await supabase.functions.invoke(
            "smart-service-v7",
            options: FunctionInvokeOptions(
                body: EstimatePlanGenerationRequest(
                    request_id: UUID(),
                    operation: "generate_plan",
                    project_id: projectID,
                    estimate_id: estimateID
                )
            )
        )
        guard response.estimate_id == estimateID, response.work_plan.count >= 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return response.work_plan
    }

    static func updateDetails(
        estimateID: UUID,
        workPlan: [EstimatePlanSection],
        notes: String
    ) async throws {
        try await supabase
            .from("estimates")
            .update(EstimateProposalPatch(work_plan: workPlan, notes: notes))
            .eq("id", value: estimateID.uuidString)
            .execute()
    }

    static func loadMedia(estimateID: UUID) async throws -> [EstimateMedia] {
        try await supabase
            .from("estimate_media")
            .select()
            .eq("estimate_id", value: estimateID.uuidString)
            .order("sort_order", ascending: true)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    static func uploadMedia(
        data: Data,
        mimeType: String,
        displayName: String,
        kind: String,
        projectID: UUID,
        estimateID: UUID,
        sortOrder: Int
    ) async throws {
        let organizationID = try await WorkspaceContext.organizationID()
        let ext: String = switch mimeType {
        case "application/pdf": "pdf"
        case "image/png": "png"
        default: "jpg"
        }
        let path = "\(organizationID.uuidString)/\(projectID.uuidString)/estimates/\(estimateID.uuidString)/\(UUID().uuidString).\(ext)"

        try await supabase.storage
            .from("project-files")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: false)
            )

        do {
            try await supabase
                .from("estimate_media")
                .insert(EstimateMediaPayload(
                    id: UUID(),
                    organization_id: organizationID,
                    project_id: projectID,
                    estimate_id: estimateID,
                    kind: kind,
                    display_name: displayName,
                    storage_path: path,
                    render_id: nil,
                    mime_type: mimeType,
                    sort_order: sortOrder
                ))
                .execute()
        } catch {
            try? await supabase.storage.from("project-files").remove(paths: [path])
            throw error
        }
    }

    static func attachRender(
        _ render: ProjectRender,
        estimateID: UUID,
        sortOrder: Int
    ) async throws {
        try await supabase
            .from("estimate_media")
            .insert(EstimateMediaPayload(
                id: UUID(),
                organization_id: render.organizationId,
                project_id: render.projectId,
                estimate_id: estimateID,
                kind: "render",
                display_name: "Project render",
                storage_path: nil,
                render_id: render.id,
                mime_type: "image/jpeg",
                sort_order: sortOrder
            ))
            .execute()
    }

    static func data(for media: EstimateMedia) async throws -> Data {
        if let path = media.storagePath {
            return try await supabase.storage.from("project-files").download(path: path)
        }
        guard let renderID = media.renderId else {
            throw SupabaseDataError.projectNotSaved
        }
        let renders: [ProjectRender] = try await supabase
            .from("project_renders")
            .select()
            .eq("id", value: renderID.uuidString)
            .limit(1)
            .execute()
            .value
        guard let render = renders.first else {
            throw SupabaseDataError.projectNotSaved
        }
        return try await ProjectRenderRepository.imageData(
            path: render.acceptedImagePath ?? render.currentImagePath
        )
    }

    static func delete(_ media: EstimateMedia) async throws {
        if let path = media.storagePath {
            try await supabase.storage.from("project-files").remove(paths: [path])
        }
        try await supabase
            .from("estimate_media")
            .delete()
            .eq("id", value: media.id.uuidString)
            .execute()
    }
}

// MARK: - Invoices

private struct InvoiceRow: Decodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let client_id: UUID?
    let estimate_id: UUID?
    let invoice_number: String
    let title: String
    let description: String
    let status: String
    let due_date: String
    let discount_amount: Double
    let tax_percent: Double
    let cover_transaction_fees: Bool
    let terms_and_conditions: String
    let render_id: UUID?
    let include_render: Bool?
    let created_at: String
    let due_at: String?
    let company_name: String?
    let payment_methods: [InvoicePaymentMethod]?
    let disclaimer: String?
    let attachments: [String]?
}

private struct InvoiceRenderPatch: Encodable {
    let render_id: UUID?
    let include_render: Bool
}

private struct InvoiceItemRow: Decodable {
    let id: UUID
    let invoice_id: UUID
    let title: String
    let quantity: Double
    let unit_price: Double
    let unit: String
    let sort_order: Int
}

private struct InvoicePayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let client_id: UUID?
    let estimate_id: UUID?
    let invoice_number: String
    let title: String
    let description: String
    let status: String
    let due_date: String
    let subtotal: Double
    let discount_amount: Double
    let tax_percent: Double
    let tax_amount: Double
    let total: Double
    let cover_transaction_fees: Bool
    let terms_and_conditions: String

    init(invoice: Invoice, organizationID: UUID, projectID: UUID) {
        id = invoice.id
        organization_id = organizationID
        project_id = projectID
        client_id = invoice.clientId
        estimate_id = invoice.estimateId
        invoice_number = invoice.invoiceNumber
        title = invoice.title
        description = invoice.description
        status = invoice.status
        due_date = invoice.dueDate
        subtotal = invoice.subtotal
        discount_amount = invoice.discountAmount
        tax_percent = invoice.taxPercent
        tax_amount = invoice.taxAmount
        total = invoice.total
        cover_transaction_fees = invoice.coverTransactionFees
        terms_and_conditions = invoice.termsAndConditions
    }
}

private struct InvoiceExtendedPayload: Encodable {
    let due_at: String?
    let company_name: String
    let payment_methods: [InvoicePaymentMethod]
    let disclaimer: String
    let attachments: [String]

    init(invoice: Invoice) {
        if let dueAt = invoice.dueAt {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            due_at = formatter.string(from: dueAt)
        } else {
            due_at = nil
        }
        company_name = invoice.companyName
        payment_methods = invoice.paymentMethods
        disclaimer = invoice.disclaimer
        attachments = invoice.attachments
    }
}

private struct InvoiceItemPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let invoice_id: UUID
    let title: String
    let quantity: Double
    let unit_price: Double
    let unit: String
    let sort_order: Int
}

private struct InvoiceUpsertRPCParameters: Encodable {
    let p_invoice: InvoicePayload
    let p_items: [InvoiceItemPayload]
}

private struct InvoiceProjectOrganizationRow: Decodable {
    let organization_id: UUID
}

enum InvoiceRepository {
    static func load() async throws -> [Invoice] {
        async let invoiceRequest: [InvoiceRow] = supabase
            .from("invoices")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        async let itemRequest: [InvoiceItemRow] = supabase
            .from("invoice_items")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value

        let (rows, itemRows) = try await (invoiceRequest, itemRequest)
        let itemsByInvoice = Dictionary(grouping: itemRows, by: \.invoice_id)

        return rows.map { row in
            let items = (itemsByInvoice[row.id] ?? []).map {
                InvoiceLineItem(
                    id: $0.id,
                    title: $0.title,
                    quantity: $0.quantity,
                    unitPrice: $0.unit_price,
                    unit: $0.unit
                )
            }
            return Invoice(
                id: row.id,
                organizationId: row.organization_id,
                estimateId: row.estimate_id,
                invoiceNumber: row.invoice_number,
                title: row.title,
                description: row.description,
                items: items,
                discount: row.discount_amount,
                taxPercent: row.tax_percent,
                status: row.status,
                dueDate: row.due_date,
                clientId: row.client_id,
                projectId: row.project_id,
                createdAt: SupabaseDate.parse(row.created_at),
                coverTransactionFees: row.cover_transaction_fees,
                termsAndConditions: row.terms_and_conditions,
                attachments: row.attachments ?? [],
                renderId: row.render_id,
                includeRender: row.include_render ?? false,
                dueAt: row.due_at.flatMap(invoiceDate),
                companyName: row.company_name ?? "",
                paymentMethods: row.payment_methods ?? [],
                disclaimer: row.disclaimer ?? "This invoice is an estimate and the final amount may vary based on actual work completed. All prices are subject to change. Payment is due upon receipt unless otherwise agreed."
            )
        }
    }

    static func upsert(_ invoice: Invoice) async throws {
        guard let projectID = invoice.projectId else {
            throw SupabaseDataError.invoiceRequiresProject
        }
        // The project is the source of truth for invoice ownership. Looking
        // its organization up directly avoids assigning a new invoice to the
        // wrong workspace when the signed-in user belongs to more than one.
        let projectOrganization: InvoiceProjectOrganizationRow = try await supabase
            .from("projects")
            .select("organization_id")
            .eq("id", value: projectID.uuidString)
            .single()
            .execute()
            .value
        let organizationID = projectOrganization.organization_id
        let invoicePayload = InvoicePayload(
            invoice: invoice,
            organizationID: organizationID,
            projectID: projectID
        )
        let itemPayloads = invoice.items.enumerated().map { index, item in
            InvoiceItemPayload(
                id: item.id,
                organization_id: organizationID,
                invoice_id: invoice.id,
                title: item.title,
                quantity: item.quantity,
                unit_price: item.unitPrice,
                unit: item.unit,
                sort_order: index
            )
        }

        try await supabase
            .rpc(
                "upsert_invoice_with_items",
                params: InvoiceUpsertRPCParameters(
                    p_invoice: invoicePayload,
                    p_items: itemPayloads
                )
            )
            .execute()

        try await supabase
            .from("invoices")
            .update(InvoiceExtendedPayload(invoice: invoice))
            .eq("id", value: invoice.id.uuidString)
            .execute()

        try await supabase
            .from("invoices")
            .update(InvoiceRenderPatch(
                render_id: invoice.renderId,
                include_render: invoice.renderId == nil ? false : invoice.includeRender
            ))
            .eq("id", value: invoice.id.uuidString)
            .execute()
    }

    static func delete(_ id: UUID) async throws {
        try await supabase
            .from("invoices")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    private static func invoiceDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

// MARK: - Payments

private struct PaymentRow: Decodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let invoice_id: UUID?
    let amount: Double
    let method: String
    let received_at: String
    let created_at: String
}

private struct PaymentPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let invoice_id: UUID?
    let amount: Double
    let method: String
    let received_at: String

    init(payment: Payment, organizationID: UUID) {
        id = payment.id
        organization_id = organizationID
        project_id = payment.projectId
        invoice_id = payment.invoiceId
        amount = payment.amount
        method = payment.method
        received_at = SupabaseDate.fractional.string(from: payment.receivedAt)
    }
}

enum PaymentRepository {
    static func load() async throws -> [Payment] {
        let rows: [PaymentRow] = try await supabase
            .from("payments")
            .select()
            .order("received_at", ascending: false)
            .execute()
            .value

        return rows.map { row in
            Payment(
                id: row.id,
                organizationId: row.organization_id,
                projectId: row.project_id,
                invoiceId: row.invoice_id,
                amount: row.amount,
                method: row.method,
                receivedAt: SupabaseDate.parse(row.received_at),
                createdAt: SupabaseDate.parse(row.created_at)
            )
        }
    }

    static func upsert(_ payment: Payment) async throws {
        let projectOrganization: InvoiceProjectOrganizationRow = try await supabase
            .from("projects")
            .select("organization_id")
            .eq("id", value: payment.projectId.uuidString)
            .single()
            .execute()
            .value

        try await supabase
            .from("payments")
            .upsert(
                PaymentPayload(
                    payment: payment,
                    organizationID: projectOrganization.organization_id
                ),
                onConflict: "id"
            )
            .execute()
    }
}

// MARK: - Documents

struct ProjectDocument: Identifiable, Decodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let invoice_id: UUID?
    let name: String
    let storage_path: String
    let mime_type: String?
    let size_bytes: Int?
    let category: String
    let created_at: String
}

private struct ProjectDocumentPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let project_id: UUID
    let invoice_id: UUID?
    let name: String
    let storage_path: String
    let mime_type: String?
    let size_bytes: Int
    let category: String
}

enum ProjectDocumentRepository {
    static func load(projectID: UUID) async throws -> [ProjectDocument] {
        try await supabase
            .from("project_documents")
            .select()
            .eq("project_id", value: projectID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    static func upload(
        fileURL: URL,
        projectID: UUID,
        invoiceID: UUID? = nil,
        category: String = "document"
    ) async throws {
        let organizationID = try await WorkspaceContext.organizationID()
        let secured = fileURL.startAccessingSecurityScopedResource()
        defer {
            if secured {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: fileURL)
        let safeName = fileURL.lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let path = "\(organizationID.uuidString)/\(projectID.uuidString)/\(UUID().uuidString)-\(safeName)"
        let mimeType = fileURL.mimeType

        try await supabase.storage
            .from("project-files")
            .upload(
                path,
                data: data,
                options: FileOptions(contentType: mimeType, upsert: false)
            )

        do {
            try await supabase
                .from("project_documents")
                .insert(ProjectDocumentPayload(
                    id: UUID(),
                    organization_id: organizationID,
                    project_id: projectID,
                    invoice_id: invoiceID,
                    name: fileURL.lastPathComponent,
                    storage_path: path,
                    mime_type: mimeType,
                    size_bytes: data.count,
                    category: category
                ))
                .execute()
        } catch {
            try? await supabase.storage.from("project-files").remove(paths: [path])
            throw error
        }
    }

    static func delete(_ document: ProjectDocument) async throws {
        try await supabase.storage
            .from("project-files")
            .remove(paths: [document.storage_path])
        try await supabase
            .from("project_documents")
            .delete()
            .eq("id", value: document.id.uuidString)
            .execute()
    }
}

private extension URL {
    var mimeType: String {
        switch pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - One-time on-device import

@MainActor
final class LegacyDataMigrator {
    static let shared = LegacyDataMigrator()

    private init() {}

    func migrateIfNeeded() async throws {
        let session = try await supabase.auth.session
        let migrationKey = "supabase_phase1_migrated_\(session.user.id.uuidString)"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let organizationID = try await WorkspaceContext.organizationID()
        let decoder = JSONDecoder()

        let localClients: [Client] = {
            guard let data = UserDefaults.standard.data(forKey: "saved_clients") else { return [] }
            return (try? decoder.decode([Client].self, from: data)) ?? []
        }()

        if !localClients.isEmpty {
            let payloads = localClients.map {
                ClientPayload(client: $0, organizationID: organizationID)
            }
            try await supabase.from("clients").upsert(payloads).execute()
        }

        let localProjects: [Project] = {
            guard let data = UserDefaults.standard.data(forKey: "saved_projects") else { return [] }
            return (try? decoder.decode([Project].self, from: data)) ?? []
        }()

        var clientKeys: [String: UUID] = [:]
        for client in localClients {
            for key in Self.keys(name: client.name, email: client.email, phone: client.phone) {
                clientKeys[key] = client.id
            }
        }

        for project in localProjects {
            var resolvedClientID = project.clientId
            if resolvedClientID == nil {
                for key in Self.keys(
                    name: project.clientName ?? "",
                    email: project.clientEmail ?? "",
                    phone: project.clientPhone ?? ""
                ) where resolvedClientID == nil {
                    resolvedClientID = clientKeys[key]
                }
            }

            if resolvedClientID == nil,
               let name = project.clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                let derivedClient = Client(
                    id: project.id,
                    organizationId: organizationID,
                    name: name,
                    company: "",
                    email: project.clientEmail ?? "",
                    phone: project.clientPhone ?? "",
                    address: project.address ?? "",
                    referralSource: ""
                )
                resolvedClientID = derivedClient.id
                try await supabase
                    .from("clients")
                    .upsert(ClientPayload(client: derivedClient, organizationID: organizationID))
                    .execute()
            }

            var propertyID = project.propertyId
            if let address = project.address?.trimmingCharacters(in: .whitespacesAndNewlines),
               !address.isEmpty {
                propertyID = propertyID ?? project.id
                try await supabase
                    .from("properties")
                    .upsert(PropertyPayload(
                        id: propertyID!,
                        organization_id: organizationID,
                        client_id: resolvedClientID,
                        label: project.title,
                        address_line1: address
                    ))
                    .execute()
            }

            let migratedProject = Project(
                id: project.id,
                organizationId: organizationID,
                clientId: resolvedClientID,
                propertyId: propertyID,
                projectNumber: project.projectNumber,
                title: project.title,
                price: project.price,
                status: project.status,
                clientName: project.clientName,
                clientPhone: project.clientPhone,
                clientEmail: project.clientEmail,
                address: project.address,
                assignee: project.assignee,
                estimateChatSessionId: project.estimateChatSessionId,
                estimate: project.estimate
            )
            try await supabase
                .from("projects")
                .upsert(ProjectPayload(project: migratedProject, organizationID: organizationID))
                .execute()

            if let estimateIDString = project.estimate?.supabaseEstimateId,
               let estimateID = UUID(uuidString: estimateIDString) {
                try await ProjectRepository.linkEstimate(
                    estimateID: estimateID,
                    projectID: project.id,
                    organizationID: organizationID
                )
            }
        }

        let localInvoices: [Invoice] = {
            guard let data = UserDefaults.standard.data(forKey: "saved_invoices") else { return [] }
            return (try? decoder.decode([Invoice].self, from: data)) ?? []
        }()
        let validProjectIDs = Set(localProjects.map(\.id))
        for invoice in localInvoices where invoice.projectId.map(validProjectIDs.contains) == true {
            var migratedInvoice = invoice
            migratedInvoice.organizationId = organizationID
            try await InvoiceRepository.upsert(migratedInvoice)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    private static func keys(name: String, email: String, phone: String) -> [String] {
        [
            email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            phone.filter(\.isNumber),
            name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].filter { !$0.isEmpty }
    }
}
