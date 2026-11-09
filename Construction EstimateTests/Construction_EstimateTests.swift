//
//  Construction_EstimateTests.swift
//  Construction EstimateTests
//
//

import Foundation
import Testing
import PDFKit
import UIKit
import SwiftUI
@testable import Construction_Estimate

struct Construction_EstimateTests {
    private struct ProviderError: Error, CustomStringConvertible {
        let description: String
    }

    private func makeEstimate(
        categories: [EstimateCategory],
        subtotal: Double,
        markupPercent: Double = 0,
        markupAmount: Double = 0,
        total: Double,
        contingency: ContingencyInfo? = nil
    ) -> Estimate {
        Estimate(
            estimateNumber: "EST-10001",
            title: "Kitchen update",
            categories: categories,
            subtotal: subtotal,
            markupPercent: markupPercent,
            markupAmount: markupAmount,
            total: total,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            chatSessionId: UUID(uuidString: "A20E6F3D-2C07-4473-9B60-1854D75B848A")!,
            siteConditions: nil,
            permitInfo: nil,
            contingency: contingency,
            toolRental: nil,
            wasteFactors: nil,
            exclusions: ["Permit fees"],
            paymentTerms: "Due on completion",
            sanityCheckNote: nil,
            crossReferenceNotes: nil
        )
    }

    private func makeProjectRender(
        id: UUID = UUID(),
        projectID: UUID,
        currentImagePath: String,
        prompt: String = "Replace the cabinets",
        status: String = "draft",
        acceptedImagePath: String? = nil
    ) -> ProjectRender {
        ProjectRender(
            id: id,
            organizationId: UUID(),
            projectId: projectID,
            originalImagePath: "before.jpg",
            currentImagePath: currentImagePath,
            acceptedImagePath: acceptedImagePath,
            initialPrompt: prompt,
            status: status,
            createdBy: UUID(),
            createdAt: "2026-08-13T00:00:00Z",
            updatedAt: "2026-08-13T00:00:00Z",
            acceptedAt: status == "accepted" ? "2026-08-13T00:01:00Z" : nil
        )
    }

    @Test func passwordRulesRequireLengthLettersAndNumbers() {
        #expect(!PasswordRules.isValid("short1"))
        #expect(!PasswordRules.isValid("onlyletters"))
        #expect(!PasswordRules.isValid("12345678"))
        #expect(PasswordRules.isValid("secure123"))
    }

    @Test func newBlankInvoiceHasNoPremadeLineItems() {
        let invoice = Invoice.createNew(number: 1)
        #expect(invoice.items.isEmpty)
        #expect(invoice.total == 0)
    }

    @Test func newBusinessProfileDoesNotAssumeAccountName() {
        #expect(BusinessProfileSettings().businessName.isEmpty)
    }

    @Test func authenticationErrorsNeverExposeProviderDetails() {
        let secretDetail = "database timeout: internal-project-ref service_role"
        let message = SafeErrorMessages.authentication(
            ProviderError(description: secretDetail),
            operation: .signIn
        )

        #expect(message == "Sign in couldn't be completed. Please try again.")
        #expect(!message.contains(secretDetail))
        #expect(!message.contains("service_role"))
    }

    @Test func knownAuthenticationErrorsAreMappedToSafeCopy() {
        let message = SafeErrorMessages.authentication(
            ProviderError(description: "AuthApiError: Invalid login credentials"),
            operation: .signIn
        )
        #expect(message == "The email or password is incorrect.")
    }

    @Test func databaseAndPurchaseErrorsNeverExposeProviderText() {
        let providerError = ProviderError(
            description: "PostgREST PGRST999 service_role internal detail"
        )
        let dataMessage = SafeErrorMessages.data(providerError, action: "project save")
        let purchaseMessage = SafeErrorMessages.purchase(providerError)

        #expect(dataMessage == "That project save couldn't be completed. Please try again.")
        #expect(purchaseMessage == "The subscription screen couldn't be completed. Please try again.")
        #expect(!dataMessage.contains("PostgREST"))
        #expect(!purchaseMessage.contains("service_role"))
    }

    @Test func aiErrorsUseOnlyAllowlistedCodes() throws {
        let known = try #require("{\"code\":\"ai_consent_required\",\"details\":\"secret\"}".data(using: .utf8))
        let unknown = try #require("{\"code\":\"provider_leaked_detail\",\"message\":\"raw OpenAI error\"}".data(using: .utf8))

        #expect(
            SafeErrorMessages.ai(statusCode: 403, responseData: known) ==
                "Allow AI features in Privacy & Permissions to continue."
        )
        let unknownMessage = SafeErrorMessages.ai(statusCode: 500, responseData: unknown)
        #expect(unknownMessage == "That request couldn't be completed. Please try again.")
        #expect(!unknownMessage.contains("OpenAI"))
    }

    @Test func mediaPayloadContainsOnlyPreparedBoundedData() throws {
        let audio = Data([0x01, 0x02, 0x03])
        let frame = Data([0xFF, 0xD8, 0xFF])
        let attachment = PreparedAIAttachment(
            kind: .video,
            displayName: "Video attached",
            mimeType: "audio/mp4",
            attachmentData: nil,
            videoFramesJPEG: [frame],
            videoAudioData: audio,
            thumbnailJPEG: frame
        )

        #expect(attachment.requestPayload["attachment_kind"] as? String == "video")
        #expect(attachment.requestPayload["attachment_base64"] == nil)
        #expect(
            attachment.requestPayload["video_frames_base64"] as? [String] ==
                [frame.base64EncodedString()]
        )
        #expect(
            attachment.requestPayload["video_audio_base64"] as? String ==
                audio.base64EncodedString()
        )
    }

    @Test func attachmentLimitsRemainBounded() {
        #expect(AIAttachmentPreparer.maximumSourceBytes == 25_000_000)
        #expect(AIAttachmentPreparer.maximumVideoSeconds == 60)
        #expect(AIAttachmentPreparer.maximumVideoFrames == 6)
        #expect(AIAttachmentPreparer.maximumFrameBytes == 2_000_000)
        #expect(AIAttachmentPreparer.maximumCombinedFrameBytes == 8_000_000)
    }

    @MainActor @Test func consentVersionIsExplicitAndStable() {
        #expect(AIConsentStore.currentVersion == "2026-07-31")
    }

    @Test func estimateDerivesItemAndMaterialSummaries() {
        let materials = EstimateCategory(
            name: "Materials",
            items: [
                EstimateLineItem(
                    name: "Tile",
                    quantity: 2,
                    unitLabel: "box",
                    unitPrice: 50,
                    total: 100
                ),
                EstimateLineItem(
                    name: "Grout",
                    quantity: 1,
                    unitLabel: "bag",
                    unitPrice: 25,
                    total: 25
                ),
            ],
            subtotal: 125
        )
        let labor = EstimateCategory(
            name: "Labor",
            items: [
                EstimateLineItem(
                    name: "Installation",
                    quantity: 3,
                    unitLabel: "hour",
                    unitPrice: 80,
                    total: 240
                ),
            ],
            subtotal: 240
        )
        let estimate = makeEstimate(
            categories: [materials, labor],
            subtotal: 365,
            markupPercent: 10,
            markupAmount: 36.50,
            total: 401.50
        )

        #expect(estimate.itemCount == 3)
        #expect(estimate.materials.map(\.name) == ["Tile", "Grout"])
        #expect(estimate.materialsSubtotal == 125)
        #expect(estimate.formattedTotal.contains("401.50"))
    }

    @Test func estimateDictionaryParsingUsesLineItemSumForCategorySubtotal() throws {
        let dictionary: [String: Any] = [
            "title": "Faucet replacement",
            "categories": [[
                "name": "Materials",
                "subtotal": 0.0,
                "items": [[
                    "name": "Faucet",
                    "quantity": 2.0,
                    "unitLabel": "EA",
                    "unitPrice": 45.0,
                    "total": 90.0,
                ]],
            ]],
            "subtotal": 90.0,
            "markupPercent": 10.0,
            "markupAmount": 9.0,
            "total": 99.0,
        ]

        let estimate = try #require(Estimate.from(
            dict: dictionary,
            chatSessionId: UUID(),
            estimateNumber: "EST-10002"
        ))

        #expect(estimate.categories.count == 1)
        #expect(estimate.categories[0].subtotal == 90)
        #expect(estimate.categories[0].items[0].total == 90)
    }

    @Test func estimateDictionaryParsingIncludesDetailedWorkPlan() throws {
        let dictionary: [String: Any] = [
            "title": "Water heater replacement",
            "categories": [[
                "name": "Plumbing",
                "subtotal": 800.0,
                "items": [[
                    "name": "Water heater replacement",
                    "quantity": 1.0,
                    "unitLabel": "EA",
                    "unitPrice": 800.0,
                    "total": 800.0,
                ]],
            ]],
            "subtotal": 800.0,
            "markupPercent": 0.0,
            "markupAmount": 0.0,
            "total": 800.0,
            "workPlan": [[
                "id": "5E363276-121F-44C8-B8BD-F13D0F187468",
                "title": "Removal and disposal",
                "steps": ["Protect the work area.", "Remove and dispose of the existing unit."],
            ]],
            "notes": "Coordinate access with the homeowner.",
        ]

        let estimate = try #require(Estimate.from(
            dict: dictionary,
            chatSessionId: UUID(),
            estimateNumber: "EST-10003"
        ))

        #expect(estimate.workPlan?.first?.title == "Removal and disposal")
        #expect(estimate.workPlan?.first?.steps.count == 2)
        #expect(estimate.notes == "Coordinate access with the homeowner.")
    }

    @MainActor @Test func estimatePDFContainsPricePlanMediaAndNotes() throws {
        let category = EstimateCategory(
            name: "Plumbing",
            items: [EstimateLineItem(
                name: "Water heater replacement",
                quantity: 1,
                unitLabel: "EA",
                unitPrice: 800,
                total: 800
            )],
            subtotal: 800
        )
        var estimate = makeEstimate(categories: [category], subtotal: 800, total: 800)
        estimate.workPlan = [
            EstimatePlanSection(
                title: "Preparation and protection",
                steps: [
                    "Confirm access to the work area.",
                    "Protect the floors and surrounding finishes.",
                    "Stage the replacement unit and installation materials.",
                ]
            ),
            EstimatePlanSection(
                title: "Removal and installation",
                steps: [
                    "Disconnect and remove the existing unit.",
                    "Install and connect the replacement unit.",
                    "Verify operation and clean the completed work area.",
                ]
            ),
        ]
        estimate.notes = "Coordinate site access before work begins."

        let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).image { context in
            UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
            UIColor(AppBrand.accent).setFill()
            context.fill(CGRect(x: 90, y: 90, width: 720, height: 420))
        }
        let imageData = try #require(image.jpegData(compressionQuality: 0.9))
        let media = [EstimateMediaAsset(
            id: UUID(),
            kind: "render",
            displayName: "Proposed finished space",
            mimeType: "image/jpeg",
            data: imageData
        )]

        let data = OutgoingDocument.estimate(estimate).pdfData(client: nil, estimateMedia: media)
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        #expect(document.pageCount >= 1)
        #expect(text.contains("ESTIMATE TOTAL"))
        #expect(text.contains("PROJECT PLAN"))
        #expect(text.contains("Removal and installation"))
        #expect(text.contains("PHOTOS & PLANS"))
        #expect(text.contains("Coordinate site access"))
        #expect(!text.contains("Water heater replacement"))

        try data.write(
            to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("easybid-estimate-proposal.pdf"),
            options: .atomic
        )
    }

    @MainActor @Test func estimateAppearanceIsSavedAndRenderedInThePDF() throws {
        var estimate = makeEstimate(categories: [], subtotal: 800, total: 800)
        estimate.appearance = EstimateAppearance(accent: .green, businessName: "Northside Builders")
        let encoded = try JSONEncoder().encode(estimate)
        let restored = try JSONDecoder().decode(Estimate.self, from: encoded)
        #expect(restored.appearance == estimate.appearance)
        let greenPDF = try #require(PDFDocument(data: OutgoingDocument.estimate(restored).pdfData(client: nil)))
        #expect(greenPDF.string?.contains("Northside Builders") == true)
        #expect(greenPDF.string?.contains("ESTIMATE TOTAL") == true)
        let greenPage = try #require(greenPDF.page(at: 0)).thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        estimate.appearance?.accent = .black
        let blackPDF = try #require(PDFDocument(data: OutgoingDocument.estimate(estimate).pdfData(client: nil)))
        let blackPage = try #require(blackPDF.page(at: 0)).thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        #expect(greenPage.pngData() != blackPage.pngData())
        var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "appearance")
        let oldEstimate = try JSONDecoder().decode(Estimate.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(oldEstimate.appearance == nil)
    }

    @Test func invoiceAppliesDiscountBeforeTax() {
        let invoice = Invoice(
            invoiceNumber: "INV-10001",
            title: "Bathroom update",
            description: "",
            items: [
                InvoiceLineItem(title: "Labor", quantity: 2, unitPrice: 100, unit: "hour"),
                InvoiceLineItem(title: "Materials", quantity: 1, unitPrice: 50, unit: "EA"),
            ],
            discount: 25,
            taxPercent: 8,
            status: "Draft",
            dueDate: "On completion",
            clientId: nil,
            projectId: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            coverTransactionFees: false,
            termsAndConditions: "",
            attachments: []
        )

        #expect(invoice.subtotal == 250)
        #expect(invoice.discountAmount == 25)
        #expect(abs(invoice.taxAmount - 18) < 0.0001)
        #expect(abs(invoice.total - 243) < 0.0001)
    }

    @Test func invoiceConversionPreservesEstimateItemsMarkupAndContingency() throws {
        let category = EstimateCategory(
            name: "Labor and materials",
            items: [
                EstimateLineItem(
                    name: "Base scope",
                    quantity: 2,
                    unitLabel: "EA",
                    unitPrice: 150,
                    total: 300
                ),
            ],
            subtotal: 300
        )
        var estimate = makeEstimate(
            categories: [category],
            subtotal: 300,
            markupPercent: 10,
            markupAmount: 30,
            total: 345,
            contingency: ContingencyInfo(percent: 5, amount: 15, reason: "Unknown conditions")
        )
        let estimateID = UUID()
        estimate.supabaseEstimateId = estimateID.uuidString
        let projectID = UUID()
        let clientID = UUID()

        let invoice = Invoice.from(
            estimate: estimate,
            projectId: projectID,
            clientId: clientID,
            number: 7
        )

        #expect(invoice.estimateId == estimateID)
        #expect(invoice.projectId == projectID)
        #expect(invoice.clientId == clientID)
        #expect(invoice.invoiceNumber == "INV-10007")
        #expect(invoice.items.map(\.title) == [
            "Base scope",
            "Markup (10%)",
            "Contingency (5%)",
        ])
        #expect(abs(invoice.total - estimate.total) < 0.0001)
        #expect(invoice.termsAndConditions == "Due on completion")
    }

    @Test func invoiceAndPaymentSurviveCodableRoundTrips() throws {
        let projectID = UUID()
        let invoice = Invoice(
            id: UUID(),
            invoiceNumber: "INV-10008",
            title: "Deck repair",
            description: "Replace damaged boards",
            items: [
                InvoiceLineItem(title: "Deck board", quantity: 4, unitPrice: 22.50, unit: "EA"),
            ],
            discount: 5,
            taxPercent: 7.5,
            status: "Sent",
            dueDate: "Net 15",
            clientId: UUID(),
            projectId: projectID,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            coverTransactionFees: true,
            termsAndConditions: "Thank you",
            attachments: ["scope.pdf"]
        )
        let invoiceData = try JSONEncoder().encode(invoice)
        let decodedInvoice = try JSONDecoder().decode(Invoice.self, from: invoiceData)

        #expect(decodedInvoice.id == invoice.id)
        #expect(decodedInvoice.projectId == projectID)
        #expect(decodedInvoice.items.count == 1)
        #expect(decodedInvoice.items[0].title == "Deck board")
        #expect(abs(decodedInvoice.total - invoice.total) < 0.0001)

        let payment = Payment(
            id: UUID(),
            projectId: projectID,
            invoiceId: invoice.id,
            amount: 91.38,
            method: "Check",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_100),
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let paymentData = try JSONEncoder().encode(payment)
        let decodedPayment = try JSONDecoder().decode(Payment.self, from: paymentData)

        #expect(decodedPayment == payment)
    }

    @Test func projectWorkflowUsesServerEstimateStatus() {
        let category = EstimateCategory(name: "Labor", items: [], subtotal: 0)
        var approvedEstimate = makeEstimate(
            categories: [category],
            subtotal: 0,
            total: 0
        )
        approvedEstimate.status = "Approved"
        let approvedProject = Project(
            projectNumber: "PRJ-10001",
            title: "Approved job",
            price: 0,
            status: "Draft",
            estimate: approvedEstimate
        )
        var sentEstimate = approvedEstimate
        sentEstimate.status = "Viewed"
        let sentProject = Project(
            projectNumber: "PRJ-10002",
            title: "Sent job",
            price: 0,
            status: "Draft",
            estimate: sentEstimate
        )

        #expect(approvedProject.workflowStatus == "Approved")
        #expect(sentProject.workflowStatus == "Sent")
    }

    @Test func consentRecordsDecodeServerFieldNames() throws {
        let userID = UUID()
        let json = """
        {
          "user_id": "\(userID.uuidString)",
          "is_granted": true,
          "consent_version": "\(AIConsentStore.currentVersion)",
          "granted_at": "2026-08-01T12:00:00Z",
          "revoked_at": null
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(AIConsentRecord.self, from: Data(json.utf8))

        #expect(record.userID == userID)
        #expect(record.isGranted)
        #expect(record.consentVersion == AIConsentStore.currentVersion)
        #expect(record.grantedAt != nil)
        #expect(record.revokedAt == nil)
    }

    @Test func premiumPlacementNamesMatchProductionCampaign() {
        #expect(Set(PremiumPlacement.allCases.map(\.rawValue)) == [
            "create_estimate",
            "create_invoice",
            "create_render",
            "send_estimate",
            "send_invoice",
        ])
    }

    @Test func threeDayTrialLengthRemainsExplicit() {
        #expect(SuperwallService.freeTrialDays == 3)
    }

    @Test func activeTrialOrSubscriptionAllowsPaidActions() {
        let decision = PremiumAccessPolicy.initialDecision(
            isConfigured: true,
            subscriptionState: .active
        )

        #expect(decision == .allow)
    }

    @Test func expiredTrialRequiresWinBackPaywall() {
        let decision = PremiumAccessPolicy.initialDecision(
            isConfigured: true,
            subscriptionState: .inactive
        )

        #expect(decision == .presentPaywall)
    }

    @Test func unknownSubscriptionStateDoesNotUnlockPaidActions() {
        let decision = PremiumAccessPolicy.initialDecision(
            isConfigured: true,
            subscriptionState: .unknown
        )

        #expect(decision == .presentPaywall)
    }

    @Test func missingSuperwallConfigurationFailsClosed() {
        for state in [
            PremiumSubscriptionAccessState.active,
            .inactive,
            .unknown,
        ] {
            #expect(PremiumAccessPolicy.initialDecision(
                isConfigured: false,
                subscriptionState: state
            ) == .failClosed)
        }
    }

    @Test func purchaseAndRestoreUnlockTheRequestedAction() {
        #expect(PremiumAccessPolicy.decision(after: .purchased) == .allow)
        #expect(PremiumAccessPolicy.decision(after: .restored) == .allow)
    }

    @Test func dismissSkipAndErrorNeverUnlockTheRequestedAction() {
        #expect(PremiumAccessPolicy.decision(after: .declined) == .failClosed)
        #expect(PremiumAccessPolicy.decision(after: .skipped) == .failClosed)
        #expect(PremiumAccessPolicy.decision(after: .error) == .failClosed)
    }

    @Test func timedOutRenderCreationRecoversOnlyTheNewMatchingRender() {
        let projectID = UUID()
        let oldRenderID = UUID()
        let oldRender = makeProjectRender(
            id: oldRenderID,
            projectID: projectID,
            currentImagePath: "old.png"
        )
        let newRender = makeProjectRender(
            projectID: projectID,
            currentImagePath: "new.png"
        )
        let context = ProjectRenderRecoveryContext.create(
            projectID: projectID,
            prompt: "Replace the cabinets",
            existingRenderIDs: [oldRenderID]
        )

        #expect(ProjectRenderRecovery.match(context, in: [oldRender, newRender]) == newRender)
    }

    @Test func timedOutRenderRevisionWaitsForAChangedImage() {
        let projectID = UUID()
        let renderID = UUID()
        let unchanged = makeProjectRender(
            id: renderID,
            projectID: projectID,
            currentImagePath: "first.png"
        )
        let revised = makeProjectRender(
            id: renderID,
            projectID: projectID,
            currentImagePath: "second.png"
        )
        let context = ProjectRenderRecoveryContext.revise(
            renderID: renderID,
            previousImagePath: "first.png"
        )

        #expect(ProjectRenderRecovery.match(context, in: [unchanged]) == nil)
        #expect(ProjectRenderRecovery.match(context, in: [revised]) == revised)
    }

    @Test func timedOutRenderAcceptanceWaitsForAcceptedState() {
        let projectID = UUID()
        let renderID = UUID()
        let draft = makeProjectRender(
            id: renderID,
            projectID: projectID,
            currentImagePath: "render.png"
        )
        let accepted = makeProjectRender(
            id: renderID,
            projectID: projectID,
            currentImagePath: "render.png",
            status: "accepted",
            acceptedImagePath: "render.png"
        )
        let context = ProjectRenderRecoveryContext.accept(renderID: renderID)

        #expect(ProjectRenderRecovery.match(context, in: [draft]) == nil)
        #expect(ProjectRenderRecovery.match(context, in: [accepted]) == accepted)
    }
}
