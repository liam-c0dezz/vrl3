import Observation
import PhotosUI
import Supabase
import SwiftUI
import UIKit

enum BusinessSetupDestination: String, Identifiable {
    case business
    case hourlyRates
    case upsells

    var id: String { rawValue }
}

struct BusinessProfileSettings: Equatable {
    var businessName = ""
    var licenseNumber = ""
    var website = ""
    var phone = ""
    var email = ""
    var postalCode = ""
    var defaultMarkupPercent = 20.0
    var salesTaxPercent = 0.0
    var paymentTerms = "Net 30"
    var quoteValidDays = 30
    var paymentLink = ""
    var logoStoragePath: String?
    var setupCompletedAt: String?

    var isSetupComplete: Bool { setupCompletedAt != nil }
}

struct BusinessHourlyRate: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hourlyRate: Double

    static let starterDefaults: [BusinessHourlyRate] = [
        BusinessHourlyRate(name: "General Contractor (GC)", hourlyRate: 90),
        BusinessHourlyRate(name: "Standard labor", hourlyRate: 50),
        BusinessHourlyRate(name: "Plumber", hourlyRate: 95),
        BusinessHourlyRate(name: "Electrician", hourlyRate: 100),
        BusinessHourlyRate(name: "HVAC Technician", hourlyRate: 110),
        BusinessHourlyRate(name: "Roofer", hourlyRate: 70),
        BusinessHourlyRate(name: "Painter", hourlyRate: 60),
        BusinessHourlyRate(name: "Tile Setter", hourlyRate: 70),
        BusinessHourlyRate(name: "Carpenter / Framing", hourlyRate: 90),
        BusinessHourlyRate(name: "Drywaller", hourlyRate: 58)
    ]
}

struct BusinessUpsell: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var description: String
    var price: Double
}

private struct BusinessProfileRow: Decodable {
    let business_name: String
    let license_number: String
    let website: String
    let phone: String
    let email: String
    let postal_code: String
    let default_markup_percent: Double
    let sales_tax_percent: Double
    let payment_terms: String
    let quote_valid_days: Int
    let payment_link: String
    let logo_storage_path: String?
    let setup_completed_at: String?

    var settings: BusinessProfileSettings {
        BusinessProfileSettings(
            businessName: business_name,
            licenseNumber: license_number,
            website: website,
            phone: phone,
            email: email,
            postalCode: postal_code,
            defaultMarkupPercent: default_markup_percent,
            salesTaxPercent: sales_tax_percent,
            paymentTerms: payment_terms,
            quoteValidDays: quote_valid_days,
            paymentLink: payment_link,
            logoStoragePath: logo_storage_path,
            setupCompletedAt: setup_completed_at
        )
    }
}

private struct BusinessProfilePayload: Encodable {
    let organization_id: UUID
    let business_name: String
    let license_number: String
    let website: String
    let phone: String
    let email: String
    let postal_code: String
    let default_markup_percent: Double
    let sales_tax_percent: Double
    let payment_terms: String
    let quote_valid_days: Int
    let payment_link: String
    let logo_storage_path: String?
    let setup_completed_at: String
}

private struct BusinessRateRow: Decodable {
    let id: UUID
    let name: String
    let hourly_rate: Double

    var model: BusinessHourlyRate {
        BusinessHourlyRate(id: id, name: name, hourlyRate: hourly_rate)
    }
}

private struct BusinessRatePayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let name: String
    let hourly_rate: Double
    let sort_order: Int
}

private struct BusinessUpsellRow: Decodable {
    let id: UUID
    let name: String
    let description: String
    let price: Double

    var model: BusinessUpsell {
        BusinessUpsell(id: id, name: name, description: description, price: price)
    }
}

private struct BusinessUpsellPayload: Encodable {
    let id: UUID
    let organization_id: UUID
    let name: String
    let description: String
    let price: Double
    let sort_order: Int
}

private enum BusinessSettingsRepository {
    static func loadProfile() async throws -> BusinessProfileSettings {
        let organizationID = try await WorkspaceContext.organizationID()
        let rows: [BusinessProfileRow] = try await supabase
            .from("business_profiles")
            .select()
            .eq("organization_id", value: organizationID.uuidString)
            .limit(1)
            .execute()
            .value

        if let row = rows.first {
            return row.settings
        }

        let session = try await supabase.auth.session
        var defaults = BusinessProfileSettings()
        defaults.email = session.user.email ?? ""
        return defaults
    }

    static func loadRates() async throws -> [BusinessHourlyRate] {
        let rows: [BusinessRateRow] = try await supabase
            .from("business_hourly_rates")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value
        return rows.map(\.model)
    }

    static func loadUpsells() async throws -> [BusinessUpsell] {
        let rows: [BusinessUpsellRow] = try await supabase
            .from("business_upsells")
            .select()
            .order("sort_order", ascending: true)
            .execute()
            .value
        return rows.map(\.model)
    }

    static func downloadLogo(path: String) async throws -> Data {
        try await supabase.storage
            .from("business-assets")
            .download(path: path)
    }

    static func saveProfile(
        _ settings: BusinessProfileSettings,
        logoData: Data?
    ) async throws -> BusinessProfileSettings {
        let organizationID = try await WorkspaceContext.organizationID()
        var logoPath = settings.logoStoragePath

        if let logoData {
            logoPath = "\(organizationID.uuidString.lowercased())/logo.jpg"
            try await supabase.storage
                .from("business-assets")
                .upload(
                    logoPath!,
                    data: logoData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        }

        let completionDate = settings.setupCompletedAt
            ?? ISO8601DateFormatter().string(from: Date())
        let payload = BusinessProfilePayload(
            organization_id: organizationID,
            business_name: settings.businessName.trimmed,
            license_number: settings.licenseNumber.trimmed,
            website: settings.website.trimmed,
            phone: settings.phone.trimmed,
            email: settings.email.trimmed,
            postal_code: settings.postalCode.trimmed,
            default_markup_percent: settings.defaultMarkupPercent,
            sales_tax_percent: settings.salesTaxPercent,
            payment_terms: settings.paymentTerms,
            quote_valid_days: settings.quoteValidDays,
            payment_link: settings.paymentLink.trimmed,
            logo_storage_path: logoPath,
            setup_completed_at: completionDate
        )

        try await supabase
            .from("business_profiles")
            .upsert(payload, onConflict: "organization_id")
            .execute()

        var saved = settings
        saved.businessName = payload.business_name
        saved.licenseNumber = payload.license_number
        saved.website = payload.website
        saved.phone = payload.phone
        saved.email = payload.email
        saved.postalCode = payload.postal_code
        saved.paymentLink = payload.payment_link
        saved.logoStoragePath = logoPath
        saved.setupCompletedAt = completionDate
        return saved
    }

    static func replaceRates(
        _ rates: [BusinessHourlyRate],
        deletedIDs: Set<UUID>
    ) async throws {
        let organizationID = try await WorkspaceContext.organizationID()
        if !rates.isEmpty {
            let payloads = rates.enumerated().map { index, rate in
                BusinessRatePayload(
                    id: rate.id,
                    organization_id: organizationID,
                    name: rate.name.trimmed,
                    hourly_rate: rate.hourlyRate,
                    sort_order: index
                )
            }
            try await supabase
                .from("business_hourly_rates")
                .upsert(payloads, onConflict: "id")
                .execute()
        }

        for id in deletedIDs {
            try await supabase
                .from("business_hourly_rates")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }

    static func replaceUpsells(
        _ upsells: [BusinessUpsell],
        deletedIDs: Set<UUID>
    ) async throws {
        let organizationID = try await WorkspaceContext.organizationID()
        if !upsells.isEmpty {
            let payloads = upsells.enumerated().map { index, upsell in
                BusinessUpsellPayload(
                    id: upsell.id,
                    organization_id: organizationID,
                    name: upsell.name.trimmed,
                    description: upsell.description.trimmed,
                    price: upsell.price,
                    sort_order: index
                )
            }
            try await supabase
                .from("business_upsells")
                .upsert(payloads, onConflict: "id")
                .execute()
        }

        for id in deletedIDs {
            try await supabase
                .from("business_upsells")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }
}

@Observable
@MainActor
final class BusinessSettingsStore {
    static let shared = BusinessSettingsStore()

    var profile = BusinessProfileSettings()
    var hourlyRates: [BusinessHourlyRate] = []
    var upsells: [BusinessUpsell] = []
    var logoData: Data?
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
    private(set) var hasLoaded = false

    var logoImage: UIImage? {
        logoData.flatMap(UIImage.init(data:))
    }

    private init() {}

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let loadedProfile = BusinessSettingsRepository.loadProfile()
            async let loadedRates = BusinessSettingsRepository.loadRates()
            async let loadedUpsells = BusinessSettingsRepository.loadUpsells()
            let (profile, rates, upsells) = try await (
                loadedProfile,
                loadedRates,
                loadedUpsells
            )
            self.profile = profile
            hourlyRates = rates
            self.upsells = upsells
            if let path = profile.logoStoragePath {
                logoData = try? await BusinessSettingsRepository.downloadLogo(path: path)
                if let image = logoImage {
                    BusinessProfile.shared.setLogo(image)
                }
            }
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func saveProfile(_ settings: BusinessProfileSettings, logoData: Data?) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            profile = try await BusinessSettingsRepository.saveProfile(
                settings,
                logoData: logoData
            )
            if let logoData {
                self.logoData = logoData
                BusinessProfile.shared.setLogo(UIImage(data: logoData))
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveRates(_ rates: [BusinessHourlyRate]) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let deletedIDs = Set(hourlyRates.map(\.id)).subtracting(rates.map(\.id))
            try await BusinessSettingsRepository.replaceRates(rates, deletedIDs: deletedIDs)
            hourlyRates = rates
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveUpsells(_ upsells: [BusinessUpsell]) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let deletedIDs = Set(self.upsells.map(\.id)).subtracting(upsells.map(\.id))
            try await BusinessSettingsRepository.replaceUpsells(upsells, deletedIDs: deletedIDs)
            self.upsells = upsells
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reset() {
        profile = BusinessProfileSettings()
        hourlyRates = []
        upsells = []
        logoData = nil
        isLoading = false
        isSaving = false
        errorMessage = nil
        hasLoaded = false
    }
}

struct BusinessSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = BusinessSettingsStore.shared
    @State private var draft = BusinessProfileSettings()
    @State private var markupText = "20"
    @State private var taxText = "0"
    @State private var selectedLogoData: Data?
    @State private var logoPickerItem: PhotosPickerItem?
    @State private var didLoadDraft = false

    private let paymentTerms = ["Due on receipt", "Net 7", "Net 15", "Net 30", "Net 45", "Net 60"]
    private let quoteValidOptions = [7, 14, 30, 45, 60, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    logoCard
                    companyCard
                    contactCard
                    locationCard
                    estimateDefaultsCard
                    paymentCard
                    relatedSetupLinks

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
                .padding(.bottom, 82)
            }
            .background(AppGray.bgPale.ignoresSafeArea())
            .navigationTitle("Business")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    HStack(spacing: 8) {
                        if store.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text(store.isSaving ? "Saving…" : "Save Business")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSave ? AppGray.ink : AppGray.borderStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSave || store.isSaving)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(AppGray.bgPale)
            }
            .task { await loadDraftIfNeeded() }
            .onChange(of: logoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    guard let rawData = try? await newItem.loadTransferable(type: Data.self),
                          let normalized = normalizedLogoData(rawData)
                    else { return }
                    selectedLogoData = normalized
                }
            }
        }
    }

    private var logoCard: some View {
        PhotosPicker(selection: $logoPickerItem, matching: .images) {
            VStack(spacing: 12) {
                Group {
                    if let image = selectedLogoData.flatMap(UIImage.init(data:)) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    } else if let image = store.logoImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    } else {
                        Image(systemName: "building.2.fill")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(AppGray.ink)
                    }
                }
                .frame(width: 104, height: 104)
                .background(AppGray.pill)
                .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(hasLogo ? "Change business logo" : "Add business logo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppGray.secondary)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .businessCard()
        }
        .buttonStyle(.plain)
    }

    private var hasLogo: Bool {
        if selectedLogoData != nil { return true }
        return store.logoImage != nil
    }

    private var companyCard: some View {
        BusinessFormCard(title: "Company", icon: "building.2") {
            BusinessTextField(label: "Business Name", placeholder: "Your company name", text: $draft.businessName)
                .textContentType(.organizationName)
            BusinessDivider()
            BusinessTextField(label: "License #", placeholder: "CGC1234567", text: $draft.licenseNumber)
            BusinessDivider()
            BusinessTextField(label: "Website", placeholder: "yourwebsite.com", text: $draft.website)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }
    }

    private var contactCard: some View {
        BusinessFormCard(title: "Contact", icon: "phone") {
            BusinessTextField(label: "Phone", placeholder: "+1 234 567 8900", text: $draft.phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
            BusinessDivider()
            BusinessTextField(label: "Email", placeholder: "email@company.com", text: $draft.email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
        }
    }

    private var locationCard: some View {
        BusinessFormCard(title: "Location", icon: "map") {
            BusinessTextField(label: "ZIP Code", placeholder: "e.g. 90210", text: $draft.postalCode)
                .textContentType(.postalCode)
                .keyboardType(.numbersAndPunctuation)
        }
    }

    private var estimateDefaultsCard: some View {
        BusinessFormCard(title: "Estimate Defaults", icon: "percent") {
            BusinessTextField(label: "Markup %", placeholder: "20", text: $markupText, suffix: "%")
                .keyboardType(.decimalPad)
            BusinessDivider()
            BusinessTextField(label: "Sales Tax %", placeholder: "0", text: $taxText, suffix: "%")
                .keyboardType(.decimalPad)
            BusinessDivider()
            BusinessPickerRow(label: "Payment Terms", value: draft.paymentTerms) {
                Picker("Payment Terms", selection: $draft.paymentTerms) {
                    ForEach(paymentTerms, id: \.self) { Text($0).tag($0) }
                }
            }
            BusinessDivider()
            BusinessPickerRow(label: "Quote Valid", value: "\(draft.quoteValidDays) days") {
                Picker("Quote Valid", selection: $draft.quoteValidDays) {
                    ForEach(quoteValidOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
            }
            Text("Applied automatically to new estimates")
                .font(.system(size: 12))
                .foregroundStyle(AppGray.secondary)
                .padding(.top, 2)
        }
    }

    private var paymentCard: some View {
        BusinessFormCard(title: "Get Paid", icon: "creditcard") {
            BusinessTextField(
                label: "Payment link",
                placeholder: "stripe.com/pay/... or paypal.me/you",
                text: $draft.paymentLink
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            Text("Clients can use this link to pay after accepting an estimate.")
                .font(.system(size: 12))
                .foregroundStyle(AppGray.secondary)
        }
    }

    private var relatedSetupLinks: some View {
        VStack(spacing: 12) {
            NavigationLink {
                HourlyRatesSetupView()
            } label: {
                BusinessLinkCard(
                    icon: "tag.fill",
                    title: "My Prices",
                    subtitle: store.hourlyRates.isEmpty
                        ? "Set up your hourly rates"
                        : "\(store.hourlyRates.count) custom rate\(store.hourlyRates.count == 1 ? "" : "s")"
                )
            }
            NavigationLink {
                BusinessUpsellsSetupView()
            } label: {
                BusinessLinkCard(
                    icon: "plus.circle.fill",
                    title: "My Upsells",
                    subtitle: store.upsells.isEmpty
                        ? "Add add-ons you always offer"
                        : "\(store.upsells.count) saved upsell\(store.upsells.count == 1 ? "" : "s")"
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var canSave: Bool {
        !draft.businessName.trimmed.isEmpty
            && decimal(markupText).map { (0...300).contains($0) } == true
            && decimal(taxText).map { (0...100).contains($0) } == true
    }

    private func loadDraftIfNeeded() async {
        guard !didLoadDraft else { return }
        if !store.hasLoaded { await store.refresh() }
        draft = store.profile
        markupText = displayNumber(draft.defaultMarkupPercent)
        taxText = displayNumber(draft.salesTaxPercent)
        didLoadDraft = true
    }

    private func save() {
        guard let markup = decimal(markupText), let tax = decimal(taxText) else { return }
        draft.defaultMarkupPercent = markup
        draft.salesTaxPercent = tax
        Task {
            if await store.saveProfile(draft, logoData: selectedLogoData) {
                dismiss()
            }
        }
    }
}

struct HourlyRatesSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = BusinessSettingsStore.shared
    @State private var drafts: [RateDraft] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Add the labor rates you use most. These are saved to your business and available on every device.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppGray.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach($drafts) { $rate in
                    EditableLineItemCard(
                        title: $rate.name,
                        titlePlaceholder: "Rate name",
                        amount: $rate.amount,
                        amountLabel: "Hourly rate",
                        amountSuffix: "/ hr",
                        onDelete: { drafts.removeAll { $0.id == rate.id } }
                    )
                }

                Button {
                    drafts.append(RateDraft(name: "", amount: ""))
                } label: {
                    Label("Add hourly rate", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppGray.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
                }
                .buttonStyle(.plain)

                if let error = store.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(AppGray.bgPale.ignoresSafeArea())
        .navigationTitle("Hourly Rates")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { saveBar(title: "Save Rates", action: save) }
        .task { await loadIfNeeded() }
    }

    private var validRates: [BusinessHourlyRate]? {
        var result: [BusinessHourlyRate] = []
        for draft in drafts {
            guard !draft.name.trimmed.isEmpty,
                  let amount = decimal(draft.amount),
                  (0...100000).contains(amount)
            else { return nil }
            result.append(BusinessHourlyRate(id: draft.id, name: draft.name.trimmed, hourlyRate: amount))
        }
        return result.isEmpty ? nil : result
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        if !store.hasLoaded { await store.refresh() }
        drafts = store.hourlyRates.map(RateDraft.init)
        if drafts.isEmpty {
            drafts = BusinessHourlyRate.starterDefaults.map(RateDraft.init)
        }
        didLoad = true
    }

    private func save() {
        guard let rates = validRates else { return }
        Task {
            if await store.saveRates(rates) { dismiss() }
        }
    }

    @ViewBuilder
    private func saveBar(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(store.isSaving ? "Saving…" : title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(validRates == nil ? AppGray.borderStrong : AppGray.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(validRates == nil || store.isSaving)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(AppGray.bgPale)
    }
}

struct BusinessUpsellsSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = BusinessSettingsStore.shared
    @State private var drafts: [UpsellDraft] = []
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Save the add-ons you regularly offer so they are ready for future estimates.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppGray.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach($drafts) { $upsell in
                    VStack(spacing: 12) {
                        EditableLineItemCard(
                            title: $upsell.name,
                            titlePlaceholder: "Upsell name",
                            amount: $upsell.amount,
                            amountLabel: "Price",
                            amountSuffix: nil,
                            onDelete: { drafts.removeAll { $0.id == upsell.id } }
                        )
                        TextField("Optional description", text: $upsell.description, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(2...4)
                            .padding(16)
                            .businessCard()
                    }
                }

                Button {
                    drafts.append(UpsellDraft(name: "", description: "", amount: ""))
                } label: {
                    Label("Add upsell", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppGray.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
                }
                .buttonStyle(.plain)

                if let error = store.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }
            }
            .padding(20)
            .padding(.bottom, 80)
        }
        .background(AppGray.bgPale.ignoresSafeArea())
        .navigationTitle("My Upsells")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text(store.isSaving ? "Saving…" : "Save Upsells")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(validUpsells == nil ? AppGray.borderStrong : AppGray.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(validUpsells == nil || store.isSaving)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(AppGray.bgPale)
        }
        .task { await loadIfNeeded() }
    }

    private var validUpsells: [BusinessUpsell]? {
        var result: [BusinessUpsell] = []
        for draft in drafts {
            guard !draft.name.trimmed.isEmpty,
                  let amount = decimal(draft.amount),
                  (0...10_000_000).contains(amount)
            else { return nil }
            result.append(BusinessUpsell(
                id: draft.id,
                name: draft.name.trimmed,
                description: draft.description.trimmed,
                price: amount
            ))
        }
        return result
    }

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        if !store.hasLoaded { await store.refresh() }
        drafts = store.upsells.map(UpsellDraft.init)
        if drafts.isEmpty { drafts = [UpsellDraft(name: "", description: "", amount: "")] }
        didLoad = true
    }

    private func save() {
        guard let upsells = validUpsells else { return }
        Task {
            if await store.saveUpsells(upsells) { dismiss() }
        }
    }
}

private struct RateDraft: Identifiable {
    var id = UUID()
    var name: String
    var amount: String

    init(name: String, amount: String) {
        self.name = name
        self.amount = amount
    }

    init(_ rate: BusinessHourlyRate) {
        id = rate.id
        name = rate.name
        amount = displayNumber(rate.hourlyRate)
    }
}

private struct UpsellDraft: Identifiable {
    var id = UUID()
    var name: String
    var description: String
    var amount: String

    init(name: String, description: String, amount: String) {
        self.name = name
        self.description = description
        self.amount = amount
    }

    init(_ upsell: BusinessUpsell) {
        id = upsell.id
        name = upsell.name
        description = upsell.description
        amount = displayNumber(upsell.price)
    }
}

private struct BusinessFormCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(Color.white)

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
    }
}

private struct BusinessTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var suffix: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppGray.secondary)
            HStack {
                TextField(placeholder, text: $text)
                    .font(.system(size: 16))
                    .foregroundStyle(AppGray.ink)
                if let suffix {
                    Text(suffix).font(.system(size: 16)).foregroundStyle(AppGray.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppGray.border.opacity(0.75)))
        }
    }
}

private struct BusinessPickerRow<Content: View>: View {
    let label: String
    let value: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppGray.secondary)
            Menu {
                content
            } label: {
                HStack {
                    Text(value).font(.system(size: 16)).foregroundStyle(AppGray.ink)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppGray.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(AppGray.border.opacity(0.75)))
            }
        }
    }
}

private struct BusinessDivider: View {
    var body: some View { Divider().overlay(AppGray.border.opacity(0.7)) }
}

private struct BusinessLinkCard: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppGray.ink)
                .frame(width: 50, height: 50)
                .background(AppGray.pill)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(AppGray.ink)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(AppGray.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppGray.secondary)
        }
        .padding(16)
        .businessCard()
    }
}

private struct EditableLineItemCard: View {
    @Binding var title: String
    let titlePlaceholder: String
    @Binding var amount: String
    let amountLabel: String
    let amountSuffix: String?
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                TextField(titlePlaceholder, text: $title)
                    .font(.system(size: 16, weight: .semibold))
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppGray.secondary)
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Text(amountLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppGray.secondary)
                Spacer()
                Text("$").foregroundStyle(AppGray.secondary)
                TextField("0.00", text: $amount)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                if let amountSuffix { Text(amountSuffix).foregroundStyle(AppGray.secondary) }
            }
        }
        .padding(16)
        .businessCard()
    }
}

private extension View {
    func businessCard() -> some View {
        background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private func decimal(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: ".").trimmed)
}

private func displayNumber(_ number: Double) -> String {
    number.rounded() == number ? String(Int(number)) : String(format: "%.2f", number)
}

private func normalizedLogoData(_ data: Data) -> Data? {
    guard let source = UIImage(data: data) else { return nil }
    let maxDimension: CGFloat = 1200
    let scale = min(1, maxDimension / max(source.size.width, source.size.height))
    let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
    return image.jpegData(compressionQuality: 0.86)
}

#Preview("Business setup") {
    BusinessSetupView()
}
