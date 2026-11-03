import SwiftUI
import UIKit

enum ProjectQuickCreateAction: String, Identifiable {
    case render
    case invoice

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .render: L("Choose a project to add a render")
        case .invoice: L("Choose a project to create an invoice")
        }
    }
}

struct ProjectActionPickerView: View {
    let action: ProjectQuickCreateAction

    @Environment(\.dismiss) private var dismiss
    @State private var projectStore = ProjectStore.shared
    @State private var invoiceStore = InvoiceStore.shared
    @State private var renderProject: Project?
    @State private var invoiceDraft: Invoice?
    @State private var subscriptionError: String?

    var body: some View {
        VStack(spacing: 0) {
            pickerHeader

            ScrollView {
                LazyVStack(spacing: 12) {
                    if projectStore.isLoading && projectStore.projects.isEmpty {
                        ProgressView()
                            .padding(.top, 80)
                    } else if projectStore.projects.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 30))
                                .foregroundColor(AppGray.muted)
                            Text(L("No projects yet"))
                                .font(.system(size: 20, weight: .bold))
                            Text(action == .render ? L("Create a project before adding a render.") : L("Create a project before adding an invoice."))
                                .font(.system(size: 15))
                                .foregroundColor(AppGray.secondary)
                        }
                        .padding(.top, 80)
                    } else {
                        ForEach(projectStore.projects) { project in
                            HapticButton {
                                choose(project)
                            } label: {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .background(AppGray.bgPale.ignoresSafeArea())
        .task { await projectStore.refresh() }
        .fullScreenCover(item: $renderProject) { project in
            RenderCreationView(project: project)
        }
        .fullScreenCover(item: $invoiceDraft) { invoice in
            NavigationStack {
                InvoiceDetailView(invoice: invoice) { saved in
                    invoiceStore.update(saved)
                }
            }
        }
        .alert(
            L("Subscription unavailable"),
            isPresented: Binding(
                get: { subscriptionError != nil },
                set: { if !$0 { subscriptionError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(subscriptionError ?? L("Please try again."))
        }
    }

    private var pickerHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HapticButton { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Text(L("Projects"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(AppGray.ink)
            Text(action.subtitle)
                .font(.system(size: 16))
                .foregroundColor(AppGray.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .background(Color.white)
    }

    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 14) {
            Image(systemName: action == .render ? "camera.fill" : "doc.plaintext.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(AppBrand.accent)
                .frame(width: 44, height: 44)
                .background(AppBrand.accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                    .lineLimit(1)
                Text([project.projectNumber, project.clientName].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
                    .lineLimit(1)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppGray.muted)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.055), radius: 9, x: 0, y: 3)
    }

    private func choose(_ project: Project) {
        let placement: PremiumPlacement = action == .render ? .createRender : .createInvoice
        SuperwallService.performPremiumAction(
            placement,
            params: ["source": "quick_create_project_picker"],
            onFailure: { subscriptionError = $0 },
            action: { chooseAfterGate(project) }
        )
    }

    private func chooseAfterGate(_ project: Project) {
        switch action {
        case .render:
            renderProject = project
        case .invoice:
            let invoice: Invoice
            if let estimate = project.estimate {
                invoice = Invoice.from(
                    estimate: estimate,
                    projectId: project.id,
                    clientId: project.clientId,
                    number: invoiceStore.nextNumber
                )
            } else {
                var blank = Invoice.createNew(number: invoiceStore.nextNumber)
                blank.projectId = project.id
                blank.clientId = project.clientId
                blank.title = project.title
                invoice = blank
            }
            invoiceStore.add(invoice)
            invoiceDraft = invoice
        }
    }
}

struct RenderCreationView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @State private var store = ProjectRenderStore.shared
    @State private var consentStore = AIConsentStore.shared
    @State private var photoData: Data?
    @State private var prompt = ""
    @State private var activeRender: ProjectRender?
    @State private var images: ProjectRenderImages?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showAIConsent = false
    @State private var showCameraDenied = false
    @State private var errorMessage: String?
    @State private var didAccept = false
    @FocusState private var promptFocused: Bool

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(spacing: 0) {
            navigationHeader

            if let activeRender {
                resultStep(activeRender)
            } else {
                inputStep
            }
        }
        .background(AppGray.bgPale.ignoresSafeArea())
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerView { data in
                photoData = data
                errorMessage = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPickerView { data in
                photoData = data
                errorMessage = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAIConsent) {
            AIConsentPromptView(consentStore: consentStore)
        }
        .alert(L("Camera access is off"), isPresented: $showCameraDenied) {
            HapticButton("Open Settings") { AppPermissions.openSettings() }
            HapticButton("Cancel", role: .cancel) {}
        } message: {
            Text(L("Enable camera access in Settings to photograph this project."))
        }
        .task { await consentStore.refresh() }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(L("New Render"))
                .font(.system(size: 17, weight: .semibold))

            HStack {
                HapticButton { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(
                            .clear.tint(Color.white.opacity(0.72)),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                Spacer()
                if didAccept {
                    Text(L("Saved"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(brandBlue)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppGray.bgPale.ignoresSafeArea(edges: .top))
    }

    private var inputStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    composerContent

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("Attach Photo"))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppGray.ink)

                        HStack(spacing: 12) {
                            mediaButton(title: L("Upload Photo"), icon: "photo") {
                                showPhotoPicker = true
                            }
                            mediaButton(title: L("Take Photo"), icon: "camera") {
                                Task {
                                    if await AppPermissions.request(.camera) {
                                        showCamera = true
                                    } else {
                                        showCameraDenied = true
                                    }
                                }
                            }
                        }
                    }

                    if let photoData {
                        attachedPhotoRow(data: photoData)
                    }

                    if store.isGenerating {
                        generatingCard
                    }

                    errorText
                }
                .padding(20)
            }

            renderBottomButton
        }
    }

    private func resultStep(_ render: ProjectRender) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                generatedResult(render)

                if store.isGenerating {
                    generatingCard
                }

                errorText
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(
            AppGray.bgPale
                .contentShape(Rectangle())
                .onTapGesture { promptFocused = false }
        )
    }

    private var composerContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Project Description"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppGray.ink)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $prompt)
                    .focused($promptFocused)
                    .font(.system(size: 16))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(12)

                if prompt.isEmpty {
                    Text(L("Describe the remodel or construction you want to visualize."))
                        .font(.system(size: 16))
                        .foregroundColor(AppGray.muted)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }

    private var canGenerate: Bool {
        photoData != nil && prompt.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private func mediaButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        HapticButton(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                Text(L(title))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(AppGray.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func attachedPhotoRow(data: Data) -> some View {
        HStack(spacing: 12) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text(L("Photo attached"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppGray.ink)
            Spacer()
            HapticButton {
                photoData = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppGray.borderStrong)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private var renderBottomButton: some View {
        HapticButton(action: generateInitial) {
            HStack(spacing: 8) {
                if store.isGenerating {
                    ProgressView().tint(.white)
                }
                Text(store.isGenerating ? L("Generating Render…") : L("Generate Render"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(canGenerate && !store.isGenerating ? AppGray.ink : AppGray.borderStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate || store.isGenerating)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(L(errorMessage))
                .font(.system(size: 14))
                .foregroundColor(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func generatedResult(_ render: ProjectRender) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(render.isAccepted ? L("Accepted render") : L("Your render"))
                .font(.system(size: 20, weight: .bold))

            if let images {
                BeforeAfterRenderView(images: images)
                    .onTapGesture { promptFocused = false }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .task(id: render.currentImagePath) {
                        images = try? await store.images(for: render)
                    }
            }

            VStack(alignment: .leading, spacing: 7) {
                requestSectionLabel(L("Your request"))
                Text("“\(render.initialPrompt)”")
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { promptFocused = false }

            if !render.isAccepted {
                requestSectionLabel(L("Request an edit"))

                TextField(L("Try “Use white oak cabinets and brass hardware”"), text: $prompt, axis: .vertical)
                    .focused($promptFocused)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    HapticButton(action: reviseRender) {
                        Text(L("Request Edit"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppGray.bgFaint)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || store.isGenerating)

                    HapticButton(action: acceptRender) {
                        Text(L("Accept"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppGray.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(store.isGenerating)
                }
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 4)
    }

    private func requestSectionLabel(_ title: String) -> some View {
        Text(L(title))
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(AppGray.ink)
    }

    private var generatingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Creating your render"))
                    .font(.system(size: 15, weight: .semibold))
                Text(L("This can take a minute."))
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func generateInitial() {
        guard let photoData else { return }
        SuperwallService.performPremiumAction(
            .createRender,
            params: ["source": "render_generator", "operation": "create"],
            onFailure: { errorMessage = $0 },
            action: {
                Task { await runAI {
                    try await store.create(
                        projectID: project.id,
                        photoData: photoData,
                        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                } }
            }
        )
    }

    private func reviseRender() {
        guard let activeRender else { return }
        let editPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        SuperwallService.performPremiumAction(
            .createRender,
            params: ["source": "render_generator", "operation": "revise"],
            onFailure: { errorMessage = $0 },
            action: {
                Task { await runAI { try await store.revise(activeRender, prompt: editPrompt) } }
            }
        )
    }

    private func acceptRender() {
        guard let activeRender else { return }
        promptFocused = false
        Task {
            do {
                let accepted = try await store.accept(activeRender)
                self.activeRender = accepted
                didAccept = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runAI(_ operation: @escaping () async throws -> ProjectRender) async {
        guard consentStore.isGranted else {
            showAIConsent = true
            return
        }
        promptFocused = false
        errorMessage = nil
        do {
            let render = try await operation()
            activeRender = render
            images = nil
            prompt = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct BeforeAfterRenderView: View {
    let images: ProjectRenderImages
    var labelAlignment: Alignment = .topLeading
    var showsExpandIndicator = false
    var onImageTap: ((UIImage, String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            imagePanel(images.before, label: L("Before"))
            imagePanel(images.after, label: L("After"))
        }
    }

    @ViewBuilder
    private func imagePanel(_ image: UIImage, label: String) -> some View {
        if let onImageTap {
            HapticButton {
                onImageTap(image, label)
            } label: {
                imagePanelContent(image, label: label)
            }
            .buttonStyle(.plain)
        } else {
            imagePanelContent(image, label: label)
        }
    }

    private func imagePanelContent(_ image: UIImage, label: String) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: labelAlignment) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .glassEffect(
                        .clear.tint(Color.black.opacity(0.62)),
                        in: Capsule()
                    )
                    .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                if showsExpandIndicator {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.45), radius: 3, x: 0, y: 1)
                        .padding(12)
                }
            }
    }
}

struct ProjectRenderTabView: View {
    let project: Project

    @State private var store = ProjectRenderStore.shared
    @State private var showNewRender = false
    @State private var subscriptionError: String?

    private var projectRenders: [ProjectRender] {
        store.renders(for: project.id)
    }

    var body: some View {
        VStack(spacing: 16) {
            if store.isLoading && projectRenders.isEmpty {
                ProgressView().padding(.vertical, 60)
            } else if projectRenders.isEmpty {
                VStack(spacing: 16) {
                    Spacer().frame(height: 60)
                    Text(L("No renders yet"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppGray.ink)
                    Text(L("Upload a job photo and visualize\nthe finished work with AI."))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(AppGray.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    HapticButton(action: beginRenderCreation) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text(L("Create render"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .frame(minWidth: 180)
                        .background(AppGray.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Renders"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                        Text(L("Before-and-after\nconcept images"))
                            .font(.system(size: 15))
                            .foregroundColor(AppGray.secondary)
                    }
                    Spacer()
                    HapticButton(action: beginRenderCreation) {
                        Label(L("New Render"), systemImage: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(AppGray.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 21)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)

                ForEach(projectRenders) { render in
                    ProjectRenderCard(render: render, projectTitle: project.title)
                }
            }

            if let error = store.lastError {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { await store.refresh(projectID: project.id) }
        .fullScreenCover(isPresented: $showNewRender, onDismiss: {
            Task { await store.refresh(projectID: project.id) }
        }) {
            RenderCreationView(project: project)
        }
        .alert(
            L("Subscription unavailable"),
            isPresented: Binding(
                get: { subscriptionError != nil },
                set: { if !$0 { subscriptionError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(subscriptionError ?? L("Please try again."))
        }
    }

    private func beginRenderCreation() {
        SuperwallService.performPremiumAction(
            .createRender,
            params: ["source": "project_render_tab"],
            onFailure: { subscriptionError = $0 },
            action: { showNewRender = true }
        )
    }
}

private struct ProjectRenderCard: View {
    let render: ProjectRender
    let projectTitle: String
    @State private var store = ProjectRenderStore.shared
    @State private var images: ProjectRenderImages?
    @State private var selectedImage: RenderImageSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("%@ Render", "\(projectTitle)"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)

            Text(render.initialPrompt)
                .font(.system(size: 14))
                .foregroundColor(AppGray.secondary)
                .lineLimit(3)
                .padding(.top, 8)
                .padding(.bottom, 18)

            if let images {
                BeforeAfterRenderView(
                    images: images,
                    labelAlignment: .bottomLeading,
                    showsExpandIndicator: true,
                    onImageTap: { image, label in
                        selectedImage = RenderImageSelection(image: image, label: label)
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .task { images = try? await store.images(for: render) }
            }

        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        .fullScreenCover(item: $selectedImage) { selection in
            RenderImagePreview(
                selection: selection,
                title: L("%@ Render", "\(projectTitle)")
            )
        }
    }
}

private struct RenderImageSelection: Identifiable {
    let id = UUID()
    let image: UIImage
    let label: String
}

private struct RenderImagePreview: View {
    @Environment(\.dismiss) private var dismiss

    let selection: RenderImageSelection
    let title: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: selection.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L(title))
                            .font(.system(size: 17, weight: .semibold))
                        Text(selection.label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .foregroundColor(.white)

                    Spacer()

                    HapticButton { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .glassEffect(
                                .clear.tint(Color.white.opacity(0.16)),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()
            }
        }
        .statusBarHidden()
    }
}
