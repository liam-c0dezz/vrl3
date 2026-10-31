//
//  InvoiceDetailView.swift
//  Construction Estimate
//

import SwiftUI
import UniformTypeIdentifiers

private enum InvoiceMetadataDate: String, Identifiable {
    case issued
    case due

    var id: String { rawValue }
    var title: String { self == .issued ? "Issued" : "Due" }
}

struct InvoiceDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var invoice: Invoice
    var onSave: ((Invoice) -> Void)? = nil

    @State private var selectedView: String = "Invoice"
    @State private var showClientPicker = false
    @State private var selectedClient: Client? = nil
    @State private var showTermsSheet = false
    @State private var termsDraft = ""
    @State private var businessProfile = BusinessProfile.shared
    @State private var showSendSheet = false
    @State private var renderStore = ProjectRenderStore.shared
    @State private var projectStore = ProjectStore.shared
    @State private var acceptedRender: ProjectRender?
    @State private var renderImages: ProjectRenderImages?
    @State private var showRenderCreation = false
    @State private var descriptionEditor = InvoiceDescriptionEditorController()
    @State private var businessSettingsStore = BusinessSettingsStore.shared
    @State private var editingLineItem: InvoiceLineItem?
    @State private var showingAddLineItem = false
    @State private var deletingLineItems = false
    @State private var selectedLineItemIDs: Set<UUID> = []
    @State private var showingDiscountEditor = false
    @State private var showingTaxEditor = false
    @State private var showingFileImporter = false
    @State private var showingClientMenu = false
    @State private var showingPaymentMethodPicker = false
    @State private var editingMetadataDate: InvoiceMetadataDate?
    @State private var clientRequiredMessage = false
    @State private var documentStore = ProjectDocumentStore()
    @State private var showingInvoiceOptions = false
    @State private var subscriptionError: String?

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            navBar

            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // Segment control (Invoice / Client view)
                    segmentControl

                    if selectedView == "Invoice" {
                        invoiceContent
                    } else {
                        clientContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 180)
            }

            Spacer()

            // Bottom buttons
            bottomButtons
        }
        .background(AppGray.bgPale)
        .navigationBarHidden(true)
        .sheet(isPresented: $showClientPicker) {
            ClientPickerSheet { client in
                selectedClient = client
                invoice.clientId = client.id
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showTermsSheet) {
            TermsSheet(terms: $invoice.termsAndConditions, draft: $termsDraft)
                .presentationDetents([.medium])
        }
        .sheet(item: $editingLineItem) { item in
            MaterialEditSheet(
                item: EstimateLineItem(name: item.title, quantity: item.quantity, unitLabel: item.unit, unitPrice: item.unitPrice, total: item.total),
                onSave: { updated in
                    if let index = invoice.items.firstIndex(where: { $0.id == item.id }) {
                        invoice.items[index].title = updated.name
                        invoice.items[index].quantity = updated.quantity
                        invoice.items[index].unitPrice = updated.unitPrice
                        invoice.items[index].unit = updated.unitLabel
                    }
                    editingLineItem = nil
                }
            )
        }
        .sheet(isPresented: $showingAddLineItem) {
            MaterialEditSheet(
                title: "Add Item",
                item: EstimateLineItem(name: "", quantity: 1, unitLabel: "EA", unitPrice: 0, total: 0),
                onSave: { item in
                    invoice.items.append(InvoiceLineItem(title: item.name, quantity: item.quantity, unitPrice: item.unitPrice, unit: item.unitLabel))
                    showingAddLineItem = false
                }
            )
        }
        .sheet(isPresented: $showingDiscountEditor) {
            InvoiceAmountEditor(title: "Discount", value: $invoice.discount, suffix: "$", maximum: invoice.subtotal)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showingTaxEditor) {
            InvoiceAmountEditor(title: "Tax", value: $invoice.taxPercent, suffix: "%", maximum: 100)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showingPaymentMethodPicker) {
            PaymentMethodPicker(invoice: $invoice)
                .presentationDetents([.large])
        }
        .sheet(item: $editingMetadataDate) { field in
            InvoiceDatePickerSheet(
                title: field.title,
                date: metadataDateBinding(for: field)
            )
            .presentationDetents([.height(430)])
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    for url in urls {
                        var saved = true
                        if let projectID = invoice.projectId {
                            saved = await documentStore.upload(url, projectID: projectID, invoiceID: invoice.id, category: "invoice_attachment")
                        }
                        let name = url.lastPathComponent
                        if saved && !invoice.attachments.contains(name) { invoice.attachments.append(name) }
                    }
                }
            }
        }
        .alert("Client required", isPresented: $clientRequiredMessage) {
            HapticButton("Choose client") { showClientPicker = true }
            HapticButton("Cancel", role: .cancel) {}
        } message: {
            Text("Select a client before previewing or sending this invoice.")
        }
        .alert(
            "Subscription unavailable",
            isPresented: Binding(
                get: { subscriptionError != nil },
                set: { if !$0 { subscriptionError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(subscriptionError ?? "Please try again.")
        }
        .confirmationDialog("Invoice Options", isPresented: $showingInvoiceOptions, titleVisibility: .visible) {
            HapticButton("Delete Invoice", role: .destructive) {
                InvoiceStore.shared.delete(invoice.id)
                dismiss()
            }
            HapticButton("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this invoice.")
        }
        .sheet(isPresented: $showSendSheet) {
            DocumentSendSheet(
                document: .invoice(invoice),
                client: selectedClient,
                renderImages: invoice.includeRender ? renderImages : nil,
                businessLogo: businessProfile.logoImage,
                businessDetails: businessSettingsStore.profile,
                onSent: {
                    invoice.status = "Sent"
                    onSave?(invoice)
                    showSendSheet = false
                    dismiss()
                }
            )
        }
        .fullScreenCover(isPresented: $showRenderCreation, onDismiss: {
            Task { await loadProjectRender() }
        }) {
            if let projectID = invoice.projectId,
               let project = projectStore.projects.first(where: { $0.id == projectID }) {
                RenderCreationView(project: project)
            } else {
                ProgressView()
                    .task {
                        await projectStore.refresh()
                        if !projectStore.projects.contains(where: { $0.id == invoice.projectId }) {
                            showRenderCreation = false
                        }
                    }
            }
        }
        .task(id: invoice.clientId) {
            guard let clientID = invoice.clientId else { return }
            await ClientStore.shared.refresh()
            selectedClient = ClientStore.shared.clients.first { $0.id == clientID }
        }
        .task(id: invoice.projectId) {
            await projectStore.refresh()
            await loadProjectRender()
            if let projectID = invoice.projectId {
                await documentStore.refresh(projectID: projectID)
                let storedNames = documentStore.documents
                    .filter { $0.invoice_id == invoice.id }
                    .map(\.name)
                invoice.attachments.append(contentsOf: storedNames.filter { !invoice.attachments.contains($0) })
            }
        }
        .task {
            if !businessSettingsStore.hasLoaded {
                await businessSettingsStore.refresh()
            }
            if invoice.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                invoice.companyName = businessSettingsStore.profile.businessName
            }
            if invoice.dueAt == nil {
                let days = invoice.dueDate.localizedCaseInsensitiveContains("15") ? 15 : 30
                invoice.dueAt = Calendar.current.date(byAdding: .day, value: days, to: invoice.createdAt)
                if let dueAt = invoice.dueAt { invoice.dueDate = formattedDate(dueAt) }
            }
        }
    }

    // MARK: - Nav Bar

    private var navBar: some View {
        ZStack {
            Text("Invoice")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                HapticButton(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                HapticButton { showingInvoiceOptions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .rotationEffect(.degrees(90))
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Segment Control

    private var segmentControl: some View {
        HStack(spacing: 0) {
            ForEach(["Invoice", "Client view"], id: \.self) { tab in
                HapticButton(action: {
                    if tab == "Client view" && selectedClient == nil {
                        clientRequiredMessage = true
                    } else {
                        selectedView = tab
                    }
                }) {
                    Text(tab)
                        .font(.system(
                            size: 15,
                            weight: tab == "Client view" ? .medium : (selectedView == tab ? .semibold : .regular)
                        ))
                        .foregroundColor(selectedView == tab ? AppGray.ink : AppGray.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selectedView == tab ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(AppGray.bgSubtle)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Invoice Content

    private var invoiceContent: some View {
        VStack(spacing: 20) {
            invoiceSection(title: "Company name") {
                companyNameCard
            }

            invoiceSection(title: "Client") {
                if let client = selectedClient {
                    clientInfoCard(client: client)
                } else {
                    addClientButton
                }
            }

            invoiceSection(title: "Job Details") {
                invoiceFormCard
            }

            invoiceMetadataCard

            // Line items
            lineItemsSection

            // Totals
            totalsCard

            paymentMethodsSection

            // Attachments
            attachmentsSection

            // Terms & conditions
            addTermsButton
        }
    }

    // MARK: - Project Render

    @ViewBuilder
    private var renderSection: some View {
        if invoice.projectId != nil {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Before & after")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Add the accepted project render to this invoice.")
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                    Spacer()
                }

                if let acceptedRender, let renderImages {
                    InvoiceBeforeAfterView(images: renderImages)

                    Toggle(isOn: $invoice.includeRender) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include with invoice")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Your client will see both images.")
                                .font(.system(size: 12))
                                .foregroundColor(AppGray.secondary)
                        }
                    }
                    .tint(brandBlue)
                    .onChange(of: invoice.includeRender) { _, include in
                        invoice.renderId = include ? acceptedRender.id : nil
                    }
                } else if acceptedRender != nil {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Render attached — loading preview…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                } else {
                    HapticButton(action: beginRenderCreation) {
                        HStack(spacing: 9) {
                            Image(systemName: "sparkles")
                            Text("Create a project render")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(brandBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(brandBlue.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(brandBlue.opacity(0.24), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
        }
    }

    private func loadProjectRender() async {
        guard let projectID = invoice.projectId else { return }
        await renderStore.refresh(projectID: projectID)
        let selected = invoice.renderId.flatMap { id in
            renderStore.renders(for: projectID).first(where: { $0.id == id && $0.isInvoiceReady })
        } ?? renderStore.latestInvoiceReady(for: projectID)

        acceptedRender = selected
        guard let selected else {
            renderImages = nil
            invoice.renderId = nil
            invoice.includeRender = false
            return
        }

        invoice.renderId = selected.id
        invoice.includeRender = true
        renderImages = try? await renderStore.images(for: selected)
    }

    // MARK: - Company

    private var companyNameCard: some View {
        ZStack(alignment: .leading) {
            if invoice.companyName.isEmpty {
                Text("Add company name")
                    .font(.system(size: 16))
                    .fontWeight(.regular)
                    .foregroundColor(AppGray.muted)
                    .allowsHitTesting(false)
            }

            TextField("", text: $invoice.companyName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppGray.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Client Info Card

    private func clientInfoCard(client: Client) -> some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppGray.pill)
                    .frame(width: 44, height: 44)
                Image(systemName: "person.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(AppGray.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(client.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                if !client.email.isEmpty {
                    Text(client.email)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                }
                if !client.phone.isEmpty {
                    Text(client.phone)
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                }
            }

            Spacer()

            HapticButton(action: { showingClientMenu = true }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)
                    .rotationEffect(.degrees(90))
            }
            .confirmationDialog("Client", isPresented: $showingClientMenu, titleVisibility: .hidden) {
                HapticButton("Change client") { showClientPicker = true }
                HapticButton("Remove client", role: .destructive) {
                    selectedClient = nil
                    invoice.clientId = nil
                }
                HapticButton("Cancel", role: .cancel) {}
            }
        }
        .invoiceCard()
    }

    // MARK: - Add Client HapticButton

    private var addClientButton: some View {
        HapticButton(action: { showClientPicker = true }) {
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppGray.ink)
                Text("Add Client")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppGray.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.vertical, 28)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
        }
    }

    // MARK: - Invoice Form Card

    private var invoiceFormCard: some View {
        VStack(spacing: 16) {
            // Title field
            TextField("Title", text: $invoice.title)
                .font(.system(size: 16))
                .foregroundColor(AppGray.ink)
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Description with selection-aware formatting toolbar
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    formattingButton("bold", label: "Bold") { descriptionEditor.toggleBold() }
                    formattingButton("italic", label: "Italic") { descriptionEditor.toggleItalic() }
                    formattingButton("list.bullet", label: "Bulleted list") { descriptionEditor.toggleBullets() }
                    formattingButton("list.number", label: "Numbered list") { descriptionEditor.toggleNumbering() }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Rectangle()
                    .fill(AppGray.badge.opacity(0.85))
                    .frame(height: 0.7)

                ZStack(alignment: .topLeading) {
                    if InvoiceRichText.isEmpty(invoice.description) {
                        Text("Enter description")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(AppGray.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                    }

                    InvoiceDescriptionEditor(
                        storedValue: $invoice.description,
                        controller: descriptionEditor
                    )
                    .frame(minHeight: 132)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity)
    }

    private func formattingButton(
        _ icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        HapticButton(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppGray.ink)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Invoice dates and number

    private var invoiceMetadataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                metadataHeader("Issued")
                metadataHeader("Due")
                metadataHeader("Invoice #")
            }

            HStack(spacing: 0) {
                metadataDateButton(.issued, date: invoice.createdAt)
                metadataDivider
                metadataDateButton(.due, date: metadataDateBinding(for: .due).wrappedValue)
                metadataDivider
                TextField("Number", text: $invoice.invoiceNumber)
                    .font(.system(size: 16))
                    .foregroundColor(AppGray.ink)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
            }
            .frame(height: 64)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
        }
        .foregroundStyle(AppGray.ink)
    }

    private func metadataHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AppGray.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
    }

    private func metadataDateButton(_ field: InvoiceMetadataDate, date: Date) -> some View {
        HapticButton { editingMetadataDate = field } label: {
            Text(date.formatted(date: .numeric, time: .omitted))
                .font(.system(size: 16))
                .foregroundColor(AppGray.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(AppGray.badge.opacity(0.85))
            .frame(width: 0.7)
            .padding(.vertical, 10)
    }

    private func metadataDateBinding(for field: InvoiceMetadataDate) -> Binding<Date> {
        switch field {
        case .issued:
            return $invoice.createdAt
        case .due:
            return Binding(
                get: {
                    invoice.dueAt ?? Calendar.current.date(byAdding: .day, value: 30, to: invoice.createdAt)!
                },
                set: {
                    invoice.dueAt = $0
                    invoice.dueDate = formattedDate($0)
                }
            )
        }
    }

    // MARK: - Line Items

    private var lineItemsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Invoice items")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Spacer()
                HapticButton(action: { showingAddLineItem = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 36, height: 36)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }
                HapticButton(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        deletingLineItems.toggle()
                        if !deletingLineItems { selectedLineItemIDs.removeAll() }
                    }
                }) {
                    Image(systemName: deletingLineItems ? "xmark" : "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 36, height: 36)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)

            ForEach(Array(invoice.items.enumerated()), id: \.element.id) { index, item in
                Rectangle()
                    .fill(AppGray.badge.opacity(0.85))
                    .frame(height: 0.7)
                lineItemCard(item: item, index: index)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
        .foregroundStyle(AppGray.ink)
    }

    private func lineItemCard(item: InvoiceLineItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppGray.ink)
                Spacer()
                Text(item.formattedTotal)
                    .font(.system(size: 16))
                    .foregroundColor(AppGray.secondary)
                if deletingLineItems {
                    Image(systemName: selectedLineItemIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(selectedLineItemIDs.contains(item.id) ? brandBlue : AppGray.muted)
                        .padding(.leading, 8)
                }
            }
            Text("\(Int(item.quantity)) x \(formattedCurrency(item.unitPrice)) / \(item.unit)")
                .font(.system(size: 14))
                .foregroundColor(AppGray.secondary)
        }
        .padding(18)
        .contentShape(Rectangle())
        .onTapGesture {
            if deletingLineItems {
                if selectedLineItemIDs.contains(item.id) { selectedLineItemIDs.remove(item.id) }
                else { selectedLineItemIDs.insert(item.id) }
            } else {
                editingLineItem = item
            }
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        VStack(spacing: 0) {
            // Subtotal
            HStack {
                Text("Subtotal")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Text("$ \(String(format: "%.2f", invoice.subtotal))")
                    .font(.system(size: 16))
                    .foregroundColor(AppGray.secondary)
            }
            .padding(18)

            Rectangle()
                .fill(AppGray.badge.opacity(0.85))
                .frame(height: 0.7)
                .padding(.horizontal, 18)

            // Discount
            HStack {
                Text("Discount")
                    .font(.system(size: 16))
                Spacer()
                HapticButton(invoice.discount > 0 ? formattedCurrency(invoice.discount) : "Add", action: { showingDiscountEditor = true }).font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppGray.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )
            }
            .padding(18)

            // Tax
            HStack {
                Text("Tax")
                    .font(.system(size: 16))
                Spacer()
                HapticButton(invoice.taxPercent > 0 ? formattedPercent(invoice.taxPercent) : "Add", action: { showingTaxEditor = true }).font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppGray.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            Rectangle()
                .fill(AppGray.badge.opacity(0.85))
                .frame(height: 0.7)
                .padding(.horizontal, 18)

            // Total
            HStack {
                Text("Balance due")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text(invoice.formattedTotal)
                    .font(.system(size: 20, weight: .semibold))
            }
            .padding(18)

        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
        .foregroundStyle(AppGray.ink)
    }

    // MARK: - Payment methods

    private var paymentMethodsSection: some View {
        invoiceSection(title: "Payment methods") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach($invoice.paymentMethods) { $method in
                    HStack(spacing: 12) {
                        HapticButton {
                            invoice.paymentMethods.removeAll { $0.id == method.id }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 25.5, height: 25.5)
                                .background(AppGray.ink)
                                .clipShape(Circle())
                        }
                        Text(method.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppGray.ink)
                            .frame(width: 92, alignment: .leading)
                        Divider().frame(height: 28)
                        TextField("Enter details", text: $method.details)
                            .font(.system(size: 15))
                            .foregroundColor(AppGray.ink)
                    }
                    .padding(.vertical, 6)
                }

                HapticButton { showingPaymentMethodPicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 27, height: 27)
                            .background(brandBlue)
                            .clipShape(Circle())
                        Text("Add payment method")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppGray.ink)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .invoiceCard()
            .foregroundStyle(AppGray.ink)
        }
    }

    // MARK: - Attachments

    private var attachmentsSection: some View {
        invoiceSection(title: "Attachments") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(invoice.attachments, id: \.self) { name in
                    HStack {
                        Image(systemName: "paperclip")
                        Text(name).lineLimit(1)
                        Spacer()
                        HapticButton {
                            if let projectID = invoice.projectId,
                               let document = documentStore.documents.first(where: { $0.invoice_id == invoice.id && $0.name == name }) {
                                Task { await documentStore.delete(document, projectID: projectID) }
                            }
                            invoice.attachments.removeAll { $0 == name }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(AppGray.muted)
                        }
                    }
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.ink)
                }

                HapticButton(action: { showingFileImporter = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18))
                            .foregroundColor(brandBlue)
                        Text("Add files")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(brandBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .background(brandBlue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(brandBlue.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                    )
                }

                if documentStore.isUploading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Uploading attachment…")
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                }
                if let error = documentStore.lastError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func invoiceSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppGray.ink)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Terms HapticButton

    private var addTermsButton: some View {
        HapticButton(action: {
            termsDraft = invoice.termsAndConditions
            showTermsSheet = true
        }) {
            Text("Add terms & conditions")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(brandBlue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(brandBlue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(brandBlue.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                )
        }
    }

    // MARK: - Client Content

    private var clientContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This is how your client will see the invoice when you send it.")
                .font(.system(size: 13))
                .foregroundColor(AppGray.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            DocumentPagePreview(
                data: OutgoingDocument.invoice(invoice).pdfData(
                    client: selectedClient,
                    renderImages: invoice.includeRender ? renderImages : nil,
                    businessLogo: businessProfile.logoImage,
                    businessDetails: businessSettingsStore.profile
                )
            )
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        VStack(spacing: 0) {
            Divider()

            HapticButton(action: {
                if deletingLineItems {
                    invoice.items.removeAll { selectedLineItemIDs.contains($0.id) }
                    selectedLineItemIDs.removeAll()
                    deletingLineItems = false
                } else if selectedClient == nil {
                    clientRequiredMessage = true
                } else {
                    beginSendingInvoice()
                }
            }) {
                Text(deletingLineItems ? "Delete (\(selectedLineItemIDs.count) line item\(selectedLineItemIDs.count == 1 ? "" : "s"))?" : "Preview & Send")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppGray.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .disabled(deletingLineItems && selectedLineItemIDs.isEmpty)
            .opacity(deletingLineItems && selectedLineItemIDs.isEmpty ? 0.45 : 1)
        }
        .background(Color.white)
    }

    private func beginRenderCreation() {
        SuperwallService.performPremiumAction(
            .createRender,
            params: ["source": "invoice_builder"],
            onFailure: { subscriptionError = $0 },
            action: { showRenderCreation = true }
        )
    }

    private func beginSendingInvoice() {
        SuperwallService.performPremiumAction(
            .sendInvoice,
            params: ["source": "invoice_builder"],
            onFailure: { subscriptionError = $0 },
            action: {
                onSave?(invoice)
                showSendSheet = true
            }
        )
    }

    // MARK: - Helpers

    private func formattedCurrency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formattedPercent(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))%" : String(format: "%.2f%%", value)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

private struct InvoiceBeforeAfterView: View {
    let images: ProjectRenderImages

    var body: some View {
        HStack(spacing: 10) {
            imageCard(images.before, label: "BEFORE")
            imageCard(images.after, label: "AFTER")
        }
    }

    private func imageCard(_ image: UIImage, label: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 154)
                .clipped()

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
                .padding(9)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(AppGray.border.opacity(0.7), lineWidth: 1)
        )
    }
}

private struct InvoiceDatePickerSheet: View {
    let title: String
    @Binding var date: Date

    @Environment(\.dismiss) private var dismiss
    private let brandBlue = AppBrand.accent

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(brandBlue)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        HapticButton("Done") { dismiss() }
                            .fontWeight(.semibold)
                            .foregroundColor(brandBlue)
                    }
                }
        }
    }
}

private extension View {
    func invoiceCard() -> some View {
        self
            .padding(18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)
    }
}

private struct InvoiceAmountEditor: View {
    let title: String
    @Binding var value: Double
    let suffix: String
    let maximum: Double

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    private let brandBlue = AppBrand.accent

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Enter \(title.lowercased())")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppGray.ink)
                HStack {
                    if suffix == "$" { Text("$").foregroundColor(AppGray.secondary) }
                    TextField("0", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 18, weight: .medium))
                    if suffix == "%" { Text("%").foregroundColor(AppGray.secondary) }
                }
                .padding(15)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppGray.border, lineWidth: 1))
                Spacer()
            }
            .padding(20)
            .background(AppGray.bgPale.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { HapticButton("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    HapticButton("Save") {
                        value = min(max(Double(text) ?? 0, 0), maximum)
                        dismiss()
                    }
                    .foregroundColor(brandBlue)
                }
            }
            .onAppear { text = value == 0 ? "" : String(value) }
        }
    }
}

private struct PaymentMethodPicker: View {
    @Binding var invoice: Invoice
    @Environment(\.dismiss) private var dismiss

    private let methods = ["Cash", "Credit card", "ACH transfer", "PayPal", "Venmo", "Zelle", "Square", "Check", "Pay online", "Other"]
    private let brandBlue = AppBrand.accent

    var body: some View {
        NavigationStack {
            List(methods, id: \.self) { method in
                HapticButton {
                    if !invoice.paymentMethods.contains(where: { $0.name == method }) {
                        invoice.paymentMethods.append(InvoicePaymentMethod(name: method, details: ""))
                    }
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: paymentIcon(method))
                            .foregroundColor(brandBlue)
                            .frame(width: 28)
                        Text(method)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppGray.ink)
                        Spacer()
                        if invoice.paymentMethods.contains(where: { $0.name == method }) {
                            Image(systemName: "checkmark").foregroundColor(brandBlue)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Payment method")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { HapticButton("Cancel") { dismiss() } } }
        }
    }

    private func paymentIcon(_ method: String) -> String {
        switch method {
        case "Cash": return "banknote"
        case "Credit card", "Square": return "creditcard"
        case "ACH transfer": return "building.columns"
        case "Check": return "doc.text"
        case "Pay online": return "link"
        default: return "dollarsign.circle"
        }
    }
}

// MARK: - Terms Sheet

private struct TermsSheet: View {
    @Binding var terms: String
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Terms & Conditions")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                HapticButton("Done") {
                    terms = draft
                    dismiss()
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(brandBlue)
            }

            TextField("Enter your terms and conditions...", text: $draft, axis: .vertical)
                .focused($focused)
                .lineLimit(5...12)
                .font(.system(size: 15))
                .padding(14)
                .background(AppGray.bgSubtle)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(24)
        .onAppear {
            draft = terms
            focused = true
        }
    }
}

// MARK: - Invoice Preview (shared: Client view tab, future PDF + web link)

/// A document-style rendering of an invoice exactly as the client will
/// receive it. Self-contained and data-driven so the same view can back
/// the in-app Client view, a generated PDF, and the hosted client page.
struct InvoicePreviewView: View {
    let invoice: Invoice
    let client: Client?
    let logo: UIImage?
    var renderImages: ProjectRenderImages? = nil

    private let brandBlue = AppBrand.accent
    private let labelGray = AppGray.secondary
    private let rowText = AppGray.itemText

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: invoice.createdAt)
    }

    private func qtyText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            billToRow
                .padding(.vertical, 20)
            titleBlock
            renderBlock
            lineItemsTable
            totals
                .padding(.top, 16)
            termsBlock
        }
        .padding(24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(AppGray.badge, lineWidth: 1)
        )
        .overlay(alignment: .top) {
            Capsule()
                .fill(brandBlue)
                .frame(width: 72, height: 4)
                .padding(.top, 8)
        }
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    @ViewBuilder
    private var renderBlock: some View {
        if let renderImages {
            VStack(alignment: .leading, spacing: 10) {
                Text("PROJECT VISUALIZATION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(labelGray)
                BeforeAfterRenderView(images: renderImages)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: Header (logo + invoice number)

    private var header: some View {
        HStack(alignment: .top) {
            if let logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 150, maxHeight: 56, alignment: .leading)
            } else {
                Text("INVOICE")
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(.black)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if logo != nil {
                    Text("INVOICE")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(1.5)
                        .foregroundColor(labelGray)
                }
                Text(invoice.invoiceNumber)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                Text(dateText)
                    .font(.system(size: 12))
                    .foregroundColor(labelGray)
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: Bill-to + due date

    private var billToRow: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BILL TO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(labelGray)
                if let client {
                    Text(client.name.isEmpty ? "Client" : client.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                    if !client.company.isEmpty { previewLine(client.company) }
                    if !client.address.isEmpty { previewLine(client.address) }
                    if !client.email.isEmpty { previewLine(client.email) }
                    if !client.phone.isEmpty { previewLine(client.phone) }
                } else {
                    Text("No client selected")
                        .font(.system(size: 14))
                        .foregroundColor(labelGray)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("DUE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(labelGray)
                Text(invoice.dueDate)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(rowText)
            }
        }
    }

    private func previewLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(rowText)
    }

    // MARK: Title + description

    @ViewBuilder
    private var titleBlock: some View {
        if !invoice.title.isEmpty || !invoice.description.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if !invoice.title.isEmpty {
                    Text(invoice.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.black)
                }
                if !invoice.description.isEmpty {
                    Text(invoice.description)
                        .font(.system(size: 14))
                        .foregroundColor(rowText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 18)
        }
    }

    // MARK: Line items table

    private var lineItemsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DESCRIPTION")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(labelGray)
                Spacer()
                Text("AMOUNT")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(labelGray)
            }
            .padding(.bottom, 10)

            Divider()

            ForEach(invoice.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                        Text("\(qtyText(item.quantity)) × \(currency(item.unitPrice)) / \(item.unit)")
                            .font(.system(size: 12))
                            .foregroundColor(labelGray)
                    }
                    Spacer()
                    Text(item.formattedTotal)
                        .font(.system(size: 14))
                        .foregroundColor(rowText)
                }
                .padding(.vertical, 12)
                Divider()
            }
        }
    }

    // MARK: Totals

    private var totals: some View {
        VStack(spacing: 8) {
            totalRow("Subtotal", invoice.formattedSubtotal, bold: false)
            if invoice.discountAmount > 0 {
                totalRow("Discount", "−\(currency(invoice.discountAmount))", bold: false)
            }
            if invoice.taxAmount > 0 {
                totalRow("Tax (\(Int(invoice.taxPercent.rounded()))%)", currency(invoice.taxAmount), bold: false)
            }
            Divider()
                .padding(.vertical, 2)
            totalRow("Total", invoice.formattedTotal, bold: true)
        }
    }

    private func totalRow(_ label: String, _ value: String, bold: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: bold ? 17 : 14, weight: bold ? .bold : .regular))
                .foregroundColor(bold ? .black : rowText)
            Spacer()
            Text(value)
                .font(.system(size: bold ? 17 : 14, weight: bold ? .bold : .regular))
                .foregroundColor(bold ? .black : rowText)
        }
    }

    // MARK: Terms

    @ViewBuilder
    private var termsBlock: some View {
        if !invoice.termsAndConditions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("TERMS & CONDITIONS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundColor(labelGray)
                Text(invoice.termsAndConditions)
                    .font(.system(size: 13))
                    .foregroundColor(rowText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24)
        }
    }
}

#Preview {
    NavigationStack {
        InvoiceDetailView(invoice: Invoice.createNew(number: 1))
    }
}
