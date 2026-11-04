//
//  ProjectDetailView.swift
//  Construction Estimate
//
//

import SwiftUI
import Supabase
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private enum ProjectDetailTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case estimate = "Estimate"
    case invoices = "Invoices"
    case render = "Render"
    case client = "Client"
    case documents = "Documents"

    var id: String { rawValue }
}

private struct EstimateDocumentSelection: Identifiable {
    let estimate: Estimate
    let position: Int
    var id: UUID { estimate.id }
}

private enum ProjectMetadataField: String, Identifiable {
    case address
    case assignee

    var id: String { rawValue }
    var title: String { self == .address ? L("Project address") : L("Assignee") }
    var placeholder: String { self == .address ? L("Enter address") : L("Enter assignee name") }
}

struct ProjectDetailView: View {
    let project: Project?
    var onSave: ((Project) -> Void)?
    var onUpdate: ((Project) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(TabBarVisibility.self) private var tabBar
    @State private var selectedTab: ProjectDetailTab = .dashboard
    @State private var projectTitle: String = ""
    @FocusState private var projectTitleFocused: Bool
    @State private var estimatePrice: String = ""
    @State private var projectAddress: String = ""
    @State private var projectAssignee: String = ""
    @State private var editingProjectMetadata: ProjectMetadataField?
    @State private var projectStatus: String = "Lead"
    @State private var selectedClient: Client? = nil
    @State private var showClientPicker: Bool = false
    @State private var estimateChatSessionId: UUID? = nil
    @State private var showEstimateChat: Bool = false
    @State private var showEstimateCreation: Bool = false
    @State private var showApacheEstimator = false
    @State private var confirmedEstimate: Estimate? = nil
    @State private var selectedEstimateDocument: EstimateDocumentSelection?
    @State private var projectEstimates: [Estimate] = []
    @State private var estimateHistoryLoaded = false
    @State private var draftProjectID = UUID()
    @State private var draftProjectNumber = "PRJ-\(Int.random(in: 10000...99999))"
    @State private var hasPersistedDraft = false
    @State private var saveError: String?
    @State private var showDeleteProjectConfirm = false
    /// Live Supabase rows for the active estimate, shared across the Overview
    /// and Materials tabs so the numbers stay in sync and don't refetch on
    /// every tab switch.
    @State private var sharedSupabaseRows: [EstimateItemRow]? = nil

    var isNewProject: Bool { project == nil }
    var canonicalProjectID: UUID { project?.id ?? draftProjectID }

    var projectClientForDisplay: Client? {
        if let selectedClient {
            return selectedClient
        }

        guard let clientName = project?.clientName, !clientName.isEmpty else {
            return nil
        }

        return Client(
            name: clientName,
            company: "",
            email: project?.clientEmail ?? "",
            phone: project?.clientPhone ?? "",
            address: "",
            referralSource: ""
        )
    }

    var displayNumber: String {
        project?.projectNumber ?? draftProjectNumber
    }

    var estimatesForDisplay: [Estimate] {
        if estimateHistoryLoaded { return projectEstimates }
        if !projectEstimates.isEmpty { return projectEstimates }
        if let estimate = confirmedEstimate ?? project?.estimate { return [estimate] }
        return []
    }

    func buildCurrentProject() -> Project {
        let finalPrice = confirmedEstimate?.total ?? Double(estimatePrice.replacingOccurrences(of: ",", with: "")) ?? project?.price ?? 0
        let fallbackTitle = project?.title ?? confirmedEstimate?.title ?? L("Untitled Project")
        return Project(
            id: canonicalProjectID,
            organizationId: project?.organizationId,
            clientId: selectedClient?.id ?? project?.clientId,
            propertyId: project?.propertyId,
            projectNumber: project?.projectNumber ?? displayNumber,
            title: projectTitle.isEmpty ? fallbackTitle : projectTitle,
            price: finalPrice,
            status: projectStatus.isEmpty ? (project?.status ?? "Lead") : projectStatus,
            clientName: selectedClient?.name ?? project?.clientName,
            clientPhone: selectedClient?.phone ?? project?.clientPhone,
            clientEmail: selectedClient?.email ?? project?.clientEmail,
            address: projectAddress.isEmpty ? project?.address : projectAddress,
            assignee: projectAssignee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : projectAssignee,
            estimateChatSessionId: estimateChatSessionId ?? project?.estimateChatSessionId,
            estimate: confirmedEstimate ?? project?.estimate
        )
    }

    private func deleteProject() {
        guard let project else { return }
        ProjectStore.shared.delete(project)
        tabBar.isHidden = false
        dismiss()
    }

    func buildAndSave() {
        let built = buildCurrentProject()
        if isNewProject {
            onSave?(built)
        } else {
            onUpdate?(built)
        }
    }

    func markEstimateSent(_ estimate: Estimate) {
        var updated = estimate
        updated.status = "Sent"
        updateEstimateInHistory(updated)
        let activeEstimate = confirmedEstimate ?? project?.estimate
        if activeEstimate?.supabaseEstimateId == updated.supabaseEstimateId {
            confirmedEstimate = updated
            projectStatus = "Sent"
        }
        Task { await ProjectStore.shared.refresh() }
    }

    func updateEstimateInHistory(_ estimate: Estimate) {
        if let index = projectEstimates.firstIndex(where: {
            if let remoteID = estimate.supabaseEstimateId { return $0.supabaseEstimateId == remoteID }
            return $0.id == estimate.id
        }) {
            projectEstimates[index] = estimate
        } else {
            projectEstimates.append(estimate)
            projectEstimates.sort { $0.createdAt < $1.createdAt }
        }
    }

    func deleteEstimate(_ estimate: Estimate) {
        projectEstimates.removeAll { candidate in
            if let remoteID = estimate.supabaseEstimateId {
                return candidate.supabaseEstimateId == remoteID
            }
            return candidate.id == estimate.id
        }
        estimateHistoryLoaded = true
        if confirmedEstimate?.supabaseEstimateId == estimate.supabaseEstimateId {
            confirmedEstimate = projectEstimates.last
        }

        Task {
            guard let value = estimate.supabaseEstimateId,
                  let id = UUID(uuidString: value) else { return }
            do {
                try await ProjectRepository.deleteEstimate(id)
                saveError = nil
            } catch {
                saveError = SafeErrorMessages.data(error, action: "estimate deletion")
                if let restored = try? await ProjectRepository.loadEstimates(projectID: canonicalProjectID) {
                    projectEstimates = restored
                }
            }
        }
    }

    func selectClient(_ client: Client) {
        selectedClient = client

        if project != nil {
            onUpdate?(buildCurrentProject())
        } else if hasPersistedDraft {
            Task {
                do {
                    try await ProjectStore.shared.persistAndWait(buildCurrentProject())
                    saveError = nil
                } catch {
                    saveError = SafeErrorMessages.data(error, action: "project update")
                }
            }
        }
    }

    func openEstimateChat(createNewSession: Bool) {
        if createNewSession {
            SuperwallService.performPremiumAction(
                .createEstimate,
                params: ["source": "project"],
                onFailure: { saveError = $0 },
                action: { openEstimateChatAfterGate(createNewSession: true) }
            )
            return
        }

        openEstimateChatAfterGate(createNewSession: false)
    }

    private func openEstimateChatAfterGate(createNewSession: Bool) {
        let title = projectTitle.isEmpty ? (project?.title ?? L("Untitled Project")) : projectTitle
        if createNewSession {
            estimateChatSessionId = ChatSession.createAndSave(name: L("Estimate – %@", "\(title)"))
        }

        Task {
            do {
                if isNewProject && !hasPersistedDraft {
                    try await ProjectStore.shared.persistAndWait(buildCurrentProject())
                    hasPersistedDraft = true
                }
                saveError = nil
                if createNewSession {
                    showEstimateCreation = true
                } else {
                    showEstimateChat = true
                }
            } catch {
                saveError = SafeErrorMessages.data(error, action: "project save")
            }
        }
    }

    func acceptGeneratedEstimate(_ rawDict: [String: Any], supabaseID: String?) {
        SuperwallService.performPremiumAction(
            .createEstimate,
            params: ["source": "estimate_confirmation"],
            onFailure: { saveError = $0 },
            action: { acceptGeneratedEstimateAfterGate(rawDict, supabaseID: supabaseID) }
        )
    }

    private func acceptGeneratedEstimateAfterGate(_ rawDict: [String: Any], supabaseID: String?) {
        let sessionID = estimateChatSessionId ?? project?.estimateChatSessionId ?? UUID()
        let estimateNumber = "EST-\(10001 + (project == nil ? 0 : Int.random(in: 1...99)))"
        guard let estimate = Estimate.from(
            dict: rawDict,
            chatSessionId: sessionID,
            estimateNumber: estimateNumber,
            supabaseEstimateId: supabaseID
        ) else { return }

        confirmedEstimate = estimate
        updateEstimateInHistory(estimate)
        estimatePrice = String(format: "%.2f", estimate.total)
        let built = buildCurrentProject()
        if project != nil {
            onUpdate?(built)
        } else {
            onSave?(built)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Nav Bar
            HStack(spacing: 14) {
                // Back button
                HapticButton(action: {
                    tabBar.isHidden = false
                    dismiss()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }

                Spacer()

                // Three-dot menu
                Menu {
                    Button {
                        editingProjectMetadata = .address
                    } label: {
                        Label(L("Edit address"), systemImage: "mappin.and.ellipse")
                    }
                    Button {
                        editingProjectMetadata = .assignee
                    } label: {
                        Label(L("Edit assignee"), systemImage: "person.crop.circle")
                    }
                    if !isNewProject {
                        Divider()
                        Button(role: .destructive) {
                            showDeleteProjectConfirm = true
                        } label: {
                            Label(L("Delete Project"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }
                .accessibilityLabel(L("Project Options"))
                .confirmationDialog(
                    L("Delete this project?"),
                    isPresented: $showDeleteProjectConfirm,
                    titleVisibility: .visible
                ) {
                    Button(L("Delete Project"), role: .destructive) { deleteProject() }
                    Button(L("Cancel"), role: .cancel) {}
                } message: {
                    Text(L("This permanently deletes the project and everything in it."))
                }

                // Save / + button
                if isNewProject {
                    HapticButton(action: buildAndSave) {
                        Text(L("Save"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .frame(height: 44)
                            .background(
                            AppBrand.accent
                        )
                        .clipShape(Capsule())
                    }
                } else {
                    Menu {
                        Button {
                            openEstimateChat(createNewSession: true)
                        } label: {
                            Label(L("New Estimate"), systemImage: "doc.text")
                        }
                        Button {
                            selectedTab = .invoices
                        } label: {
                            Label(L("Create Invoice"), systemImage: "doc.plaintext")
                        }
                        Button {
                            selectedTab = .render
                        } label: {
                            Label(L("Create Render"), systemImage: "camera")
                        }
                        Button {
                            selectedTab = .documents
                        } label: {
                            Label(L("Add document"), systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(AppBrand.accent)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel(L("Add to project"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            
            // MARK: - Project Header
            VStack(alignment: .leading, spacing: 12) {
                Text(displayNumber)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)

                TextField(L("Untitled project"), text: $projectTitle)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(projectTitle.isEmpty ? AppGray.borderStrong : .black)
                    .focused($projectTitleFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        guard !projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        buildAndSave()
                    }
                    .onChange(of: projectTitleFocused) { wasFocused, isFocused in
                        guard wasFocused,
                              !isFocused,
                              !isNewProject,
                              !projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        buildAndSave()
                    }
                
                // Tags
                HStack(spacing: 8) {
                    DetailTagPill(icon: "circle.dotted", text: L(projectStatus))
                    HapticButton { editingProjectMetadata = .address } label: {
                        HStack(spacing: 4) {
                            Text(projectAddress.isEmpty ? L("Address") : projectAddress)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(AppGray.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    HapticButton { editingProjectMetadata = .assignee } label: {
                        HStack(spacing: 4) {
                            Image(systemName: projectAssignee.isEmpty ? "person.crop.circle.badge.xmark" : "person.crop.circle")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                            Text(projectAssignee.isEmpty ? L("No assignee") : projectAssignee)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(AppGray.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            // MARK: - Project Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(ProjectDetailTab.allCases) { tab in
                        HapticButton {
                            selectedTab = tab
                        } label: {
                            VStack(spacing: 8) {
                                Text(L(tab.rawValue))
                                    .font(.system(size: 15, weight: selectedTab == tab ? .semibold : .regular))
                                    .foregroundColor(selectedTab == tab ? AppBrand.accent : AppGray.secondary)

                                Rectangle()
                                    .fill(selectedTab == tab ? AppBrand.accent : Color.clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            
            Rectangle()
                .fill(AppGray.badge)
                .frame(height: 0.7)

            // MARK: - Tab Content
            ScrollView {
                VStack(spacing: 20) {
                    if selectedTab == .dashboard {
                        ProjectDashboardView(
                            projectID: (project != nil || hasPersistedDraft) ? canonicalProjectID : nil,
                            estimate: confirmedEstimate ?? project?.estimate,
                            client: projectClientForDisplay,
                            onCreateEstimate: {
                                openEstimateChat(createNewSession: true)
                            },
                            onOpenEstimate: {
                                selectedTab = .estimate
                            },
                            onOpenInvoices: {
                                selectedTab = .invoices
                            },
                            onEstimateSent: markEstimateSent
                        )
                    } else if selectedTab == .client {
                        if let client = projectClientForDisplay {
                            ClientDetailsCard(
                                client: client,
                                onChangeClient: { showClientPicker = true }
                            )
                        } else {
                            VStack(spacing: 16) {
                                Spacer().frame(height: 60)
                                Text(L("No client yet"))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppGray.ink)
                                Text(L("Add the client you're working with\nto keep this project organized."))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                                HapticButton(action: { showClientPicker = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(L("Add client"))
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 14)
                                    .frame(minWidth: 180)
                                    .background(AppGray.ink)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    } else if selectedTab == .estimate {
                        if !isNewProject {
                            HapticButton { showApacheEstimator = true } label: {
                                Label(L("Smart Service Apache"), systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal, 24)
                        }
                        if !estimatesForDisplay.isEmpty {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L("Estimates"))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(AppGray.ink)
                                        Text(estimatesForDisplay.count == 1 ? L("1 estimate for this project") : L("%@ estimates for this project", estimatesForDisplay.count.formatted()))
                                            .font(.system(size: 15))
                                            .foregroundColor(AppGray.secondary)
                                    }

                                    Spacer()

                                    HapticButton {
                                        openEstimateChat(createNewSession: true)
                                    } label: {
                                        Label(L("New Estimate"), systemImage: "plus")
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

                                ForEach(Array(estimatesForDisplay.enumerated()), id: \.element.id) { index, estimate in
                                    HapticButton {
                                        selectedEstimateDocument = EstimateDocumentSelection(
                                            estimate: estimate,
                                            position: index + 1
                                        )
                                    } label: {
                                        EstimateSummaryCard(estimate: estimate)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                                }
                            }
                        } else {
                            VStack(spacing: 16) {
                                Spacer().frame(height: 60)
                                Text(L("No estimates yet"))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppGray.ink)
                                Text(L("Create a detailed, itemized estimate\nto send to your client."))
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                                HapticButton(action: {
                                    openEstimateChat(createNewSession: true)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(L("Create estimate"))
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 14)
                                        .frame(minWidth: 180)
                                        .background(AppGray.ink)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    } else if selectedTab == .invoices {
                        InvoicesTabContent(
                            projectId: (project != nil || hasPersistedDraft) ? canonicalProjectID : nil,
                            clientId: selectedClient?.id ?? project?.clientId,
                            estimate: confirmedEstimate ?? project?.estimate
                        )
                    } else if selectedTab == .render {
                        if project != nil || hasPersistedDraft {
                            ProjectRenderTabView(project: buildCurrentProject())
                        } else {
                            VStack(spacing: 12) {
                                Spacer().frame(height: 60)
                                Text(L("Save this project first"))
                                    .font(.system(size: 20, weight: .bold))
                                Text(L("Renders are stored securely inside a specific project."))
                                    .font(.system(size: 15))
                                    .foregroundColor(AppGray.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        ProjectDocumentsView(
                            projectID: (project != nil || hasPersistedDraft) ? canonicalProjectID : nil
                        )
                    }

                    if let saveError {
                        Text(L(saveError))
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
        }
        .background(Color.white)
        .navigationBarHidden(true)
        .task(id: (confirmedEstimate ?? project?.estimate)?.supabaseEstimateId) {
            guard let estimateId = (confirmedEstimate ?? project?.estimate)?.supabaseEstimateId else { return }
            do {
                let rows: [EstimateItemRow] = try await supabase
                    .from("estimate_items")
                    .select()
                    .eq("estimate_id", value: estimateId)
                    .execute()
                    .value
                await MainActor.run { sharedSupabaseRows = rows }
            } catch {
                // Non-fatal; UI falls back to in-memory estimate.
            }
        }
        .task(id: canonicalProjectID) {
            do {
                let estimates = try await ProjectRepository.loadEstimates(projectID: canonicalProjectID)
                projectEstimates = estimates
                estimateHistoryLoaded = true
            } catch {
                // Keep the latest in-memory estimate available if history cannot load.
            }
        }
        .sheet(isPresented: $showApacheEstimator) {
            SmartServiceApacheView(projectID: canonicalProjectID)
        }
        .sheet(isPresented: $showClientPicker) {
            ClientPickerSheet { client in
                selectClient(client)
            }
            .presentationDetents([.large])
        }
        .sheet(item: $editingProjectMetadata) { field in
            ProjectMetadataEditor(
                field: field,
                value: field == .address ? $projectAddress : $projectAssignee,
                onSave: {
                    editingProjectMetadata = nil
                    if !isNewProject { buildAndSave() }
                }
            )
            .presentationDetents([.height(245)])
        }
        .fullScreenCover(isPresented: $showEstimateChat) {
            let sessionId = estimateChatSessionId ?? project?.estimateChatSessionId
            ChatView(
                initialSessionId: sessionId,
                projectID: canonicalProjectID,
                onEstimateConfirmed: { rawDict, supaId in
                    acceptGeneratedEstimate(rawDict, supabaseID: supaId)
                }
            )
        }
        .fullScreenCover(isPresented: $showEstimateCreation) {
            let sessionId = estimateChatSessionId ?? project?.estimateChatSessionId
            GuidedEstimateFlowView(
                initialSessionId: sessionId,
                projectID: canonicalProjectID,
                onEstimateConfirmed: { rawDict, supabaseID in
                    acceptGeneratedEstimate(rawDict, supabaseID: supabaseID)
                }
            )
        }
        .sheet(item: $selectedEstimateDocument) { selection in
            EstimateDocumentDetailView(
                estimate: selection.estimate,
                position: selection.position,
                project: buildCurrentProject(),
                projectNumber: displayNumber,
                address: projectAddress.isEmpty ? project?.address : projectAddress,
                client: projectClientForDisplay,
                onUpdated: {
                    updateEstimateInHistory($0)
                    if confirmedEstimate?.supabaseEstimateId == $0.supabaseEstimateId { confirmedEstimate = $0 }
                },
                onSent: { markEstimateSent($0) },
                onDelete: { deleteEstimate($0) }
            )
        }
        .onAppear {
            tabBar.isHidden = true
            // Initialize state from existing project
            if let p = project {
                projectTitle = p.title
                projectAddress = p.address ?? ""
                projectAssignee = p.assignee ?? ""
                projectStatus = p.workflowStatus
                estimateChatSessionId = p.estimateChatSessionId
                confirmedEstimate = p.estimate
                if let est = p.estimate {
                    if projectEstimates.isEmpty { projectEstimates = [est] }
                    estimatePrice = String(format: "%.2f", est.total)
                }
            }
        }
        .onDisappear {
            tabBar.isHidden = false
        }
    }
}

private struct ProjectMetadataEditor: View {
    let field: ProjectMetadataField
    @Binding var value: String
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                navigationHeader

                VStack(alignment: .leading, spacing: 14) {
                    TextField(field.placeholder, text: $value)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .padding(.horizontal, 15)
                        .frame(height: 52)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(AppGray.border, lineWidth: 1)
                        )

                    HapticButton {
                        onSave()
                        dismiss()
                    } label: {
                        Text(L("Save"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppGray.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)

                Spacer(minLength: 0)
            }
            .background(AppGray.bgPale.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(field.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            HStack {
                HapticButton { dismiss() } label: {
                    Text(L("Cancel"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppGray.bgPale)
    }
}

// MARK: - Project Dashboard
private struct ProjectDashboardView: View {
    let projectID: UUID?
    let estimate: Estimate?
    let client: Client?
    let onCreateEstimate: () -> Void
    let onOpenEstimate: () -> Void
    let onOpenInvoices: () -> Void
    let onEstimateSent: (Estimate) -> Void

    @State private var invoiceStore = InvoiceStore.shared
    @State private var paymentStore = PaymentStore.shared
    @State private var showEstimateSendSheet = false
    @State private var showEstimatePDF = false
    @State private var showPaymentsSheet = false
    @State private var paymentSheetStartsWithNewPayment = false
    @State private var estimateSendError: String?

    private let brandBlue = AppBrand.accent

    private enum EstimateStage {
        case missing
        case draft
        case sent
        case accepted
    }

    private var stage: EstimateStage {
        guard let estimate else { return .missing }
        switch estimate.status.lowercased() {
        case "accepted", "approved", "won":
            return .accepted
        case "sent", "viewed", "delivered":
            return .sent
        default:
            return .draft
        }
    }

    private var projectInvoices: [Invoice] {
        guard let projectID else { return [] }
        return invoiceStore.invoices(for: projectID)
    }

    private var invoicedAmount: Double {
        projectInvoices.reduce(0) { $0 + $1.total }
    }

    private var paidAmount: Double {
        guard let projectID else { return 0 }
        return paymentStore.total(for: projectID)
    }

    private var isFullyPaid: Bool {
        invoicedAmount > 0 && paidAmount >= invoicedAmount - 0.005
    }

    private var hasPartialPayment: Bool {
        paidAmount > 0 && !isFullyPaid
    }

    private var estimateShareText: String {
        guard let estimate else { return "" }
        let categoryLines = estimate.categories.map {
            "\($0.name): \(currency($0.subtotal))"
        }
        return """
        \(estimate.title)
        Estimate \(estimate.estimateNumber)

        \(categoryLines.joined(separator: "\n"))

        Total: \(estimate.formattedTotal)
        """
    }

    private var progressStep: Int {
        switch stage {
        case .missing: return 0
        case .draft: return 1
        case .sent: return 2
        case .accepted:
            if isFullyPaid { return 5 }
            if !projectInvoices.isEmpty { return 4 }
            return 3
        }
    }

    private var progressTitle: String {
        switch stage {
        case .missing: return L("Project Created")
        case .draft: return L("Estimate Created")
        case .sent: return L("Estimate Sent")
        case .accepted:
            if isFullyPaid { return L("Payment Collected") }
            if hasPartialPayment { return L("Payment In Progress") }
            if !projectInvoices.isEmpty { return L("Construction Started") }
            return L("Estimate Approved")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let estimate {
                nextActionCard
                milestonesCard
                financialSummary(estimate)

                HStack(alignment: .top, spacing: 12) {
                    paymentsCard
                    changeOrdersCard
                }
            } else {
                dashboardEmptyState
            }
        }
        .sheet(isPresented: $showEstimateSendSheet) {
            if let estimate {
                DocumentSendSheet(
                    document: .estimate(estimate),
                    client: client,
                    onSent: { showEstimateSendSheet = false },
                    onEstimateSent: onEstimateSent
                )
            }
        }
        .sheet(isPresented: $showEstimatePDF) {
            if let estimate {
                DocumentPDFPreviewSheet(
                    document: .estimate(estimate),
                    client: client
                )
            }
        }
        .sheet(isPresented: $showPaymentsSheet) {
            if let projectID {
                PaymentEditorSheet(
                    projectID: projectID,
                    invoicedAmount: invoicedAmount,
                    startsWithNewPayment: paymentSheetStartsWithNewPayment,
                    paymentStore: paymentStore
                )
                .presentationDetents([.large])
            }
        }
        .task {
            async let invoices: Void = invoiceStore.refresh()
            async let payments: Void = paymentStore.refresh()
            _ = await (invoices, payments)
        }
        .alert(
            L("Couldn’t prepare estimate"),
            isPresented: Binding(
                get: { estimateSendError != nil },
                set: { if !$0 { estimateSendError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(estimateSendError ?? "")
        }
    }

    @ViewBuilder
    private var nextActionCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Next Action"))
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppGray.secondary)

                Text(L(nextActionTitle))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            nextActionButton
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 21)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var nextActionTitle: String {
        if !projectInvoices.isEmpty {
            if isFullyPaid { return L("No new actions") }
            if hasPartialPayment { return L("Collect full payment") }
            return L("Add payment received")
        }

        switch stage {
        case .missing: return L("Create the estimate")
        case .draft: return L("Send estimate\nto client")
        case .sent: return L("Waiting for client approval")
        case .accepted:
            return L("Create the first invoice")
        }
    }

    @ViewBuilder
    private var nextActionButton: some View {
        if !projectInvoices.isEmpty && isFullyPaid {
            Text(L("Job completed"))
                .font(.system(size: 13, weight: .medium))
            .foregroundColor(AppGray.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppGray.border, lineWidth: 1)
            )
        } else if !projectInvoices.isEmpty {
            dashboardActionButton(
                title: hasPartialPayment ? L("Collect payment") : L("Add payment"),
                icon: "creditcard",
                action: {
                    paymentSheetStartsWithNewPayment = true
                    showPaymentsSheet = true
                }
            )
        } else {
            switch stage {
            case .missing:
                dashboardActionButton(title: L("Create"), icon: "plus", action: onCreateEstimate)
            case .draft:
                HapticButton {
                    prepareEstimateForSending()
                } label: {
                    dashboardActionLabel(
                        title: L("Send estimate"),
                        trailingIcon: "arrow.up.right",
                        background: AppGray.ink,
                        horizontalPadding: 22,
                        height: 42
                    )
                }
                .buttonStyle(PlainButtonStyle())
            case .sent:
                VStack(spacing: 10) {
                    dashboardActionButton(title: L("View estimate"), icon: "doc", action: { showEstimatePDF = true })
                    HapticButton("Send again", action: prepareEstimateForSending)
                        .font(.system(size: 13, weight: .medium))
                }
            case .accepted:
                dashboardActionButton(
                    title: L("Create invoice"),
                    icon: "creditcard",
                    action: onOpenInvoices
                )
            }
        }
    }

    private func prepareEstimateForSending() {
        guard estimate != nil else { return }
        showEstimateSendSheet = true
    }

    private func dashboardActionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        HapticButton(action: action) {
            dashboardActionLabel(
                title: title,
                trailingIcon: icon,
                background: AppGray.ink
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func dashboardActionLabel(
        title: String,
        icon: String? = nil,
        trailingIcon: String? = nil,
        background: Color? = nil,
        horizontalPadding: CGFloat = 16,
        height: CGFloat = 46
    ) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(L(title))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .background(background ?? brandBlue)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var milestonesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Job Progress"))
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(AppGray.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(L(progressTitle))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Spacer()
                Text(L("%@ of 5", progressStep.formatted()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppGray.ink)
            }
            .padding(.top, 8)

            DashboardSegmentedProgress(step: progressStep)
                .padding(.top, 18)

            Text(L("Next Steps"))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .padding(.top, 24)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                DashboardNextStepRow(
                    title: L("Send Estimate"),
                    status: stage == .draft ? L("Next") : L("Complete"),
                    isNext: stage == .draft
                )
                DashboardNextStepRow(
                    title: L("Client Approval"),
                    status: stage == .accepted ? L("Complete") : L("Waiting"),
                    detail: stage == .sent
                        ? L("The estimate has been sent and is waiting for approval.")
                        : nil
                )
                DashboardNextStepRow(
                    title: L("Begin Construction"),
                    status: {
                        if !projectInvoices.isEmpty { return L("Complete") }
                        return stage == .accepted ? L("Next") : L("Not Started")
                    }(),
                    isNext: stage == .accepted && projectInvoices.isEmpty,
                    detail: stage == .accepted && projectInvoices.isEmpty
                        ? L("The estimate is approved. Create the first invoice to begin billing.")
                        : nil
                )
                DashboardNextStepRow(
                    title: L("Collect Payment"),
                    status: isFullyPaid
                        ? L("Complete")
                        : (!projectInvoices.isEmpty ? L("Next") : L("Upcoming")),
                    isNext: stage == .accepted && !projectInvoices.isEmpty && !isFullyPaid,
                    detail: paidAmount > 0
                        ? (isFullyPaid
                            ? L("%@ collected in full.", "\(currency(paidAmount))")
                            : L("%@ collected; %@ remaining.", "\(currency(paidAmount))", "\(currency(max(invoicedAmount - paidAmount, 0)))"))
                        : nil,
                    showsDivider: false
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func financialSummary(_ estimate: Estimate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("Budget"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Spacer()
                HapticButton("View estimate", action: onOpenEstimate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppGray.secondary)
            }

            HStack(spacing: 0) {
                DashboardMetric(
                    label: L("Project value"),
                    value: estimate.formattedTotal
                )
                DashboardMetric(
                    label: L("Materials cost"),
                    value: currency(estimate.materialsSubtotal)
                )
                DashboardMetric(
                    label: L("Estimated profit"),
                    value: currency(max(estimate.total - estimate.materialsSubtotal, 0))
                )
            }
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var paymentsCard: some View {
        DashboardSummaryCard(
            title: L("Payments"),
            value: currency(paidAmount),
            detail: invoicedAmount > 0
                ? L("%@ invoiced", "\(currency(invoicedAmount))")
                : L("No invoices yet"),
            icon: "creditcard",
            actionTitle: L("Open"),
            action: {
                paymentSheetStartsWithNewPayment = false
                showPaymentsSheet = true
            }
        )
    }

    private var changeOrdersCard: some View {
        DashboardSummaryCard(
            title: L("Change orders"),
            value: "$0.00",
            detail: L("No changes yet"),
            icon: "doc.badge.plus",
            actionTitle: nil,
            action: nil
        )
    }

    private var dashboardEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 28))
                .foregroundColor(AppGray.secondary)
            Text(L("Your project dashboard starts here"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppGray.ink)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(L("Create an estimate to unlock milestones, budget tracking, payments, and change orders."))
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

            HapticButton(action: onCreateEstimate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L("Create estimate"))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .frame(minWidth: 180)
                .background(AppGray.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.vertical, 48)
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

private struct PaymentEditorSheet: View {
    let projectID: UUID
    let invoicedAmount: Double
    let startsWithNewPayment: Bool
    @Bindable var paymentStore: PaymentStore

    @Environment(\.dismiss) private var dismiss
    @State private var editingPaymentID: UUID?
    @State private var selectedMethod = "Cash"
    @State private var amountText = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private let methods = [
        "Cash", "Check", "Zelle", "Square", "Apple Pay", "Venmo",
        "Credit card", "Bank transfer", "Other"
    ]

    private var projectPayments: [Payment] {
        paymentStore.payments(for: projectID)
    }

    private var editingPayment: Payment? {
        guard let editingPaymentID else { return nil }
        return projectPayments.first { $0.id == editingPaymentID }
    }

    private var totalPaid: Double {
        projectPayments.reduce(0) { $0 + $1.amount }
    }

    private var remainingBalance: Double {
        max(invoicedAmount - totalPaid, 0)
    }

    private var enteredAmount: Double? {
        let cleaned = amountText
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    private var maximumAllowedAmount: Double {
        max(invoicedAmount - (totalPaid - (editingPayment?.amount ?? 0)), 0)
    }

    private var amountValidationMessage: String? {
        guard !amountText.isEmpty else { return nil }
        guard let enteredAmount, enteredAmount > 0 else {
            return L("Enter an amount greater than $0.")
        }
        if invoicedAmount > 0 && enteredAmount > maximumAllowedAmount + 0.005 {
            return L("This is more than the remaining invoice balance.")
        }
        return nil
    }

    private var canSave: Bool {
        guard let enteredAmount, enteredAmount > 0 else { return false }
        return !isSaving && (invoicedAmount <= 0 || enteredAmount <= maximumAllowedAmount + 0.005)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !projectPayments.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Received"))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                Text(currency(totalPaid))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(AppGray.ink)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(L("Remaining"))
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                Text(currency(remainingBalance))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(AppGray.ink)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text(L("Payments received"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppGray.textDark)

                            VStack(spacing: 0) {
                                ForEach(projectPayments) { payment in
                                    HapticButton {
                                        edit(payment)
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(L(payment.method))
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(AppGray.ink)
                                                Text(payment.receivedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(appLocale)))
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundColor(AppGray.secondary)
                                            }
                                            Spacer()
                                            Text(currency(payment.amount))
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundColor(AppGray.ink)
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(AppGray.secondary)
                                        }
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if payment.id != projectPayments.last?.id {
                                        Divider()
                                    }
                                }
                            }

                            HapticButton("Add another payment") {
                                beginNewPayment()
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    paymentField(L("Payment method")) {
                        Menu {
                            ForEach(methods, id: \.self) { method in
                                HapticButton(method) { selectedMethod = method }
                            }
                        } label: {
                            HStack {
                                Text(L(selectedMethod))
                                    .foregroundColor(AppGray.secondary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppGray.secondary)
                            }
                            .font(.system(size: 15, weight: .medium))
                        }
                    }

                    paymentField(L("Amount received")) {
                        HStack(spacing: 8) {
                            Text("$")
                                .foregroundColor(AppGray.secondary)
                            TextField("0.00", text: $amountText)
                                .keyboardType(.decimalPad)
                                .foregroundColor(AppGray.secondary)
                        }
                        .font(.system(size: 15, weight: .medium))
                    }

                    if let amountValidationMessage {
                        Text(L(amountValidationMessage))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.red)
                    }

                    if let saveError {
                        Text(L(saveError))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.red)
                    }

                    HapticButton {
                        savePayment()
                    } label: {
                        HStack(spacing: 8) {
                            if isSaving {
                                ProgressView().tint(.white)
                            }
                            Text(editingPayment == nil ? L("Add to total") : L("Save payment"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canSave ? AppGray.ink : AppGray.borderStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!canSave)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .padding(20)
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle(editingPayment == nil ? L("Add Payment") : L("Edit Payment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HapticButton("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if startsWithNewPayment {
                beginNewPayment()
            }
        }
    }

    @ViewBuilder
    private func paymentField<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
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

    private func beginNewPayment() {
        editingPaymentID = nil
        selectedMethod = "Cash"
        amountText = ""
        saveError = nil
    }

    private func edit(_ payment: Payment) {
        editingPaymentID = payment.id
        selectedMethod = payment.method
        amountText = String(format: "%.2f", payment.amount)
        saveError = nil
    }

    private func savePayment() {
        guard let enteredAmount, canSave else { return }
        isSaving = true
        saveError = nil

        let payment = Payment(
            id: editingPayment?.id ?? UUID(),
            organizationId: editingPayment?.organizationId,
            projectId: projectID,
            invoiceId: editingPayment?.invoiceId,
            amount: enteredAmount,
            method: selectedMethod,
            receivedAt: editingPayment?.receivedAt ?? Date(),
            createdAt: editingPayment?.createdAt ?? Date()
        )

        Task {
            do {
                try await paymentStore.save(payment)
                if editingPayment == nil {
                    RetentionCenter.shared.record(.paymentRecorded(amount: enteredAmount))
                }
                dismiss()
            } catch {
                saveError = SafeErrorMessages.data(error, action: "payment save")
                isSaving = false
            }
        }
    }

    private func currency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

private struct DashboardMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L(label))
                .font(.system(size: 11))
                .foregroundColor(AppGray.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppGray.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardSummaryCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.secondary)
                Spacer()
                if let actionTitle, let action {
                    HapticButton(actionTitle, action: action)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppGray.secondary)
                }
            }

            Text(L(title))
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(AppGray.secondary)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(AppGray.ink)
            Text(L(detail))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 145, alignment: .topLeading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct DashboardSegmentedProgress: View {
    let step: Int

    private let lightBlue = AppBrand.accent

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 7
            let barHeight: CGFloat = 7.6
            let segmentWidth = max((proxy.size.width - (gap * 4)) / 5, 0)
            let completedCount = min(max(step, 0), 5)
            let completedWidth = completedCount > 0
                ? (segmentWidth * CGFloat(completedCount)) + (gap * CGFloat(completedCount - 1))
                : 0

            ZStack(alignment: .leading) {
                HStack(spacing: gap) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(
                                index < completedCount
                                    ? lightBlue.opacity(0)
                                    : lightBlue.opacity(
                                        max(
                                            0.34 - (Double(max(index - completedCount, 0)) * 0.07),
                                            0.10
                                        )
                                    )
                            )
                            .frame(width: segmentWidth, height: barHeight)
                    }
                }

                if completedCount > 0 {
                    AppBrand.accent
                    .frame(width: completedWidth, height: barHeight)
                    .mask {
                        HStack(spacing: gap) {
                            ForEach(0..<completedCount, id: \.self) { _ in
                                Capsule()
                                    .frame(width: segmentWidth, height: barHeight)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 7.6)
        .accessibilityLabel(L("Job progress, step %@ of 5", step.formatted()))
    }
}

private struct DashboardNextStepRow: View {
    let title: String
    let status: String
    var isNext: Bool = false
    var detail: String? = nil
    var showsDivider: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L(title))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppGray.ink)

                if let detail, !detail.isEmpty {
                    Text(L(detail))
                        .font(.system(size: 14.3, weight: .regular))
                        .foregroundColor(AppGray.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Text(L(status))
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppGray.secondary)
        }
        .padding(.top, 15)
        .padding(.bottom, 15)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(AppGray.badge)
                    .frame(height: 0.7)
            }
        }
    }
}

// MARK: - Estimate document list and detail

private struct EstimateSummaryCard: View {
    let estimate: Estimate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(estimate.estimateNumber)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(estimate.title.isEmpty ? L("Untitled estimate") : estimate.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(estimate.formattedTotal)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppGray.ink)
                }
            }

            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text(L(estimate.status))
                    if estimate.status.caseInsensitiveCompare("Sent") == .orderedSame {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(AppGray.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(AppGray.border, lineWidth: 1)
                )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

private enum EstimateProposalTab: String, CaseIterable, Identifiable {
    case estimate = "Estimate"
    case plan = "Plan"
    case photos = "Photos"
    case notes = "Notes"

    var id: String { rawValue }
}

private struct EstimateDocumentDetailView: View {
    let estimate: Estimate
    let position: Int
    let project: Project
    let projectNumber: String
    let address: String?
    let client: Client?
    let onUpdated: (Estimate) -> Void
    let onSent: (Estimate) -> Void
    let onDelete: (Estimate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showSendSheet = false
    @State private var isPreparingSend = false
    @State private var sendError: String?
    @State private var showingEstimateOptions = false
    @State private var selectedTab: EstimateProposalTab = .estimate
    @State private var itemRows: [EstimateItemRow]?
    @State private var workPlan: [EstimatePlanSection] = []
    @State private var notes = ""
    @State private var media: [EstimateMedia] = []
    @State private var mediaAssets: [EstimateMediaAsset] = []
    @State private var didLoadProposal = false
    @State private var isSavingProposal = false
    @State private var isGeneratingPlan = false
    @State private var proposalError: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showRenderPicker = false
    @State private var showRenderCreation = false
    @State private var renderIDsBeforeCreation: Set<UUID> = []

    private var remoteEstimateID: UUID? {
        estimate.supabaseEstimateId.flatMap(UUID.init(uuidString:))
    }

    private var proposalEstimate: Estimate {
        var updated = estimate
        updated.workPlan = workPlan
        updated.notes = notes
        return updated
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar
            proposalTabs

            ScrollView(.vertical) {
                Group {
                    switch selectedTab {
                    case .estimate:
                        ItemizedEstimateCard(
                            estimate: proposalEstimate,
                            projectNumber: projectNumber,
                            rows: $itemRows,
                            address: address,
                            onTapEstimate: {},
                            onNewEstimate: {},
                            onViewChat: {}
                        )
                    case .plan:
                        EstimatePlanEditor(
                            sections: $workPlan,
                            isSaving: isSavingProposal,
                            isGenerating: isGeneratingPlan,
                            onSave: saveProposalDetails,
                            onGenerate: { Task { await generateMissingPlan() } }
                        )
                    case .photos:
                        EstimateMediaEditor(
                            media: media,
                            assets: mediaAssets,
                            isWorking: isSavingProposal,
                            photoPickerItem: $photoPickerItem,
                            onImportFile: { showFileImporter = true },
                            onChooseRender: { showRenderPicker = true },
                            onCreateRender: beginRenderCreation,
                            onDelete: deleteMedia
                        )
                    case .notes:
                        EstimateNotesEditor(
                            notes: $notes,
                            isSaving: isSavingProposal,
                            onSave: saveProposalDetails
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 130)
                .containerRelativeFrame(.horizontal, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .background(AppGray.bgPale)
        .safeAreaInset(edge: .bottom) {
            HapticButton { saveEstimateAndClose() } label: {
                HStack(spacing: 8) {
                    if isSavingProposal { ProgressView().tint(.white) }
                    Text(isSavingProposal ? L("Saving…") : L("Save"))
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppGray.ink)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
            .disabled(isSavingProposal || isPreparingSend || isGeneratingPlan)
            .background(Color.white)
        }
        .sheet(isPresented: $showSendSheet) {
            DocumentSendSheet(
                document: .estimate(proposalEstimate),
                client: client,
                estimateMedia: mediaAssets,
                onSent: {
                    showSendSheet = false
                    dismiss()
                },
                onEstimateSent: { sentEstimate in
                    var sent = sentEstimate
                    sent.status = "Sent"
                    onSent(sent)
                }
            )
        }
        .alert(
            L("Couldn’t prepare estimate"),
            isPresented: Binding(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(sendError ?? L("Please try again."))
        }
        .alert(
            L("Couldn’t update estimate"),
            isPresented: Binding(
                get: { proposalError != nil },
                set: { if !$0 { proposalError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(proposalError ?? L("Please try again."))
        }
        .confirmationDialog(L("Estimate Options"), isPresented: $showingEstimateOptions, titleVisibility: .visible) {
            HapticButton("Preview & Send", action: prepareForSending)
                .disabled(isSavingProposal || isPreparingSend)
            HapticButton("Delete Estimate", role: .destructive) {
                onDelete(estimate)
                dismiss()
            }
            HapticButton("Cancel", role: .cancel) {}
        } message: {
            Text(L("Send this estimate or delete it permanently."))
        }
        .task(id: estimate.supabaseEstimateId) {
            guard !didLoadProposal else { return }
            workPlan = estimate.workPlan ?? []
            notes = estimate.notes ?? ""
            didLoadProposal = true
            guard estimate.supabaseEstimateId != nil else { return }
            await refreshItems()
            if workPlan.isEmpty {
                await generateMissingPlan()
            }
            await refreshMedia()
        }
        .onChange(of: photoPickerItem) { _, newValue in
            guard let newValue else { return }
            Task { await importPhoto(newValue) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await importFile(url) }
        }
        .sheet(isPresented: $showRenderPicker) {
            EstimateRenderPicker(
                project: project,
                attachedRenderIDs: Set(media.compactMap(\.renderId)),
                onSelect: { render in
                    showRenderPicker = false
                    Task { await attachRender(render) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showRenderCreation, onDismiss: attachNewlyCreatedRender) {
            RenderCreationView(project: project)
        }
    }

    private var navigationBar: some View {
        ZStack {
            Text(L("Estimate %@", position.formatted()))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            HStack {
                HapticButton { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                HapticButton { showingEstimateOptions = true } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
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
        .background(AppGray.bgPale.ignoresSafeArea(edges: .top))
    }

    private var proposalTabs: some View {
        HStack(spacing: 0) {
            ForEach(EstimateProposalTab.allCases) { tab in
                HapticButton { selectedTab = tab } label: {
                    VStack(spacing: 7) {
                        Text(L(tab.rawValue))
                            .font(.system(size: 17, weight: selectedTab == tab ? .medium : .regular))
                            .foregroundColor(selectedTab == tab ? AppGray.ink : AppGray.secondary)
                        Color.clear
                            .frame(height: 1.6)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .background(AppGray.bgPale)
    }

    private func persistProposalDetails() async throws {
        guard let estimateID = remoteEstimateID else {
            onUpdated(proposalEstimate)
            return
        }
        try await EstimateProposalRepository.updateDetails(
            estimateID: estimateID,
            workPlan: workPlan,
            notes: notes
        )
        onUpdated(proposalEstimate)
    }

    private func saveEstimateAndClose() {
        guard !isSavingProposal else { return }
        isSavingProposal = true
        Task {
            defer { isSavingProposal = false }
            do {
                try await persistProposalDetails()
                proposalError = nil
                dismiss()
            } catch {
                proposalError = SafeErrorMessages.data(error, action: "estimate update")
            }
        }
    }

    private func saveProposalDetails() {
        guard !isSavingProposal else { return }
        isSavingProposal = true
        Task {
            do {
                try await persistProposalDetails()
                proposalError = nil
            } catch {
                proposalError = SafeErrorMessages.data(error, action: "estimate update")
            }
            isSavingProposal = false
        }
    }

    private func refreshMedia() async {
        guard let estimateID = remoteEstimateID else { return }
        do {
            media = try await EstimateProposalRepository.loadMedia(estimateID: estimateID)
            mediaAssets = await loadMediaAssets(media)
        } catch {
            proposalError = SafeErrorMessages.data(error, action: "estimate media refresh")
        }
    }

    private func refreshItems() async {
        guard let estimateID = estimate.supabaseEstimateId else {
            itemRows = nil
            return
        }
        do {
            let loaded: [EstimateItemRow] = try await supabase
                .from("estimate_items")
                .select()
                .eq("estimate_id", value: estimateID)
                .execute()
                .value
            itemRows = loaded
        } catch {
            proposalError = SafeErrorMessages.data(error, action: "estimate item refresh")
        }
    }

    private func generateMissingPlan() async {
        guard !isGeneratingPlan, let estimateID = remoteEstimateID else { return }
        isGeneratingPlan = true
        defer { isGeneratingPlan = false }
        do {
            let generated = try await EstimateProposalRepository.generatePlan(
                projectID: project.id,
                estimateID: estimateID
            )
            workPlan = generated
            var updated = proposalEstimate
            updated.workPlan = generated
            onUpdated(updated)
            proposalError = nil
        } catch {
            proposalError = SafeErrorMessages.data(error, action: "job plan generation")
        }
    }

    private func loadMediaAssets(_ records: [EstimateMedia]) async -> [EstimateMediaAsset] {
        var loaded: [EstimateMediaAsset] = []
        for record in records {
            guard let data = try? await EstimateProposalRepository.data(for: record) else { continue }
            loaded.append(EstimateMediaAsset(
                id: record.id,
                kind: record.kind,
                displayName: record.displayName,
                mimeType: record.mimeType ?? "image/jpeg",
                data: data
            ))
        }
        return loaded
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil }
        guard let estimateID = remoteEstimateID else { return }
        isSavingProposal = true
        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let jpeg = image.jpegData(compressionQuality: 0.88) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try await EstimateProposalRepository.uploadMedia(
                data: jpeg,
                mimeType: "image/jpeg",
                displayName: L("Project photo"),
                kind: "photo",
                projectID: project.id,
                estimateID: estimateID,
                sortOrder: media.count
            )
            await refreshMedia()
        } catch {
            proposalError = SafeErrorMessages.data(error, action: "photo upload")
        }
        isSavingProposal = false
    }

    private func importFile(_ url: URL) async {
        guard let estimateID = remoteEstimateID else { return }
        isSavingProposal = true
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured { url.stopAccessingSecurityScopedResource() }
            isSavingProposal = false
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 50_000_000 else {
                throw CocoaError(.fileReadTooLarge)
            }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                ?? (url.pathExtension.lowercased() == "pdf" ? "application/pdf" : "image/jpeg")
            try await EstimateProposalRepository.uploadMedia(
                data: data,
                mimeType: mimeType,
                displayName: url.lastPathComponent,
                kind: mimeType == "application/pdf" ? "floorplan" : "photo",
                projectID: project.id,
                estimateID: estimateID,
                sortOrder: media.count
            )
            await refreshMedia()
        } catch {
            proposalError = SafeErrorMessages.data(error, action: "estimate file upload")
        }
    }

    private func attachRender(_ render: ProjectRender) async {
        guard let estimateID = remoteEstimateID,
              !media.contains(where: { $0.renderId == render.id }) else { return }
        isSavingProposal = true
        do {
            try await EstimateProposalRepository.attachRender(
                render,
                estimateID: estimateID,
                sortOrder: media.count
            )
            await refreshMedia()
        } catch {
            proposalError = SafeErrorMessages.data(error, action: "render attachment")
        }
        isSavingProposal = false
    }

    private func deleteMedia(_ record: EstimateMedia) {
        guard !isSavingProposal else { return }
        isSavingProposal = true
        Task {
            do {
                try await EstimateProposalRepository.delete(record)
                await refreshMedia()
            } catch {
                proposalError = SafeErrorMessages.data(error, action: "estimate media deletion")
            }
            isSavingProposal = false
        }
    }

    private func beginRenderCreation() {
        SuperwallService.performPremiumAction(
            .createRender,
            params: ["source": "estimate_photos"],
            onFailure: { proposalError = $0 },
            action: beginRenderCreationAfterGate
        )
    }

    private func beginRenderCreationAfterGate() {
        let store = ProjectRenderStore.shared
        renderIDsBeforeCreation = Set(store.renders(for: project.id).map(\.id))
        showRenderCreation = true
    }

    private func attachNewlyCreatedRender() {
        Task {
            let store = ProjectRenderStore.shared
            await store.refresh(projectID: project.id)
            if let created = store.renders(for: project.id).first(where: {
                !renderIDsBeforeCreation.contains($0.id)
            }) {
                await attachRender(created)
            }
        }
    }

    private func prepareForSending() {
        guard !isPreparingSend else { return }
        isPreparingSend = true
        Task {
            do {
                try await persistProposalDetails()
                await refreshMedia()
                showSendSheet = true
            } catch {
                sendError = SafeErrorMessages.data(error, action: "estimate send")
            }
            isPreparingSend = false
        }
    }
}

private struct EstimatePlanEditor: View {
    @Binding var sections: [EstimatePlanSection]
    let isSaving: Bool
    let isGenerating: Bool
    let onSave: () -> Void
    let onGenerate: () -> Void

    @State private var editingSection: EstimatePlanSection?
    @State private var deletingSection: EstimatePlanSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sections.isEmpty {
                VStack(spacing: 10) {
                    if isGenerating {
                        ProgressView()
                            .tint(AppGray.ink)
                        Text(L("Building detailed job plan…"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                        Text(L("AI is organizing the saved scope into process cards and detailed steps."))
                            .font(.system(size: 16))
                            .foregroundColor(AppGray.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 29))
                            .foregroundColor(AppGray.secondary)
                        Text(L("Job plan not generated"))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                        Text(L("Generate the detailed process cards from this estimate’s saved scope."))
                            .font(.system(size: 16))
                            .foregroundColor(AppGray.secondary)
                            .multilineTextAlignment(.center)
                        HapticButton("Generate Plan", action: onGenerate)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 23)
                            .frame(height: 48)
                            .background(AppGray.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 41)
                .padding(.horizontal, 28)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            } else {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 10) {
                            Text(section.title)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(AppGray.ink)
                            Spacer()
                            planIcon("pencil") { editingSection = section }
                            planIcon("trash") { deletingSection = section }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 18.9)
                        .padding(.bottom, 14.4)

                        Rectangle()
                            .fill(AppGray.badge.opacity(0.85))
                            .frame(height: 0.7)

                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(section.steps.enumerated()), id: \.offset) { _, step in
                                HStack(alignment: .top, spacing: 11) {
                                    Circle()
                                        .fill(AppGray.muted.opacity(0.765))
                                        .frame(width: 7, height: 7)
                                        .padding(.top, 8)
                                    Text(step)
                                        .font(.system(size: 16))
                                        .foregroundColor(AppGray.itemText.opacity(0.85))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                        .padding(.bottom, 21)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                }
            }
        }
        .sheet(item: $editingSection) { section in
            PlanSectionEditorSheet(section: section) { saved in
                if let index = sections.firstIndex(where: { $0.id == saved.id }) {
                    sections[index] = saved
                } else {
                    sections.append(saved)
                }
                onSave()
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            L("Delete plan phase?"),
            isPresented: Binding(
                get: { deletingSection != nil },
                set: { if !$0 { deletingSection = nil } }
            ),
            titleVisibility: .visible
        ) {
            HapticButton("Delete Phase", role: .destructive) {
                guard let deletingSection else { return }
                sections.removeAll { $0.id == deletingSection.id }
                self.deletingSection = nil
                onSave()
            }
            HapticButton("Cancel", role: .cancel) { deletingSection = nil }
        }
    }

    private func planIcon(_ name: String, action: @escaping () -> Void) -> some View {
        HapticButton(action: action) {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppGray.ink)
                .frame(width: 37, height: 37)
                .background(AppGray.pill)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }
}

private struct PlanSectionEditorSheet: View {
    let section: EstimatePlanSection
    let onSave: (EstimatePlanSection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var stepsText: String

    init(section: EstimatePlanSection, onSave: @escaping (EstimatePlanSection) -> Void) {
        self.section = section
        self.onSave = onSave
        _title = State(initialValue: section.title)
        _stepsText = State(initialValue: section.steps.joined(separator: "\n"))
    }

    private var steps: [String] {
        stepsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Phase title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                TextField(L("Phase title"), text: $title)
                    .font(.system(size: 16, weight: .medium))
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppGray.border))

                Text(L("Plan steps"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Text(L("Put each bullet point on its own line."))
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
                TextEditor(text: $stepsText)
                    .font(.system(size: 16))
                    .padding(10)
                    .frame(minHeight: 260)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppGray.border))
                Spacer()
            }
            .padding(20)
            .background(AppGray.bgPale.ignoresSafeArea())
            .navigationTitle(section.title.isEmpty ? L("Add Plan Phase") : L("Edit Plan Phase"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    HapticButton("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HapticButton("Save") {
                        onSave(EstimatePlanSection(
                            id: section.id,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            steps: Array(steps.prefix(20))
                        ))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || steps.isEmpty)
                }
            }
        }
    }
}

private struct EstimateNotesEditor: View {
    @Binding var notes: String
    let isSaving: Bool
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Estimate notes"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text(L("Add any notes you want the client to see on the estimate here"))
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(AppGray.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .font(.system(size: 16))
                        .foregroundColor(AppGray.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 260)
                        .padding(12)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                HapticButton(action: onSave) {
                    Text(isSaving ? L("Saving…") : L("Save notes"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppGray.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isSaving || notes.count > 12000)
            }
        }
    }
}

private struct EstimateMediaEditor: View {
    let media: [EstimateMedia]
    let assets: [EstimateMediaAsset]
    let isWorking: Bool
    @Binding var photoPickerItem: PhotosPickerItem?
    let onImportFile: () -> Void
    let onChooseRender: () -> Void
    let onCreateRender: () -> Void
    let onDelete: (EstimateMedia) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Photos & plans"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    mediaAction(title: L("Upload Photo"), icon: "photo")
                }
                .buttonStyle(.plain)

                HapticButton(action: onImportFile) {
                    mediaAction(title: L("Add Floorplan"), icon: "doc")
                }
                .buttonStyle(.plain)

                HapticButton(action: onChooseRender) {
                    mediaAction(title: L("Add Render"), icon: "photo.stack")
                }
                .buttonStyle(.plain)

                HapticButton(action: onCreateRender) {
                    mediaAction(title: L("Create Render"), icon: "sparkles")
                }
                .buttonStyle(.plain)
            }
            .disabled(isWorking)

            if isWorking {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            ForEach(media) { record in
                HStack(spacing: 14) {
                    mediaPreview(record)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                            .lineLimit(2)
                        Text(L(record.kind.capitalized))
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                    Spacer()
                    HapticButton { onDelete(record) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                            .frame(width: 34, height: 34)
                            .background(AppGray.pill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
        }
    }

    private func mediaAction(title: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: .medium))
            Text(L(title))
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(AppGray.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 104)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    @ViewBuilder
    private func mediaPreview(_ record: EstimateMedia) -> some View {
        if let asset = assets.first(where: { $0.id == record.id }),
           let image = asset.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: record.isPDF ? "doc.fill" : "photo")
                .font(.system(size: 20))
                .foregroundColor(AppGray.secondary)
                .frame(width: 64, height: 54)
                .background(AppGray.bgFaint)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct EstimateRenderPicker: View {
    let project: Project
    let attachedRenderIDs: Set<UUID>
    let onSelect: (ProjectRender) -> Void

    @State private var store = ProjectRenderStore.shared
    @Environment(\.dismiss) private var dismiss

    private var available: [ProjectRender] {
        store.renders(for: project.id).filter { !attachedRenderIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                navigationHeader

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if available.isEmpty {
                            Text(L("No unattached renders are available for this project."))
                                .font(.system(size: 15))
                                .foregroundColor(AppGray.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 50)
                        } else {
                            ForEach(available) { render in
                                HapticButton { onSelect(render) } label: {
                                    HStack(spacing: 14) {
                                        EstimateRenderThumbnail(render: render)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(render.initialPrompt)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(AppGray.ink)
                                                .lineLimit(2)
                                            Text(render.isAccepted ? L("Accepted render") : L("Project render"))
                                                .font(.system(size: 13))
                                                .foregroundColor(AppGray.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus")
                                            .foregroundColor(AppGray.ink)
                                    }
                                    .padding(14)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .background(AppGray.bgPale.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.refresh(projectID: project.id) }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(L("Add Render"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            HStack {
                HapticButton { dismiss() } label: {
                    Text(L("Cancel"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassEffect(.clear.tint(Color.white.opacity(0.72)), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(AppGray.bgPale)
    }
}

private struct EstimateRenderThumbnail: View {
    let render: ProjectRender
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AppGray.bgFaint.overlay(ProgressView())
            }
        }
        .frame(width: 70, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .task {
            let path = render.acceptedImagePath ?? render.currentImagePath
            if let data = try? await ProjectRenderRepository.imageData(path: path) {
                image = UIImage(data: data)
            }
        }
    }
}

// MARK: - Itemized Estimate Card (after confirmation)
struct ItemizedEstimateCard: View {
    let estimate: Estimate
    var projectNumber: String = ""
    @Binding var rows: [EstimateItemRow]?
    var address: String? = nil
    let onTapEstimate: () -> Void
    let onNewEstimate: () -> Void
    let onViewChat: () -> Void

    /// Categories the user has collapsed. Empty by default → all open.
    @State private var collapsedCategories: Set<String> = []
    @State private var editingCategories: Set<String> = []
    @State private var editingRow: EstimateItemRow? = nil
    @State private var addingCategory: String? = nil
    @State private var confirmDeleteCategory: String? = nil
    @State private var loadError: String? = nil

    private var supabaseRows: [EstimateItemRow]? { rows }

    /// Total recomputed from live Supabase rows when available; otherwise the
    /// estimate's stored total. Re-runs every time the view appears, so edits
    /// made in the Materials tab show up when the user returns to Overview.
    /// Categories rebuilt from Supabase rows (grouped by `category` field).
    /// Falls back to the in-memory estimate categories only when Supabase
    /// hasn't loaded yet (first render) or for legacy estimates without a
    /// `supabaseEstimateId`.
    private var liveCategories: [EstimateCategory] {
        guard let rows = supabaseRows else { return estimate.categories }
        let groups = Dictionary(grouping: rows) { $0.category ?? "Other" }
        let orderedNames = rows.reduce(into: [String]()) { acc, r in
            let key = r.category ?? "Other"
            if !acc.contains(key) { acc.append(key) }
        }
        return orderedNames.map { name in
            let groupRows = groups[name] ?? []
            let items = groupRows.map { r in
                EstimateLineItem(
                    name: r.name,
                    quantity: r.quantity,
                    unitLabel: r.unit_label ?? "ea",
                    unitPrice: r.unit_price,
                    total: r.total,
                    source: r.source,
                    url: r.url,
                    onHand: r.on_hand
                )
            }
            let subtotal = items.reduce(0) { $0 + $1.total }
            return EstimateCategory(name: name, items: items, subtotal: subtotal)
        }
    }

    private var liveSubtotal: Double {
        liveCategories.reduce(0) { $0 + $1.subtotal }
    }

    private var liveTotalText: String {
        let markup = liveSubtotal * (estimate.markupPercent / 100.0)
        let contingency = estimate.contingency?.amount ?? 0
        let total = liveSubtotal + markup + contingency
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: total)) ?? estimate.formattedTotal
    }


    private let darkText = AppGray.ink
    private let brandBlue = AppBrand.accent

    private func formatted(_ value: Double) -> String {
        guard value != 0 else { return "N/A" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "N/A"
    }

    private var isMaterials: (EstimateCategory) -> Bool {
        { $0.name.lowercased().contains("material") }
    }

    private func sourceURL(from source: String?) -> URL? {
        guard let s = source, !s.isEmpty else { return nil }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(s.startIndex..., in: s)
            if let match = detector.firstMatch(in: s, range: range), let url = match.url {
                return url
            }
        }
        return nil
    }

    // MARK: - Editable display model (carries DB row ids when available)

    private struct DisplayItem: Identifiable {
        let id: String
        let rowId: String?
        let item: EstimateLineItem
    }
    private struct DisplayGroup: Identifiable {
        let id: String
        let name: String
        let items: [DisplayItem]
        let subtotal: Double
    }

    private var displayGroups: [DisplayGroup] {
        if let rows = supabaseRows {
            var order: [String] = []
            for r in rows {
                let key = r.category ?? "Other"
                if !order.contains(key) { order.append(key) }
            }
            return order.map { name in
                let grpRows = rows.filter { ($0.category ?? "Other") == name }
                let items = grpRows.map { r in
                    DisplayItem(
                        id: r.id,
                        rowId: r.id,
                        item: EstimateLineItem(
                            name: r.name, quantity: r.quantity, unitLabel: r.unit_label ?? "ea",
                            unitPrice: r.unit_price, total: r.total, source: r.source, url: r.url,
                            description: r.description, onHand: r.on_hand
                        )
                    )
                }
                return DisplayGroup(id: name, name: name, items: items,
                                    subtotal: grpRows.reduce(0) { $0 + $1.total })
            }
        }
        return estimate.categories.map { cat in
            let items = cat.items.enumerated().map { idx, it in
                DisplayItem(id: "\(cat.name)-\(idx)", rowId: nil, item: it)
            }
            return DisplayGroup(id: cat.name, name: cat.name, items: items, subtotal: cat.subtotal)
        }
    }

    private func insertItem(_ item: EstimateLineItem, into category: String) async {
        guard let estId = estimate.supabaseEstimateId else {
            await MainActor.run { loadError = L("Save the estimate before adding items.") }
            return
        }
        struct NewItem: Encodable {
            let estimate_id: String
            let category: String
            let name: String
            let quantity: Double
            let unit_label: String
            let unit_price: Double
            let total: Double
            let description: String?
            let on_hand: Bool
        }
        do {
            // Preserve the complete server list even if the review screen's
            // initial row load is still finishing.
            let existingRows: [EstimateItemRow]
            if let rows {
                existingRows = rows
            } else {
                existingRows = try await supabase
                    .from("estimate_items")
                    .select()
                    .eq("estimate_id", value: estId)
                    .execute()
                    .value
            }

            let saved: EstimateItemRow = try await supabase
                .from("estimate_items")
                .insert(NewItem(
                    estimate_id: estId,
                    category: category,
                    name: item.name,
                    quantity: item.quantity,
                    unit_label: item.unitLabel,
                    unit_price: item.unitPrice,
                    total: item.total,
                    description: item.description,
                    on_hand: item.onHand
                ))
                .select()
                .single()
                .execute()
                .value
            await MainActor.run {
                rows = existingRows + [saved]
                addingCategory = nil
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = SafeErrorMessages.data(error, action: "item addition")
            }
        }
    }

    private func deleteCategory(_ name: String) async {
        guard let estId = estimate.supabaseEstimateId else { return }
        do {
            try await supabase
                .from("estimate_items")
                .delete()
                .eq("estimate_id", value: estId)
                .eq("category", value: name)
                .execute()
            await MainActor.run {
                rows = (rows ?? []).filter { ($0.category ?? "Other") != name }
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = SafeErrorMessages.data(error, action: L("%@ deletion", L(name)))
            }
        }
    }

    private func saveEdit(rowId: String, updated: EstimateLineItem) async {
        struct ItemPatch: Encodable {
            let name: String
            let quantity: Double
            let unit_price: Double
            let total: Double
            let description: String?
        }
        do {
            let saved: EstimateItemRow = try await supabase
                .from("estimate_items")
                .update(ItemPatch(name: updated.name, quantity: updated.quantity,
                                  unit_price: updated.unitPrice, total: updated.total,
                                  description: updated.description))
                .eq("id", value: rowId)
                .select()
                .single()
                .execute()
                .value
            await MainActor.run {
                if var current = rows, let idx = current.firstIndex(where: { $0.id == rowId }) {
                    current[idx] = saved
                    rows = current
                }
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = SafeErrorMessages.data(error, action: "estimate save")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Category rows (header · items · total) ───────────
            ForEach(displayGroups) { group in
                let isOpen = !collapsedCategories.contains(group.name)
                let editable = estimate.supabaseEstimateId != nil

                VStack(spacing: 0) {
                // ── Category header ──
                HStack(spacing: 6) {
                    Text(L(group.name))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(AppGray.ink)
                    Text(group.items.count == 1 ? L("1 item") : L("%@ items", group.items.count.formatted()))
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(AppGray.secondary)

                    Spacer()

                    if editable {
                        HapticButton {
                            addingCategory = group.name
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                                .frame(width: 35, height: 35)
                        }
                        .buttonStyle(PlainButtonStyle())

                        HapticButton {
                            confirmDeleteCategory = group.name
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                                .frame(width: 35, height: 35)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    HapticButton {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if isOpen { collapsedCategories.insert(group.name) }
                            else { collapsedCategories.remove(group.name) }
                        }
                    } label: {
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                            .frame(width: 28, height: 35)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.white)

                if isOpen {
                    Rectangle()
                        .fill(AppGray.badge.opacity(0.85))
                        .frame(height: 0.7)

                    // ── Items ──
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, display in
                            if index > 0 {
                                Rectangle()
                                    .fill(AppGray.badge.opacity(0.85))
                                    .frame(height: 0.7)
                            }

                            let item = display.item
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top) {
                                    Text(item.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(AppGray.ink)
                                    Spacer()
                                    Text(formatted(item.total))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(AppGray.ink)
                                }

                                let inEdit = editingCategories.contains(group.name)
                                if item.unitPrice != 0 || (inEdit && display.rowId != nil) {
                                    HStack(alignment: .center) {
                                        if item.unitPrice != 0 {
                                            Text("\(item.quantity.formatted(.number.precision(.fractionLength(0...2)))) \(item.unitLabel) × \(formatted(item.unitPrice))")
                                                .font(.system(size: 16, weight: .regular))
                                                .foregroundColor(AppGray.secondary)
                                                .padding(.leading, 3)
                                        }
                                        Spacer()
                                        if inEdit, let rowId = display.rowId {
                                            HapticButton {
                                                editingRow = rows?.first(where: { $0.id == rowId })
                                            } label: {
                                                Text(L("Edit"))
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(AppGray.secondary)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 9)
                                                    .background(Color.white)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .strokeBorder(AppGray.border, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.top, 9)
                                }

                                if let url = sourceURL(from: item.source) {
                                    Link(destination: url) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(L("Visit site"))
                                                .font(.system(size: 14, weight: .medium))
                                        }
                                        .foregroundColor(brandBlue)
                                        .padding(.top, 2)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard editingCategories.contains(group.name),
                                      let rowId = display.rowId else { return }
                                editingRow = rows?.first(where: { $0.id == rowId })
                            }
                        }
                    }
                    .background(Color.white)

                    // ── Add / Edit items row ──
                    if editable {
                        HStack(spacing: 10) {
                            HapticButton {
                                addingCategory = group.name
                            } label: {
                                Text(L("Add item"))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppGray.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(hex: 0xF6F6F7))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PlainButtonStyle())

                            HapticButton {
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) {
                                    if editingCategories.contains(group.name) {
                                        editingCategories.remove(group.name)
                                    } else {
                                        editingCategories.insert(group.name)
                                    }
                                }
                            } label: {
                                Text(editingCategories.contains(group.name) ? L("Done") : L("Edit items"))
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(AppGray.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color(hex: 0xF6F6F7))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                        .background(Color.white)
                    }

                    // ── Category total footer (mirrors the header) ──
                    Rectangle()
                        .fill(AppGray.badge.opacity(0.85))
                        .frame(height: 0.7)

                    HStack {
                        Text(L("Total"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(AppGray.ink)
                        Spacer()
                        Text(formatted(group.subtotal))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                    }
                    .frame(minHeight: 30)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.white)
                }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)

                if group.id != displayGroups.last?.id {
                    Color.clear.frame(height: 12)
                }
            }

            if let loadError {
                Text(L(loadError))
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            // ── Totals card (cost adders + recommended quote) ──
            EstimateExtrasView(estimate: estimate).adders
        }
        .sheet(item: $editingRow) { row in
            MaterialEditSheet(
                item: EstimateLineItem(
                    name: row.name, quantity: row.quantity, unitLabel: row.unit_label ?? "ea",
                    unitPrice: row.unit_price, total: row.total, source: row.source, url: row.url,
                    description: row.description, onHand: row.on_hand
                ),
                onSave: { updated in
                    _Concurrency.Task<Void, Never> { await saveEdit(rowId: row.id, updated: updated) }
                    editingRow = nil
                }
            )
        }
        .sheet(
            isPresented: Binding(
                get: { addingCategory != nil },
                set: { if !$0 { addingCategory = nil } }
            )
        ) {
            MaterialEditSheet(
                title: "Add Item",
                item: EstimateLineItem(
                    name: "",
                    quantity: 1,
                    unitLabel: "ea",
                    unitPrice: 0,
                    total: 0
                ),
                onSave: { newItem in
                    guard let category = addingCategory else { return }
                    addingCategory = nil
                    _Concurrency.Task<Void, Never> {
                        await insertItem(newItem, into: category)
                    }
                }
            )
        }
        .confirmationDialog(
            L("Delete %@ and its items?", "\(confirmDeleteCategory ?? "")"),
            isPresented: Binding(
                get: { confirmDeleteCategory != nil },
                set: { if !$0 { confirmDeleteCategory = nil } }
            ),
            titleVisibility: .visible
        ) {
            HapticButton("Delete", role: .destructive) {
                if let name = confirmDeleteCategory {
                    _Concurrency.Task<Void, Never> { await deleteCategory(name) }
                }
                confirmDeleteCategory = nil
            }
            HapticButton("Cancel", role: .cancel) { confirmDeleteCategory = nil }
        }
    }
}

// MARK: - Recommended Quote Row (plain row matching the other category/adder rows)

struct RecommendedQuoteRow: View {
    let total: String

    private let darkGray = AppGray.itemText

    var body: some View {
        HStack {
            Text(L("Recommended Quote"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(darkGray)
            Spacer()
            Text(total)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkGray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(AppGray.bgDropdown)
    }
}

// MARK: - Invoices Tab Content
struct InvoicesTabContent: View {
    let projectId: UUID?
    let clientId: UUID?
    let estimate: Estimate?

    @State private var store = InvoiceStore.shared
    @State private var editingInvoice: Invoice? = nil
    @State private var subscriptionError: String?

    private let brandBlue = AppBrand.accent

    private var invoices: [Invoice] {
        guard let projectId else { return [] }
        return store.invoices(for: projectId)
    }

    var body: some View {
        VStack(spacing: 16) {
            if projectId == nil {
                VStack(spacing: 12) {
                    Spacer().frame(height: 60)
                    Text(L("Save this project first"))
                        .font(.system(size: 20, weight: .bold))
                    Text(L("Every invoice must be connected to one project."))
                        .font(.system(size: 15))
                        .foregroundColor(AppGray.secondary)
                }
            } else if invoices.isEmpty {
                VStack(spacing: 16) {
                    Spacer().frame(height: 60)
                    Text(L("No invoices yet"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppGray.ink)
                    Text(L("Bill your client for completed work\nand collect payment."))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(AppGray.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    HapticButton(action: {
                        if estimate != nil { createFromEstimate() } else { createBlank() }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text(L("Create invoice"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .frame(minWidth: 180)
                            .background(AppGray.ink)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            } else {
                invoiceHeaderCard

                ForEach(invoices) { invoice in
                    HapticButton(action: { editingInvoice = invoice }) {
                        InvoiceSummaryCard(invoice: invoice)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
                }
            }
        }
        .sheet(item: $editingInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(invoice: invoice) { saved in
                    if store.invoices.contains(where: { $0.id == saved.id }) {
                        store.update(saved)
                    } else {
                        store.add(saved)
                    }
                }
            }
        }
        .task {
            await store.refresh()
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

    private var invoiceHeaderCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Invoices"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Text(invoices.count == 1 ? L("1 invoice for this project") : L("%@ invoices for this project", invoices.count.formatted()))
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.secondary)
            }

            Spacer()

            Menu {
                if estimate != nil {
                    HapticButton("Create from estimate", action: createFromEstimate)
                }
                HapticButton("Blank invoice", action: createBlank)
            } label: {
                Label(L("Create Invoice"), systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(AppGray.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 21)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func createFromEstimate() {
        guard let estimate else { return }
        SuperwallService.performPremiumAction(
            .createInvoice,
            params: ["source": "project_invoice_tab", "template": "estimate"],
            onFailure: { subscriptionError = $0 },
            action: { createFromEstimateAfterGate(estimate) }
        )
    }

    private func createFromEstimateAfterGate(_ estimate: Estimate) {
        let invoice = Invoice.from(
            estimate: estimate,
            projectId: projectId,
            clientId: clientId,
            number: store.nextNumber
        )
        store.add(invoice)
        editingInvoice = invoice
    }

    private func createBlank() {
        SuperwallService.performPremiumAction(
            .createInvoice,
            params: ["source": "project_invoice_tab", "template": "blank"],
            onFailure: { subscriptionError = $0 },
            action: createBlankAfterGate
        )
    }

    private func createBlankAfterGate() {
        var invoice = Invoice.createNew(number: store.nextNumber)
        invoice.projectId = projectId
        invoice.clientId = clientId
        store.add(invoice)
        editingInvoice = invoice
    }
}

// MARK: - Invoice Summary Card (list row)
struct InvoiceSummaryCard: View {
    let invoice: Invoice

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Paid":  return Color(red: 0.18, green: 0.49, blue: 0.20)
        case "Sent":  return AppGray.secondary
        default:      return AppGray.secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(invoice.invoiceNumber)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)

                // Title + price on the same axis
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(invoice.title.isEmpty ? L("Untitled invoice") : invoice.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Spacer()
                    Text(invoice.formattedTotal)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                }
            }

            // Status pill + chevron at the bottom, on the same axis
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 6) {
                    Text(L(invoice.status))
                    if invoice.status.caseInsensitiveCompare("Sent") == .orderedSame {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                    .font(.system(size: 13))
                    .foregroundColor(statusColor(invoice.status))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
            }
            .padding(.top, 3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(Color.white)
        .contentShape(Rectangle())
    }
}

// MARK: - Detail Tag Pill
struct DetailTagPill: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppGray.secondary)
            Text(L(text))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppGray.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(AppGray.border, lineWidth: 1)
        )
    }
}

// MARK: - Client Details Card
struct ClientDetailsCard: View {
    let client: Client
    let onChangeClient: () -> Void

    private var detailRows: [(label: String, value: String)] {
        [
            (L("Company"), client.company),
            (L("Email"), client.email),
            (L("Phone Number"), client.phone),
            (L("Address"), client.address)
        ].filter { !$0.value.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Client Details"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppGray.secondary)

                    Text(client.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .padding(.top, -2)
                }

                Spacer()

                HapticButton(action: onChangeClient) {
                    Text(L("Change"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppGray.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(AppGray.border, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(detailRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L(row.label))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppGray.itemText)
                        Text(row.value)
                            .font(.system(size: 15))
                            .foregroundColor(AppGray.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 30)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Materials Tab Content

/// One row from Supabase's `estimate_items` table.
struct EstimateItemRow: Identifiable, Codable {
    let id: String
    let estimate_id: String
    let category: String?
    var name: String
    var quantity: Double
    let unit_label: String?
    var unit_price: Double
    var total: Double
    let source: String?
    let url: String?
    var description: String?
    let on_hand: Bool
}

#Preview("Existing Project") {
    NavigationStack {
        ProjectDetailView(project: Project(
            projectNumber: "PRJ-10000",
            title: "Kitchen Cabinets & Countertops",
            price: 26198.64,
            status: "Lead",
            clientName: nil,
            address: nil
        ), onSave: nil, onUpdate: nil)
    }
    .environment(TabBarVisibility())
}

#Preview("New Project") {
    NavigationStack {
        ProjectDetailView(project: nil, onSave: nil, onUpdate: nil)
    }
    .environment(TabBarVisibility())
}
