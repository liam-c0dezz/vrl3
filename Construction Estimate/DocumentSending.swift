import SwiftUI
import UIKit
import MessageUI
import PDFKit

struct EstimateMediaAsset: Identifiable {
    let id: UUID
    let kind: String
    let displayName: String
    let mimeType: String?
    let data: Data

    var previewImage: UIImage? {
        if mimeType == "application/pdf" || displayName.lowercased().hasSuffix(".pdf") {
            guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
            return page.thumbnail(of: CGSize(width: 1_200, height: 1_200), for: .mediaBox)
        }
        return UIImage(data: data)
    }
}

enum OutgoingDocument {
    case estimate(Estimate)
    case invoice(Invoice)

    var title: String {
        switch self {
        case .estimate(let estimate):
            return estimate.title
        case .invoice(let invoice):
            return invoice.title.isEmpty ? "Invoice \(invoice.invoiceNumber)" : invoice.title
        }
    }

    var number: String {
        switch self {
        case .estimate(let estimate): return estimate.estimateNumber
        case .invoice(let invoice): return invoice.invoiceNumber
        }
    }

    var kind: String {
        switch self {
        case .estimate: return "Estimate"
        case .invoice: return "Invoice"
        }
    }

    var formattedTotal: String {
        switch self {
        case .estimate(let estimate): return estimate.formattedTotal
        case .invoice(let invoice): return invoice.formattedTotal
        }
    }

    var fileName: String {
        "\(kind)-\(number).pdf"
    }

    func pdfData(
        client: Client?,
        renderImages: ProjectRenderImages? = nil,
        estimateMedia: [EstimateMediaAsset] = [],
        businessLogo: UIImage? = nil,
        businessDetails: BusinessProfileSettings? = nil
    ) -> Data {
        DocumentPDFRenderer.render(
            document: self,
            client: client,
            renderImages: renderImages,
            estimateMedia: estimateMedia,
            businessLogo: businessLogo,
            businessDetails: businessDetails
        )
    }
}

struct DocumentSendSheet: View {
    let document: OutgoingDocument
    let client: Client?
    var clientPortalURL: URL? = nil
    var renderImages: ProjectRenderImages? = nil
    var estimateMedia: [EstimateMediaAsset] = []
    var businessLogo: UIImage? = nil
    var businessDetails: BusinessProfileSettings? = nil
    let onSent: () -> Void
    var onEstimateSent: ((Estimate) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var activeChannel: SendChannel?
    @State private var unavailableMessage: String?
    @State private var appearance = EstimateAppearance()
    @State private var preparedPortalURL: URL?
    @State private var isPreparing = false
    @State private var didLoadAppearance = false
    @State private var previewData = Data()
    @State private var mediaLoadFailed = false
    @State private var loadedMedia: [EstimateMediaAsset] = []
    @State private var awaitingConfirmation = false

    private var previewMedia: [EstimateMediaAsset] { estimateMedia.isEmpty ? loadedMedia : estimateMedia }

    private var styledDocument: OutgoingDocument {
        if case .estimate(var estimate) = document {
            estimate.appearance = appearance
            return .estimate(estimate)
        }
        return document
    }

    private func refreshPreview() {
        previewData = styledDocument.pdfData(
            client: client, renderImages: renderImages, estimateMedia: previewMedia,
            businessLogo: businessLogo, businessDetails: businessDetails
        )
    }

    private let brandBlue = AppBrand.accent

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if case .estimate = document {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Business name", text: $appearance.businessName)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: appearance.businessName) { _, name in
                                if name.count > 120 { appearance.businessName = String(name.prefix(120)) }
                            }
                        HStack(spacing: 18) {
                            ForEach(EstimateAccent.allCases) { accent in
                                Button { appearance.accent = accent } label: {
                                    Circle().fill(Color(accent.uiColor)).frame(width: 30, height: 30)
                                        .overlay {
                                            if appearance.accent == accent {
                                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                            }
                                        }
                                }
                                .accessibilityLabel(accent.rawValue.capitalized)
                                .accessibilityAddTraits(appearance.accent == accent ? .isSelected : [])
                            }
                            Spacer()
                        }
                        Text("Your PDF and client portal use this style.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .disabled(awaitingConfirmation)
                }
                PDFDocumentView(data: previewData)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recipient")
                        .font(.system(size: 13))
                        .foregroundColor(AppGray.secondary)
                    Text(client?.name.isEmpty == false ? client!.name : "Add the recipient in Mail or Messages")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppGray.ink)
                    if let email = client?.email, !email.isEmpty {
                        Text(email)
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                    if let phone = client?.phone, !phone.isEmpty {
                        Text(phone)
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.048), radius: 6.4, x: 0, y: 1.6)

                if awaitingConfirmation {
                    sendButton(title: "Retry status sync", icon: "arrow.clockwise") { finishIfSent(true) }
                } else {
                    HStack(spacing: 12) {
                        sendButton(title: "Email", icon: "envelope.fill") {
                            beginSending(.email)
                        }
                        sendButton(title: "Text", icon: "message.fill") {
                            beginSending(.text)
                        }
                    }
                }
            }
            .disabled(isPreparing || mediaLoadFailed)
            .overlay { if isPreparing { ProgressView("Preparing…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .padding(16)
            .background(AppGray.bgPale.ignoresSafeArea())
            .navigationTitle("Preview & Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isPreparing)
                }
            }
        }
        .task {
            guard !didLoadAppearance else { return }
            if case .estimate(let estimate) = document {
                appearance = estimate.appearance ?? EstimateAppearance(
                    businessName: BusinessSettingsStore.shared.profile.businessName
                )
            }
            didLoadAppearance = true
            refreshPreview()
            if case .estimate(let estimate) = document,
               estimateMedia.isEmpty,
               let rawID = estimate.supabaseEstimateId, let id = UUID(uuidString: rawID) {
                isPreparing = true
                do {
                    let media = try await EstimateProposalRepository.loadMedia(estimateID: id)
                    var assets: [EstimateMediaAsset] = []
                    for record in media {
                        let data = try await EstimateProposalRepository.data(for: record)
                        assets.append(EstimateMediaAsset(id: record.id, kind: record.kind,
                            displayName: record.displayName, mimeType: record.mimeType, data: data))
                    }
                    loadedMedia = assets
                    refreshPreview()
                } catch {
                    mediaLoadFailed = true
                    unavailableMessage = "Couldn’t load the estimate’s photos and plans. Reopen this preview to try again."
                }
                isPreparing = false
            }
        }
        .onChange(of: appearance) { _, _ in refreshPreview() }
        .interactiveDismissDisabled(isPreparing)
        .sheet(item: $activeChannel) { channel in
            let payload = ComposerPayload(
                recipients: recipients(for: channel),
                subject: "\(document.kind) \(document.number) — \(document.title)",
                body: messageBody,
                attachment: styledDocument.pdfData(
                    client: client,
                    renderImages: renderImages,
                    estimateMedia: previewMedia,
                    businessLogo: businessLogo,
                    businessDetails: businessDetails
                ),
                fileName: document.fileName
            )

            switch channel {
            case .email:
                MailComposer(payload: payload) { sent in
                    activeChannel = nil
                    finishIfSent(sent)
                }
            case .text:
                MessageComposer(payload: payload) { sent in
                    activeChannel = nil
                    finishIfSent(sent)
                }
            }
        }
        .alert(
            "Can’t send",
            isPresented: Binding(
                get: { unavailableMessage != nil },
                set: { if !$0 { unavailableMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unavailableMessage ?? "")
        }
    }

    private var messageBody: String {
        let recipient = client?.name.isEmpty == false ? client!.name : "there"
        let reviewSection = (preparedPortalURL ?? clientPortalURL).map {
            """

            Review, request changes, or approve it here:
            \($0.absoluteString)
            """
        } ?? ""

        return """
        Hi \(recipient),

        Attached is \(document.kind.lowercased()) for \(document.title), totaling \(document.formattedTotal).\(reviewSection)

        Please let me know if you have any questions.
        """
    }

    private func recipients(for channel: SendChannel) -> [String] {
        switch channel {
        case .email:
            guard let email = client?.email, !email.isEmpty else { return [] }
            return [email]
        case .text:
            guard let phone = client?.phone, !phone.isEmpty else { return [] }
            return [phone]
        }
    }

    private func beginSending(_ channel: SendChannel) {
        switch channel {
        case .email:
            guard MFMailComposeViewController.canSendMail() else {
                unavailableMessage = "Mail isn’t configured on this device."
                return
            }
        case .text:
            guard MFMessageComposeViewController.canSendText() else {
                unavailableMessage = "Text messaging isn’t available on this device."
                return
            }
        }

        let placement: PremiumPlacement
        switch document {
        case .estimate:
            placement = .sendEstimate
        case .invoice:
            placement = .sendInvoice
        }

        SuperwallService.performPremiumAction(
            placement,
            params: ["source": "document_composer", "channel": channel.rawValue],
            onFailure: { unavailableMessage = $0 },
            action: {
                isPreparing = true
                Task {
                    do {
                        if case .estimate(let estimate) = styledDocument {
                            preparedPortalURL = try await EstimatePortalService.createReviewURL(for: estimate)
                        }
                        activeChannel = channel
                    } catch {
                        unavailableMessage = SafeErrorMessages.data(error, action: "estimate send")
                    }
                    isPreparing = false
                }
            }
        )
    }

    private func finishIfSent(_ sent: Bool) {
        guard sent else { return }
        awaitingConfirmation = true
        isPreparing = true
        Task {
            do {
                if case .estimate = document, let url = preparedPortalURL {
                    try await EstimatePortalService.confirmSent(reviewURL: url)
                }
                if case .estimate(let estimate) = styledDocument { onEstimateSent?(estimate) }
                onSent()
                dismiss()
            } catch {
                unavailableMessage = "Your message was sent, but the estimate status couldn’t sync. Please check your connection and refresh the project."
            }
            isPreparing = false
        }
    }

    private func sendButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(AppGray.ink)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DocumentPDFPreviewSheet: View {
    let document: OutgoingDocument
    let client: Client?
    var renderImages: ProjectRenderImages? = nil
    var estimateMedia: [EstimateMediaAsset] = []
    var businessLogo: UIImage? = nil
    var businessDetails: BusinessProfileSettings? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFDocumentView(data: document.pdfData(
                client: client,
                renderImages: renderImages,
                estimateMedia: estimateMedia,
                businessLogo: businessLogo,
                businessDetails: businessDetails
            ))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("\(document.kind) \(document.number)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(AppGray.bgPale)
        pdfView.document = PDFDocument(data: data)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.dataRepresentation() != data {
            pdfView.document = PDFDocument(data: data)
        }
    }
}

struct DocumentPagePreview: View {
    let data: Data

    private var pages: [UIImage] {
        guard let document = PDFDocument(data: data) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.thumbnail(
                of: CGSize(width: 1_224, height: 1_584),
                for: .mediaBox
            )
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                Image(uiImage: page)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(AppGray.border.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Invoice document preview")
    }
}

private enum SendChannel: String, Identifiable {
    case email
    case text

    var id: String { rawValue }
}

private struct ComposerPayload {
    let recipients: [String]
    let subject: String
    let body: String
    let attachment: Data
    let fileName: String
}

private struct MailComposer: UIViewControllerRepresentable {
    let payload: ComposerPayload
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients(payload.recipients)
        controller.setSubject(payload.subject)
        controller.setMessageBody(payload.body, isHTML: false)
        controller.addAttachmentData(
            payload.attachment,
            mimeType: "application/pdf",
            fileName: payload.fileName
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish(result == .sent && error == nil)
            }
        }
    }
}

private struct MessageComposer: UIViewControllerRepresentable {
    let payload: ComposerPayload
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.messageComposeDelegate = context.coordinator
        controller.recipients = payload.recipients
        controller.subject = payload.subject
        controller.body = payload.body
        if MFMessageComposeViewController.canSendAttachments() {
            controller.addAttachmentData(
                payload.attachment,
                typeIdentifier: "com.adobe.pdf",
                filename: payload.fileName
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            controller.dismiss(animated: true) {
                self.onFinish(result == .sent)
            }
        }
    }
}

private enum DocumentPDFRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 48

    static func render(
        document: OutgoingDocument,
        client: Client?,
        renderImages: ProjectRenderImages?,
        estimateMedia: [EstimateMediaAsset],
        businessLogo: UIImage?,
        businessDetails: BusinessProfileSettings?
    ) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            var writer = PDFWriter(
                context: context,
                client: client,
                businessLogo: businessLogo,
                businessDetails: businessDetails
            )
            switch document {
            case .estimate(let estimate):
                writer.drawEstimate(estimate, media: estimateMedia)
            case .invoice(let invoice):
                writer.drawInvoice(invoice, renderImages: invoice.includeRender ? renderImages : nil)
            }
        }
    }

    private struct PDFWriter {
        let context: UIGraphicsPDFRendererContext
        let client: Client?
        let businessLogo: UIImage?
        let businessDetails: BusinessProfileSettings?
        var y: CGFloat = margin
        var invoiceRowIndex = 0
        var estimateAppearance: EstimateAppearance?

        mutating func drawEstimate(_ estimate: Estimate, media: [EstimateMediaAsset]) {
            estimateAppearance = estimate.appearance
            beginDocument(kind: "ESTIMATE", number: estimate.estimateNumber, title: estimate.title)
            drawEstimateFinalTotal(estimate.total)
            drawEstimatePlan(estimate.workPlan ?? [])
            drawEstimateMedia(media)
            if let notes = estimate.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                drawEstimateTextCard(title: "NOTES", body: notes)
            }
            if let terms = estimate.paymentTerms, !terms.isEmpty {
                drawEstimateTextCard(title: "PAYMENT TERMS", body: terms)
            }
        }

        mutating func drawInvoice(_ invoice: Invoice, renderImages: ProjectRenderImages?) {
            beginInvoicePage(invoice)
            drawInvoiceSummary(invoice)
            drawInvoiceTableHeader()
            for item in invoice.items {
                drawInvoiceLineItem(item, invoice: invoice)
            }
            drawInvoiceTotals(invoice)
            drawInvoiceNotesAndPayment(invoice)
            drawInvoiceDisclaimer(invoice)
            if let renderImages {
                drawInvoiceRenderImages(renderImages, invoice: invoice)
            }
        }

        mutating func beginInvoicePage(_ invoice: Invoice, continuation: Bool = false) {
            context.beginPage()
            y = 0
            if continuation {
                y = 42
                return
            }
            y = 54
        }

        mutating func drawInvoiceSummary(_ invoice: Invoice) {
            let top = y + 8
            let firstX = margin
            let company = invoice.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let clientLabelY = company.isEmpty ? top : top + 22
            let clientNameY = clientLabelY + 22
            let clientDetailsY = clientNameY + 21
            if company.isEmpty {
                drawLabel("CLIENT", x: firstX, y: top, width: 220)
            } else {
                drawLabel(company, x: firstX, y: top, width: 245)
                drawLabel("CLIENT", x: firstX, y: clientLabelY, width: 220)
            }
            if let client {
                draw(client.name.isEmpty ? "Client" : client.name, in: CGRect(x: firstX, y: clientNameY, width: 230, height: 18), size: 11.5, weight: .semibold)
                let details = [client.company, client.address].filter { !$0.isEmpty }
                draw(details.joined(separator: "\n"), in: CGRect(x: firstX, y: clientDetailsY, width: 235, height: 38), size: 9.5, color: .secondaryLabel)
            } else {
                draw("Client not selected", in: CGRect(x: firstX, y: clientNameY, width: 230, height: 18), size: 10.5, color: .secondaryLabel)
            }

            let titleY = company.isEmpty ? top + 84 : top + 106
            draw(invoice.title.isEmpty ? "Project" : invoice.title, in: CGRect(x: firstX, y: titleY, width: 245, height: 28), size: 15, weight: .semibold)

            let metaX: CGFloat = 310
            let metaWidth: CGFloat = 260
            context.cgContext.setFillColor(invoiceBlue.cgColor)
            context.cgContext.fill(CGRect(x: metaX, y: top, width: metaWidth, height: 31))
            draw("INVOICE #\(invoice.invoiceNumber)", in: CGRect(x: metaX + 10, y: top + 9, width: metaWidth - 20, height: 15), size: 8.5, weight: .bold, color: .white)
            draw("Issued", in: CGRect(x: metaX + 10, y: top + 44, width: 70, height: 16), size: 8.5, color: .secondaryLabel)
            draw(formattedDate(invoice.createdAt), in: CGRect(x: metaX + 105, y: top + 44, width: 145, height: 16), size: 8.5, alignment: .right)
            drawThinRule(from: CGPoint(x: metaX, y: top + 67), to: CGPoint(x: metaX + metaWidth, y: top + 67))
            draw("Due", in: CGRect(x: metaX + 10, y: top + 77, width: 70, height: 16), size: 8.5, color: .secondaryLabel)
            let due = invoice.dueAt.map(formattedDate) ?? invoice.dueDate
            draw(due, in: CGRect(x: metaX + 105, y: top + 77, width: 145, height: 16), size: 8.5, alignment: .right)

            y = top + (company.isEmpty ? 120 : 142)
        }

        mutating func drawInvoiceNotesAndPayment(_ invoice: Invoice) {
            let hasNotes = !InvoiceRichText.isEmpty(invoice.description)
            let hasPayment = !invoice.paymentMethods.isEmpty
            guard hasNotes || hasPayment else { return }

            let gap: CGFloat = 12
            let boxWidth = (pageRect.width - margin * 2 - gap) / 2
            var notesSource: NSMutableAttributedString?
            var notesBodyHeight: CGFloat = 0
            if hasNotes {
                let source = NSMutableAttributedString(attributedString: InvoiceRichText.attributedString(from: invoice.description, fontSize: 10.5))
                source.addAttribute(
                    .foregroundColor,
                    value: UIColor(red: 0.24, green: 0.26, blue: 0.29, alpha: 1),
                    range: NSRange(location: 0, length: source.length)
                )
                let measured = source.boundingRect(
                    with: CGSize(width: boxWidth - 20, height: 130),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                notesBodyHeight = min(ceil(measured.height), 120)
                notesSource = source
            }

            let paymentBodyHeight = hasPayment ? CGFloat(invoice.paymentMethods.count * 15) : 0
            let boxHeight = max(48, max(notesBodyHeight, paymentBodyHeight) + 32)
            ensureInvoiceSpace(boxHeight + 18, invoice: invoice)
            let boxY = y + 8

            if let notesSource {
                let box = CGRect(x: margin, y: boxY, width: boxWidth, height: boxHeight)
                context.cgContext.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                context.cgContext.fill(box)
                draw("NOTES", in: CGRect(x: box.minX + 10, y: box.minY + 9, width: 120, height: 16), size: 9.5, weight: .bold, color: .secondaryLabel)
                notesSource.draw(
                    with: CGRect(x: box.minX + 10, y: box.minY + 26, width: box.width - 20, height: box.height - 30),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
            }

            if hasPayment {
                let boxX = hasNotes ? margin + boxWidth + gap : margin
                let box = CGRect(x: boxX, y: boxY, width: boxWidth, height: boxHeight)
                context.cgContext.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
                context.cgContext.fill(box)
                let body = invoice.paymentMethods.map { method in
                    method.details.isEmpty ? method.name : "\(method.name)  |  \(method.details)"
                }.joined(separator: "\n")
                draw("PAYMENT METHODS", in: CGRect(x: box.minX + 10, y: box.minY + 9, width: 160, height: 16), size: 9.5, weight: .bold, color: .secondaryLabel)
                draw(body, in: CGRect(x: box.minX + 10, y: box.minY + 26, width: box.width - 20, height: box.height - 30), size: 9.2, color: .secondaryLabel)
            }

            y = boxY + boxHeight + 10
        }

        mutating func drawInvoiceDescription(_ invoice: Invoice) {
            guard !InvoiceRichText.isEmpty(invoice.description) else { return }
            ensureInvoiceSpace(96, invoice: invoice)
            let source = NSMutableAttributedString(attributedString: InvoiceRichText.attributedString(from: invoice.description, fontSize: 10.5))
            let fullRange = NSRange(location: 0, length: source.length)
            source.addAttribute(.foregroundColor, value: UIColor(red: 0.24, green: 0.26, blue: 0.29, alpha: 1), range: fullRange)
            let availableWidth: CGFloat = 260
            let measured = source.boundingRect(
                with: CGSize(width: availableWidth, height: 130),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let height = min(ceil(measured.height), 120)
            let box = CGRect(x: margin, y: y + 8, width: availableWidth, height: height + 32)
            context.cgContext.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
            context.cgContext.fill(box)
            draw("NOTES", in: CGRect(x: box.minX + 10, y: box.minY + 9, width: 120, height: 16), size: 9.5, weight: .bold, color: .secondaryLabel)
            source.draw(
                with: CGRect(x: box.minX + 10, y: box.minY + 26, width: availableWidth - 20, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            y = box.maxY + 10
        }

        mutating func drawInvoicePaymentMethods(_ invoice: Invoice) {
            guard !invoice.paymentMethods.isEmpty else { return }
            ensureInvoiceSpace(72, invoice: invoice)
            let body = invoice.paymentMethods.map { method in
                method.details.isEmpty ? method.name : "\(method.name)  |  \(method.details)"
            }.joined(separator: "\n")
            let height = max(48, CGFloat(invoice.paymentMethods.count * 15 + 31))
            let box = CGRect(x: margin, y: y, width: 260, height: height)
            context.cgContext.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
            context.cgContext.fill(box)
            draw("PAYMENT METHODS", in: CGRect(x: box.minX + 10, y: box.minY + 9, width: 160, height: 16), size: 9.5, weight: .bold, color: .secondaryLabel)
            draw(body, in: CGRect(x: box.minX + 10, y: box.minY + 26, width: box.width - 20, height: box.height - 30), size: 9.2, color: .secondaryLabel)
            y = box.maxY + 10
        }

        mutating func drawInvoiceAttachments(_ invoice: Invoice) {
            guard !invoice.attachments.isEmpty else { return }
            ensureInvoiceSpace(52, invoice: invoice)
            draw("ATTACHMENTS", in: CGRect(x: margin, y: y, width: 120, height: 16), size: 9.5, weight: .bold, color: .secondaryLabel)
            draw(invoice.attachments.joined(separator: ", "), in: CGRect(x: margin, y: y + 18, width: pageRect.width - margin * 2, height: 32), size: 9, color: .secondaryLabel)
            y += 52
        }

        mutating func drawInvoiceDisclaimer(_ invoice: Invoice) {
            guard !invoice.disclaimer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            ensureInvoiceSpace(82, invoice: invoice)
            let box = CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: 72)
            context.cgContext.setFillColor(UIColor(white: 0.97, alpha: 1).cgColor)
            context.cgContext.fill(box)
            draw("DISCLAIMER", in: CGRect(x: box.minX + 10, y: box.minY + 9, width: 140, height: 16), size: 9.5, weight: .bold, color: .secondaryLabel)
            draw(invoice.disclaimer, in: CGRect(x: box.minX + 10, y: box.minY + 27, width: box.width - 20, height: 38), size: 9.5, color: .secondaryLabel)
            y = box.maxY + 10
        }

        mutating func drawInvoiceRenderImages(_ images: ProjectRenderImages, invoice: Invoice) {
            ensureInvoiceSpace(215, invoice: invoice)
            y += 22
            drawSectionHeading("PROJECT VISUALIZATION")

            let gap: CGFloat = 12
            let width = (pageRect.width - (margin * 2) - gap) / 2
            let imageHeight: CGFloat = 158
            let beforeRect = CGRect(x: margin, y: y, width: width, height: imageHeight)
            let afterRect = CGRect(x: margin + width + gap, y: y, width: width, height: imageHeight)
            drawImageCard(images.before, in: beforeRect, label: "BEFORE")
            drawImageCard(images.after, in: afterRect, label: "AFTER")
            y = beforeRect.maxY + 22
        }

        mutating func drawInvoiceTableHeader() {
            let rect = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: 31)
            context.cgContext.setFillColor(invoiceBlue.cgColor)
            context.cgContext.fill(rect)
            draw("DESCRIPTION", in: CGRect(x: margin + 10, y: y + 9, width: 250, height: 15), size: 8.5, weight: .bold, color: .white)
            draw("QTY", in: CGRect(x: 315, y: y + 9, width: 44, height: 15), size: 8.5, weight: .bold, color: .white, alignment: .right)
            draw("UNIT PRICE", in: CGRect(x: 365, y: y + 9, width: 82, height: 15), size: 8.5, weight: .bold, color: .white, alignment: .right)
            draw("TOTAL", in: CGRect(x: 452, y: y + 9, width: 105, height: 15), size: 8.5, weight: .bold, color: .white, alignment: .right)
            y = rect.maxY + 3
        }

        mutating func drawInvoiceLineItem(_ item: InvoiceLineItem, invoice: Invoice) {
            let titleHeight = max(17, ceil((item.title as NSString).boundingRect(
                with: CGSize(width: 245, height: 40),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: 10.5, weight: .semibold)],
                context: nil
            ).height))
            let rowHeight = max(42, titleHeight + 22)
            if y + rowHeight > pageRect.height - margin {
                beginInvoicePage(invoice, continuation: true)
                drawInvoiceTableHeader()
            }

            if invoiceRowIndex.isMultiple(of: 2) == false {
                context.cgContext.setFillColor(UIColor(white: 0.965, alpha: 1).cgColor)
                context.cgContext.fill(CGRect(x: margin, y: y, width: pageRect.width - margin * 2, height: rowHeight))
            }

            draw(item.title, in: CGRect(x: margin + 10, y: y + 9, width: 248, height: titleHeight + 2), size: 10.5, weight: .medium)
            draw(item.unit, in: CGRect(x: margin + 10, y: y + titleHeight + 11, width: 150, height: 14), size: 8.5, color: .secondaryLabel)
            draw(quantity(item.quantity), in: CGRect(x: 315, y: y + 14, width: 44, height: 17), size: 10, alignment: .right)
            draw(currency(item.unitPrice), in: CGRect(x: 365, y: y + 14, width: 82, height: 17), size: 10, alignment: .right)
            draw(currency(item.total), in: CGRect(x: 452, y: y + 14, width: 105, height: 17), size: 10, weight: .semibold, alignment: .right)
            y += rowHeight
            context.cgContext.setStrokeColor(UIColor.systemGray5.cgColor)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            context.cgContext.strokePath()
            invoiceRowIndex += 1
        }

        mutating func drawInvoiceTotals(_ invoice: Invoice) {
            let adjustmentRows = (invoice.discountAmount > 0 ? 1 : 0) + (invoice.taxAmount > 0 ? 1 : 0)
            let height = CGFloat(80 + (adjustmentRows * 22))
            ensureInvoiceSpace(height + 26, invoice: invoice)
            y += 14
            var rowY = y
            drawInvoiceAmountRow("Subtotal", value: invoice.formattedSubtotal, y: rowY)
            rowY += 22
            if invoice.discountAmount > 0 {
                drawInvoiceAmountRow("Discount", value: "−\(currency(invoice.discountAmount))", y: rowY)
                rowY += 22
            }
            if invoice.taxAmount > 0 {
                drawInvoiceAmountRow("Tax (\(percentage(invoice.taxPercent)))", value: currency(invoice.taxAmount), y: rowY)
                rowY += 22
            }
            context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
            context.cgContext.setLineWidth(1)
            context.cgContext.move(to: CGPoint(x: 340, y: rowY + 2))
            context.cgContext.addLine(to: CGPoint(x: 552, y: rowY + 2))
            context.cgContext.strokePath()
            rowY += 13
            drawInvoiceAmountRow("TOTAL", value: invoice.formattedTotal, y: rowY, bold: true)
            y = rowY + 24
        }

        mutating func drawInvoiceTerms(_ terms: String, invoice: Invoice) {
            ensureInvoiceSpace(90, invoice: invoice)
            y += 24
            drawSectionHeading("TERMS & CONDITIONS")
            let bodyRect = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: min(72, pageRect.height - margin - y))
            draw(terms, in: bodyRect, size: 9.5, color: UIColor(red: 0.28, green: 0.30, blue: 0.33, alpha: 1))
            y = bodyRect.maxY
        }

        mutating func ensureInvoiceSpace(_ height: CGFloat, invoice: Invoice) {
            guard y + height > pageRect.height - margin else { return }
            beginInvoicePage(invoice, continuation: true)
        }

        func drawInvoiceAmountRow(_ label: String, value: String, y: CGFloat, bold: Bool = false) {
            draw(label, in: CGRect(x: 340, y: y, width: 100, height: 18), size: bold ? 12 : 10, weight: bold ? .bold : .regular, color: bold ? .label : .secondaryLabel)
            draw(value, in: CGRect(x: 444, y: y, width: 108, height: 18), size: bold ? 13 : 10, weight: bold ? .bold : .semibold, alignment: .right)
        }

        func drawLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) {
            draw(text, in: CGRect(x: x, y: y, width: width, height: 15), size: 8.5, weight: .bold, color: invoiceBlue)
        }

        var invoiceBlue: UIColor {
            if let estimateAppearance { return estimateAppearance.accent.uiColor }
            return UIColor(AppBrand.accent)
        }

        mutating func drawSectionHeading(_ text: String) {
            draw(text, in: CGRect(x: margin, y: y, width: 270, height: 16), size: 9.5, weight: .bold, color: invoiceBlue)
            y += 18
            context.cgContext.setStrokeColor(invoiceBlue.cgColor)
            context.cgContext.setLineWidth(1.2)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            context.cgContext.strokePath()
            y += 10
        }

        mutating func drawDocumentRule() {
            context.cgContext.setStrokeColor(UIColor.systemGray3.cgColor)
            context.cgContext.setLineWidth(0.65)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            context.cgContext.strokePath()
            y += 10
        }

        func drawThinRule(from start: CGPoint, to end: CGPoint) {
            context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
            context.cgContext.setLineWidth(0.6)
            context.cgContext.move(to: start)
            context.cgContext.addLine(to: end)
            context.cgContext.strokePath()
        }

        func fillRoundedRect(_ rect: CGRect, color: UIColor, radius: CGFloat) {
            color.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        }

        func drawImageCard(_ image: UIImage, in rect: CGRect, label: String) {
            context.cgContext.saveGState()
            UIBezierPath(roundedRect: rect, cornerRadius: 3).addClip()
            UIColor.systemGray6.setFill()
            UIRectFill(rect)
            image.draw(in: aspectFillRect(imageSize: image.size, in: rect))
            context.cgContext.restoreGState()

            let labelRect = CGRect(x: rect.minX + 9, y: rect.maxY - 29, width: 58, height: 20)
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.12).cgColor)
            fillRoundedRect(labelRect, color: .white, radius: 3)
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            context.cgContext.setStrokeColor(UIColor.systemGray4.cgColor)
            context.cgContext.setLineWidth(0.6)
            UIBezierPath(roundedRect: labelRect, cornerRadius: 3).stroke()
            draw(label, in: CGRect(x: labelRect.minX, y: labelRect.minY + 5.5, width: labelRect.width, height: 11), size: 7.5, weight: .bold, color: invoiceBlue, alignment: .center)
        }

        func formattedDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }

        mutating func beginDocument(kind: String, number: String, title: String) {
            context.beginPage()
            y = margin
            if let businessLogo {
                let target = aspectFitRect(
                    imageSize: businessLogo.size,
                    in: CGRect(x: margin, y: y, width: 150, height: 52)
                )
                businessLogo.draw(in: target)
                y += 64
            }
            if let name = estimateAppearance?.businessName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                drawText(name, size: 14, weight: .semibold)
                y += 12
            }
            drawText(kind, size: 12, weight: .semibold, color: invoiceBlue)
            drawText(title.isEmpty ? kind.capitalized : title, size: 24, weight: .bold, top: 8)
            drawText(number, size: 12, color: .secondaryLabel, top: 6)

            if let client {
                y += 18
                drawText("BILL TO", size: 10, weight: .semibold, color: .secondaryLabel)
                drawText(client.name, size: 13, weight: .semibold, top: 5)
                if !client.company.isEmpty { drawText(client.company, size: 11, color: .secondaryLabel, top: 3) }
                if !client.email.isEmpty { drawText(client.email, size: 11, color: .secondaryLabel, top: 3) }
                if !client.phone.isEmpty { drawText(client.phone, size: 11, color: .secondaryLabel, top: 3) }
            }

            y += 18
            drawRule()
        }

        mutating func drawEstimateSectionTitle(_ title: String) {
            ensureSpace(40)
            y += 8
            draw(title, in: CGRect(x: margin, y: y, width: 220, height: 18), size: 10, weight: .bold, color: invoiceBlue)
            y += 22
            context.cgContext.setStrokeColor(invoiceBlue.cgColor)
            context.cgContext.setLineWidth(1.1)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            context.cgContext.strokePath()
            y += 13
        }

        mutating func drawEstimateFinalTotal(_ total: Double) {
            drawEstimateSectionTitle("ESTIMATE TOTAL")
            ensureSpace(78)
            let card = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: 70)
            fillRoundedRect(card, color: UIColor(white: 0.965, alpha: 1), radius: 5)
            draw(
                "Final estimate",
                in: CGRect(x: card.minX + 16, y: card.minY + 15, width: 180, height: 18),
                size: 10.5,
                weight: .semibold,
                color: UIColor.secondaryLabel
            )
            draw(
                currency(total),
                in: CGRect(x: card.minX + 190, y: card.minY + 13, width: card.width - 206, height: 34),
                size: 22,
                weight: .bold,
                alignment: .right
            )
            draw(
                "The project plan, notes, and supporting visuals are included below.",
                in: CGRect(x: card.minX + 16, y: card.minY + 42, width: card.width - 32, height: 16),
                size: 9.5,
                color: UIColor.secondaryLabel
            )
            y = card.maxY + 14
        }

        mutating func drawEstimatePlan(_ sections: [EstimatePlanSection]) {
            guard !sections.isEmpty else { return }
            drawEstimateSectionTitle("PROJECT PLAN")

            for (index, section) in sections.enumerated() {
                let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let steps = section.steps
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !title.isEmpty, !steps.isEmpty else { continue }

                let titleHeight = measuredTextHeight(title, width: pageRect.width - (margin * 2) - 38, size: 13, weight: .semibold)
                let stepHeights = steps.map {
                    measuredTextHeight($0, width: pageRect.width - (margin * 2) - 48, size: 10.5, weight: .regular)
                }
                let cardHeight = 20 + titleHeight + stepHeights.reduce(0) { $0 + max(18, $1) + 10 } + 12

                if cardHeight <= pageRect.height - (margin * 2) {
                    ensureSpace(cardHeight + 12)
                    let card = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: cardHeight)
                    fillRoundedRect(card, color: UIColor(white: 0.965, alpha: 1), radius: 5)
                    draw(
                        "\(index + 1).  \(title)",
                        in: CGRect(x: card.minX + 16, y: card.minY + 14, width: card.width - 32, height: titleHeight + 3),
                        size: 13,
                        weight: .semibold
                    )
                    var stepY = card.minY + 20 + titleHeight
                    for (step, height) in zip(steps, stepHeights) {
                        draw("•", in: CGRect(x: card.minX + 17, y: stepY, width: 12, height: 18), size: 11, weight: .bold, color: invoiceBlue)
                        draw(step, in: CGRect(x: card.minX + 34, y: stepY, width: card.width - 50, height: height + 3), size: 10.5, color: UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1))
                        stepY += max(18, height) + 10
                    }
                    y = card.maxY + 12
                } else {
                    drawLongEstimatePlanSection(number: index + 1, title: title, steps: steps)
                }
            }
        }

        mutating func drawLongEstimatePlanSection(number: Int, title: String, steps: [String]) {
            let titleHeight = measuredTextHeight(title, width: pageRect.width - (margin * 2) - 32, size: 13, weight: .semibold)
            ensureSpace(titleHeight + 38)
            let header = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: titleHeight + 26)
            fillRoundedRect(header, color: UIColor(white: 0.965, alpha: 1), radius: 5)
            draw("\(number).  \(title)", in: header.insetBy(dx: 16, dy: 12), size: 13, weight: .semibold)
            y = header.maxY + 4

            for step in steps {
                let height = measuredTextHeight(step, width: pageRect.width - (margin * 2) - 48, size: 10.5, weight: .regular)
                ensureSpace(height + 18)
                let row = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: height + 14)
                context.cgContext.setFillColor(UIColor(white: 0.98, alpha: 1).cgColor)
                context.cgContext.fill(row)
                draw("•", in: CGRect(x: row.minX + 17, y: row.minY + 7, width: 12, height: 18), size: 11, weight: .bold, color: invoiceBlue)
                draw(step, in: CGRect(x: row.minX + 34, y: row.minY + 7, width: row.width - 50, height: height + 3), size: 10.5, color: UIColor(red: 0.18, green: 0.19, blue: 0.22, alpha: 1))
                y = row.maxY + 4
            }
            y += 8
        }

        mutating func drawEstimateMedia(_ media: [EstimateMediaAsset]) {
            let visible = media.compactMap { asset -> (EstimateMediaAsset, UIImage)? in
                guard let image = asset.previewImage else { return nil }
                return (asset, image)
            }
            guard !visible.isEmpty else { return }

            // Keep the heading with at least the first visual instead of
            // stranding it at the bottom of the previous page.
            ensureSpace(250)
            drawEstimateSectionTitle("PHOTOS & PLANS")
            let gap: CGFloat = 12
            let width = (pageRect.width - (margin * 2) - gap) / 2
            let imageHeight: CGFloat = 166
            let rowHeight: CGFloat = 204

            for rowStart in stride(from: 0, to: visible.count, by: 2) {
                ensureSpace(rowHeight)
                for column in 0..<2 where rowStart + column < visible.count {
                    let (asset, image) = visible[rowStart + column]
                    let x = margin + CGFloat(column) * (width + gap)
                    let imageRect = CGRect(x: x, y: y, width: width, height: imageHeight)
                    fillRoundedRect(imageRect, color: UIColor.systemGray6, radius: 4)
                    context.cgContext.saveGState()
                    UIBezierPath(roundedRect: imageRect, cornerRadius: 4).addClip()
                    image.draw(in: aspectFitRect(imageSize: image.size, in: imageRect.insetBy(dx: 4, dy: 4)))
                    context.cgContext.restoreGState()
                    let kind = asset.kind == "floorplan" ? "FLOOR PLAN" : asset.kind.uppercased()
                    draw(kind, in: CGRect(x: x, y: imageRect.maxY + 7, width: width, height: 12), size: 8, weight: .bold, color: invoiceBlue)
                    draw(asset.displayName, in: CGRect(x: x, y: imageRect.maxY + 20, width: width, height: 15), size: 9, color: .secondaryLabel)
                }
                y += rowHeight
            }
        }

        mutating func drawEstimateTextCard(title: String, body: String) {
            let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanBody.isEmpty else { return }
            let paragraphs = cleanBody.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if let first = paragraphs.first {
                let firstHeight = measuredTextHeight(first, width: pageRect.width - (margin * 2) - 28, size: 10.5, weight: .regular)
                ensureSpace(firstHeight + 78)
            }
            drawEstimateSectionTitle(title)
            for paragraph in paragraphs {
                let height = measuredTextHeight(paragraph, width: pageRect.width - (margin * 2) - 28, size: 10.5, weight: .regular)
                ensureSpace(height + 26)
                let box = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: height + 22)
                fillRoundedRect(box, color: UIColor(white: 0.97, alpha: 1), radius: 5)
                draw(paragraph, in: box.insetBy(dx: 14, dy: 10), size: 10.5, color: UIColor(red: 0.22, green: 0.23, blue: 0.26, alpha: 1))
                y = box.maxY + 8
            }
        }

        func measuredTextHeight(_ text: String, width: CGFloat, size: CGFloat, weight: UIFont.Weight) -> CGFloat {
            ceil((text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)],
                context: nil
            ).height)
        }

        mutating func drawRenderImages(_ images: ProjectRenderImages) {
            ensureSpace(220)
            drawText("PROJECT VISUALIZATION", size: 10, weight: .semibold, color: .secondaryLabel)
            let gap: CGFloat = 12
            let width = (pageRect.width - (margin * 2) - gap) / 2
            let imageHeight: CGFloat = 150
            let beforeRect = CGRect(x: margin, y: y + 8, width: width, height: imageHeight)
            let afterRect = CGRect(x: margin + width + gap, y: y + 8, width: width, height: imageHeight)

            UIColor.systemGray6.setFill()
            UIBezierPath(roundedRect: beforeRect, cornerRadius: 8).fill()
            UIBezierPath(roundedRect: afterRect, cornerRadius: 8).fill()
            images.before.draw(in: aspectFitRect(imageSize: images.before.size, in: beforeRect.insetBy(dx: 4, dy: 4)))
            images.after.draw(in: aspectFitRect(imageSize: images.after.size, in: afterRect.insetBy(dx: 4, dy: 4)))

            draw("BEFORE", in: CGRect(x: beforeRect.minX, y: beforeRect.maxY + 5, width: width, height: 16), size: 9, weight: .semibold, color: .secondaryLabel)
            draw("AFTER", in: CGRect(x: afterRect.minX, y: afterRect.maxY + 5, width: width, height: 16), size: 9, weight: .semibold, color: .secondaryLabel)
            y = beforeRect.maxY + 32
            drawRule(color: UIColor.systemGray5)
        }

        mutating func drawLineItem(title: String, detail: String, total: String) {
            ensureSpace(52)
            let titleRect = CGRect(x: margin, y: y, width: 360, height: 20)
            draw(title, in: titleRect, size: 11, weight: .medium)
            let totalRect = CGRect(x: pageRect.width - margin - 100, y: y, width: 100, height: 20)
            draw(total, in: totalRect, size: 11, weight: .semibold, alignment: .right)
            y += 19
            drawText(detail, size: 9, color: .secondaryLabel)
            y += 9
            drawRule(color: UIColor.systemGray5)
        }

        mutating func drawTotals(
            subtotal: Double,
            adjustments: [(String, Double)],
            total: Double
        ) {
            ensureSpace(130)
            y += 10
            drawAmountRow("Subtotal", amount: subtotal)
            for (label, amount) in adjustments where abs(amount) > 0.005 {
                drawAmountRow(label, amount: amount)
            }
            y += 4
            drawRule()
            y += 8
            drawAmountRow("Total", amount: total, bold: true)
        }

        mutating func drawAmountRow(_ label: String, amount: Double, bold: Bool = false) {
            let weight: UIFont.Weight = bold ? .bold : .regular
            let left = CGRect(x: pageRect.width - margin - 220, y: y, width: 110, height: 20)
            let right = CGRect(x: pageRect.width - margin - 110, y: y, width: 110, height: 20)
            draw(label, in: left, size: bold ? 13 : 11, weight: weight)
            draw(currency(amount), in: right, size: bold ? 13 : 11, weight: weight, alignment: .right)
            y += 24
        }

        mutating func drawFooter(title: String, body: String) {
            ensureSpace(90)
            y += 22
            drawText(title.uppercased(), size: 10, weight: .semibold, color: .secondaryLabel)
            let rect = CGRect(x: margin, y: y + 6, width: pageRect.width - (margin * 2), height: 58)
            draw(body, in: rect, size: 10)
            y += 68
        }

        mutating func ensureSpace(_ height: CGFloat) {
            guard y + height > pageRect.height - margin else { return }
            context.beginPage()
            y = margin
        }

        mutating func drawRule(color: UIColor = UIColor.systemGray3) {
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(0.7)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            context.cgContext.strokePath()
            y += 12
        }

        mutating func drawText(
            _ text: String,
            size: CGFloat,
            weight: UIFont.Weight = .regular,
            color: UIColor = .label,
            top: CGFloat = 0
        ) {
            y += top
            let rect = CGRect(x: margin, y: y, width: pageRect.width - (margin * 2), height: size * 1.6)
            draw(text, in: rect, size: size, weight: weight, color: color)
            y += size * 1.6
        }

        func draw(
            _ text: String,
            in rect: CGRect,
            size: CGFloat,
            weight: UIFont.Weight = .regular,
            color: UIColor = .label,
            alignment: NSTextAlignment = .left
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = alignment
            (text as NSString).draw(
                in: rect,
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: size, weight: weight),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
            )
        }

        func currency(_ value: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
        }

        func quantity(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }

        func percentage(_ value: Double) -> String {
            value == value.rounded() ? "\(Int(value))%" : String(format: "%.2f%%", value)
        }

        func aspectFitRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
            guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
            let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        func aspectFillRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
            guard imageSize.width > 0, imageSize.height > 0 else { return bounds }
            let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
            let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            return CGRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }

        func croppedToVisibleContent(_ image: UIImage) -> UIImage {
            guard let source = image.cgImage else { return image }
            let sampleLimit = 512
            let scale = min(1, CGFloat(sampleLimit) / CGFloat(max(source.width, source.height)))
            let sampleWidth = max(1, Int(CGFloat(source.width) * scale))
            let sampleHeight = max(1, Int(CGFloat(source.height) * scale))
            let bytesPerRow = sampleWidth * 4
            var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let bitmap = CGContext(
                      data: &pixels,
                      width: sampleWidth,
                      height: sampleHeight,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return image }
            bitmap.interpolationQuality = .medium
            bitmap.draw(source, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

            var minX = sampleWidth
            var minY = sampleHeight
            var maxX = -1
            var maxY = -1
            for row in 0..<sampleHeight {
                for column in 0..<sampleWidth {
                    let offset = (row * bytesPerRow) + (column * 4)
                    let red = pixels[offset]
                    let green = pixels[offset + 1]
                    let blue = pixels[offset + 2]
                    let alpha = pixels[offset + 3]
                    let visible = alpha > 24 && (red < 242 || green < 242 || blue < 242)
                    if visible {
                        minX = min(minX, column)
                        minY = min(minY, row)
                        maxX = max(maxX, column)
                        maxY = max(maxY, row)
                    }
                }
            }
            guard maxX >= minX, maxY >= minY else { return image }

            let padding = max(3, Int(CGFloat(max(maxX - minX, maxY - minY)) * 0.06))
            minX = max(0, minX - padding)
            minY = max(0, minY - padding)
            maxX = min(sampleWidth - 1, maxX + padding)
            maxY = min(sampleHeight - 1, maxY + padding)

            let inverseScale = 1 / scale
            let cropRect = CGRect(
                x: CGFloat(minX) * inverseScale,
                y: CGFloat(minY) * inverseScale,
                width: CGFloat(maxX - minX + 1) * inverseScale,
                height: CGFloat(maxY - minY + 1) * inverseScale
            ).integral.intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
            guard cropRect.width > 1, cropRect.height > 1,
                  let cropped = source.cropping(to: cropRect) else { return image }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
        }
    }
}


extension EstimateAccent {
    var uiColor: UIColor {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x285C9B
        return UIColor(red: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
