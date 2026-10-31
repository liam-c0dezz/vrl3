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
    var title: String { self == .address ? "Project address" : "Assignee" }
    var placeholder: String { self == .address ? "Enter address" : "Enter assignee name" }
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
    @State private var estimateDescription: String = ""
    @State private var estimatePrice: String = ""
    @State private var estimateExpanded: Bool = true
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
        let fallbackTitle = project?.title ?? confirmedEstimate?.title ?? "Untitled Project"
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
        let title = projectTitle.isEmpty ? (project?.title ?? "Untitled Project") : projectTitle
        if createNewSession {
            estimateChatSessionId = ChatSession.createAndSave(name: "Estimate – \(title)")
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
                saveError = SafeErrorMessages.data(error, action: "project deletion")
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
                HapticButton(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }

                // Save / + button
                if isNewProject {
                    HapticButton(action: buildAndSave) {
                        Text("Save")
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
                    HapticButton(action: {}) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(AppBrand.accent)
                            .clipShape(Circle())
                    }
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

                TextField("Untitled project", text: $projectTitle)
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
                    DetailTagPill(icon: "circle.dotted", text: projectStatus)
                    HapticButton { editingProjectMetadata = .address } label: {
                        HStack(spacing: 4) {
                            Text(projectAddress.isEmpty ? "Address" : projectAddress)
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
                            Text(projectAssignee.isEmpty ? "No assignee" : projectAssignee)
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
                                Text(tab.rawValue)
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
                                Text("No client yet")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppGray.ink)
                                Text("Add the client you're working with\nto keep this project organized.")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                                HapticButton(action: { showClientPicker = true }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Add client")
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
                                Label("Smart Service Apache", systemImage: "sparkles")
                            }
                            .buttonStyle(.bordered)
                            .padding(.horizontal, 24)
                        }
                        if !estimatesForDisplay.isEmpty {
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Estimates")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(AppGray.ink)
                                        Text("\(estimatesForDisplay.count) estimate\(estimatesForDisplay.count == 1 ? "" : "s") for this project")
                                            .font(.system(size: 15))
                                            .foregroundColor(AppGray.secondary)
                                    }

                                    Spacer()

                                    HapticButton {
                                        openEstimateChat(createNewSession: true)
                                    } label: {
                                        Label("New Estimate", systemImage: "plus")
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
                                Text("No estimates yet")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(AppGray.ink)
                                Text("Create a detailed, itemized estimate\nto send to your client.")
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
                                        Text("Create estimate")
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
                                Text("Save this project first")
                                    .font(.system(size: 20, weight: .bold))
                                Text("Renders are stored securely inside a specific project.")
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
                        Text(saveError)
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
                        Text("Save")
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
                    Text("Cancel")
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
        case .missing: return "Project Created"
        case .draft: return "Estimate Created"
        case .sent: return "Estimate Sent"
        case .accepted:
            if isFullyPaid { return "Payment Collected" }
            if hasPartialPayment { return "Payment In Progress" }
            if !projectInvoices.isEmpty { return "Construction Started" }
            return "Estimate Approved"
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
            "Couldn’t prepare estimate",
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
                Text("Next Action")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(AppGray.secondary)

                Text(nextActionTitle)
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
            if isFullyPaid { return "No new actions" }
            if hasPartialPayment { return "Collect full payment" }
            return "Add payment received"
        }

        switch stage {
        case .missing: return "Create the estimate"
        case .draft: return "Send estimate\nto client"
        case .sent: return "Waiting for client approval"
        case .accepted:
            return "Create the first invoice"
        }
    }

    @ViewBuilder
    private var nextActionButton: some View {
        if !projectInvoices.isEmpty && isFullyPaid {
            Text("Job completed")
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
                title: hasPartialPayment ? "Collect payment" : "Add payment",
                icon: "creditcard",
                action: {
                    paymentSheetStartsWithNewPayment = true
                    showPaymentsSheet = true
                }
            )
        } else {
            switch stage {
            case .missing:
                dashboardActionButton(title: "Create", icon: "plus", action: onCreateEstimate)
            case .draft:
                HapticButton {
                    prepareEstimateForSending()
                } label: {
                    dashboardActionLabel(
                        title: "Send estimate",
                        trailingIcon: "arrow.up.right",
                        background: AppGray.ink,
                        horizontalPadding: 22,
                        height: 42
                    )
                }
                .buttonStyle(PlainButtonStyle())
            case .sent:
                VStack(spacing: 10) {
                    dashboardActionButton(title: "View estimate", icon: "doc", action: { showEstimatePDF = true })
                    HapticButton("Send again", action: prepareEstimateForSending)
                        .font(.system(size: 13, weight: .medium))
                }
            case .accepted:
                dashboardActionButton(
                    title: "Create invoice",
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
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
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
            Text("Job Progress")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(AppGray.secondary)

            HStack(alignment: .firstTextBaseline) {
                Text(progressTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Spacer()
                Text("\(progressStep) of 5")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppGray.ink)
            }
            .padding(.top, 8)

            DashboardSegmentedProgress(step: progressStep)
                .padding(.top, 18)

            Text("Next Steps")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .padding(.top, 24)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                DashboardNextStepRow(
                    title: "Send Estimate",
                    status: stage == .draft ? "Next" : "Complete",
                    isNext: stage == .draft
                )
                DashboardNextStepRow(
                    title: "Client Approval",
                    status: stage == .accepted ? "Complete" : "Waiting",
                    detail: stage == .sent
                        ? "The estimate has been sent and is waiting for approval."
                        : nil
                )
                DashboardNextStepRow(
                    title: "Begin Construction",
                    status: {
                        if !projectInvoices.isEmpty { return "Complete" }
                        return stage == .accepted ? "Next" : "Not Started"
                    }(),
                    isNext: stage == .accepted && projectInvoices.isEmpty,
                    detail: stage == .accepted && projectInvoices.isEmpty
                        ? "The estimate is approved. Create the first invoice to begin billing."
                        : nil
                )
                DashboardNextStepRow(
                    title: "Collect Payment",
                    status: isFullyPaid
                        ? "Complete"
                        : (!projectInvoices.isEmpty ? "Next" : "Upcoming"),
                    isNext: stage == .accepted && !projectInvoices.isEmpty && !isFullyPaid,
                    detail: paidAmount > 0
                        ? (isFullyPaid
                            ? "\(currency(paidAmount)) collected in full."
                            : "\(currency(paidAmount)) collected; \(currency(max(invoicedAmount - paidAmount, 0))) remaining.")
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
                Text("Budget")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Spacer()
                HapticButton("View estimate", action: onOpenEstimate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppGray.secondary)
            }

            HStack(spacing: 0) {
                DashboardMetric(
                    label: "Project value",
                    value: estimate.formattedTotal
                )
                DashboardMetric(
                    label: "Materials cost",
                    value: currency(estimate.materialsSubtotal)
                )
                DashboardMetric(
                    label: "Estimated profit",
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
            title: "Payments",
            value: currency(paidAmount),
            detail: invoicedAmount > 0
                ? "\(currency(invoicedAmount)) invoiced"
                : "No invoices yet",
            icon: "creditcard",
            actionTitle: "Open",
            action: {
                paymentSheetStartsWithNewPayment = false
                showPaymentsSheet = true
            }
        )
    }

    private var changeOrdersCard: some View {
        DashboardSummaryCard(
            title: "Change orders",
            value: "$0.00",
            detail: "No changes yet",
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
            Text("Your project dashboard starts here")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppGray.ink)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Create an estimate to unlock milestones, budget tracking, payments, and change orders.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 8)

            HapticButton(action: onCreateEstimate) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Create estimate")
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
            return "Enter an amount greater than $0."
        }
        if invoicedAmount > 0 && enteredAmount > maximumAllowedAmount + 0.005 {
            return "This is more than the remaining invoice balance."
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
                                Text("Received")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                Text(currency(totalPaid))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(AppGray.ink)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Remaining")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(AppGray.secondary)
                                Text(currency(remainingBalance))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(AppGray.ink)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Payments received")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppGray.textDark)

                            VStack(spacing: 0) {
                                ForEach(projectPayments) { payment in
                                    HapticButton {
                                        edit(payment)
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(payment.method)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundColor(AppGray.ink)
                                                Text(payment.receivedAt.formatted(date: .abbreviated, time: .omitted))
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

                    paymentField("Payment method") {
                        Menu {
                            ForEach(methods, id: \.self) { method in
                                HapticButton(method) { selectedMethod = method }
                            }
                        } label: {
                            HStack {
                                Text(selectedMethod)
                                    .foregroundColor(AppGray.secondary)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppGray.secondary)
                            }
                            .font(.system(size: 15, weight: .medium))
                        }
                    }

                    paymentField("Amount received") {
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
                        Text(amountValidationMessage)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.red)
                    }

                    if let saveError {
                        Text(saveError)
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
                            Text(editingPayment == nil ? "Add to total" : "Save payment")
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
            .navigationTitle(editingPayment == nil ? "Add Payment" : "Edit Payment")
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
            Text(title)
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
            Text(label)
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

            Text(title)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(AppGray.secondary)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(AppGray.ink)
            Text(detail)
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
        .accessibilityLabel("Job progress, step \(step) of 5")
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
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppGray.ink)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14.3, weight: .regular))
                        .foregroundColor(AppGray.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Text(status)
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

// MARK: - New Estimate Card (empty state for new projects)
struct NewEstimateCard: View {
    let hasSession: Bool
    let onCreateEstimate: () -> Void
    let onViewEstimate: () -> Void

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            Text("AI-powered estimates")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(AppGray.ink)
                .multilineTextAlignment(.center)

            Text("Quickly create detailed, professional proposals and impress your customers with speed and accuracy.")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(AppGray.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .padding(.bottom, 8)

            if hasSession {
                HapticButton(action: onViewEstimate) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 13, weight: .regular))
                        Text("View estimate")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(AppGray.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                HapticButton(action: onCreateEstimate) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Create estimate")
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
                    Text(estimate.title.isEmpty ? "Untitled estimate" : estimate.title)
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
                    Text(estimate.status)
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
                    Text(isSavingProposal ? "Saving…" : "Save")
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
            "Couldn’t prepare estimate",
            isPresented: Binding(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(sendError ?? "Please try again.")
        }
        .alert(
            "Couldn’t update estimate",
            isPresented: Binding(
                get: { proposalError != nil },
                set: { if !$0 { proposalError = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(proposalError ?? "Please try again.")
        }
        .confirmationDialog("Estimate Options", isPresented: $showingEstimateOptions, titleVisibility: .visible) {
            HapticButton("Preview & Send", action: prepareForSending)
                .disabled(isSavingProposal || isPreparingSend)
            HapticButton("Delete Estimate", role: .destructive) {
                onDelete(estimate)
                dismiss()
            }
            HapticButton("Cancel", role: .cancel) {}
        } message: {
            Text("Send this estimate or delete it permanently.")
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
            Text("Estimate \(position)")
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
                        Text(tab.rawValue)
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
                displayName: "Project photo",
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
                        Text("Building detailed job plan…")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                        Text("AI is organizing the saved scope into process cards and detailed steps.")
                            .font(.system(size: 16))
                            .foregroundColor(AppGray.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 29))
                            .foregroundColor(AppGray.secondary)
                        Text("Job plan not generated")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppGray.ink)
                        Text("Generate the detailed process cards from this estimate’s saved scope.")
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
            "Delete plan phase?",
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
                Text("Phase title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                TextField("Example: Removal and disposal", text: $title)
                    .font(.system(size: 16, weight: .medium))
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AppGray.border))

                Text("Plan steps")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Text("Put each bullet point on its own line.")
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
            .navigationTitle(section.title.isEmpty ? "Add Plan Phase" : "Edit Plan Phase")
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
            Text("Estimate notes")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)

            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Add any notes you want the client to see on the estimate here")
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
                    Text(isSaving ? "Saving…" : "Save notes")
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
            Text("Photos & plans")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    mediaAction(title: "Upload Photo", icon: "photo")
                }
                .buttonStyle(.plain)

                HapticButton(action: onImportFile) {
                    mediaAction(title: "Add Floorplan", icon: "doc")
                }
                .buttonStyle(.plain)

                HapticButton(action: onChooseRender) {
                    mediaAction(title: "Add Render", icon: "photo.stack")
                }
                .buttonStyle(.plain)

                HapticButton(action: onCreateRender) {
                    mediaAction(title: "Create Render", icon: "sparkles")
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
                        Text(record.kind.capitalized)
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
            Text(title)
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
                            Text("No unattached renders are available for this project.")
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
                                            Text(render.isAccepted ? "Accepted render" : "Project render")
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
            Text("Add Render")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            HStack {
                HapticButton { dismiss() } label: {
                    Text("Cancel")
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
            await MainActor.run { loadError = "Save the estimate before adding items." }
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
                loadError = SafeErrorMessages.data(error, action: "\(name) deletion")
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
                    Text(group.name)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(AppGray.ink)
                    Text("\(group.items.count) item\(group.items.count == 1 ? "" : "s")")
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
                                                Text("Edit")
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
                                            Text("Visit site")
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
                                Text("Add item")
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
                                Text(editingCategories.contains(group.name) ? "Done" : "Edit items")
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
                        Text("Total")
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
                Text(loadError)
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
            "Delete \(confirmDeleteCategory ?? "") and its items?",
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
            Text("Recommended Quote")
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

// MARK: - Itemized Estimate Detail View
struct ItemizedEstimateView: View {
    let estimate: Estimate
    var onViewChat: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var expandedCategories: Set<UUID> = []
    @State private var allCollapsed: Bool = false

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack(spacing: 14) {
                HapticButton(action: { dismiss() }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(AppGray.badge)
                        .clipShape(Circle())
                }
                Spacer()
                HapticButton(action: {}) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(AppGray.badge)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text(estimate.estimateNumber)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
                Text(estimate.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Toolbar
            HStack {
                HapticButton(action: {
                    allCollapsed.toggle()
                    if allCollapsed {
                        expandedCategories = []
                    } else {
                        expandedCategories = Set(estimate.categories.map(\.id))
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: allCollapsed ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12))
                        Text(allCollapsed ? "Expand all" : "Collapse all")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppGray.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            // Categories
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(estimate.categories) { category in
                        EstimateCategorySection(
                            category: category,
                            isExpanded: expandedCategories.contains(category.id),
                            onToggle: {
                                if expandedCategories.contains(category.id) {
                                    expandedCategories.remove(category.id)
                                } else {
                                    expandedCategories.insert(category.id)
                                }
                            }
                        )
                    }

                    EstimateExtrasView(estimate: estimate)
                }
                .padding(.bottom, 120)
            }

            Spacer()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total with markup")
                            .font(.system(size: 12))
                            .foregroundColor(AppGray.secondary)
                        Text(estimate.formattedTotal)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(brandBlue)
                    }
                    Spacer()
                    if let onViewChat {
                        HapticButton(action: onViewChat) {
                            HStack(spacing: 6) {
                                Text("View chat")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                AppBrand.accent
                            )
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(UIColor.systemBackground))
            }
        }
        .background(Color.white)
        .onAppear {
            // Start with all expanded
            expandedCategories = Set(estimate.categories.map(\.id))
        }
    }
}

// MARK: - Estimate Category Section
private struct EstimateCategorySection: View {
    let category: EstimateCategory
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Category header
            HapticButton(action: onToggle) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                        Text("\(category.items.count) items")
                            .font(.system(size: 13))
                            .foregroundColor(AppGray.secondary)
                    }
                    Spacer()
                    Text(formatCurrency(category.subtotal))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppGray.muted)
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(isExpanded ? AppGray.bgSubtle : Color.white)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded line items
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(category.items) { item in
                        VStack(spacing: 0) {
                            Divider().padding(.leading, 20)
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.black)
                                    if item.unitPrice != 0 {
                                        Text("\(formatQty(item.quantity)) x \(formatCurrency(item.unitPrice)) / \(item.unitLabel)")
                                            .font(.system(size: 13))
                                            .foregroundColor(AppGray.subtle)
                                    }
                                    if let url = sourceURLValue(item.source) {
                                        Link(destination: url) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.right.square")
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text("Visit site")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                            .foregroundColor(AppBrand.accent)
                                            .padding(.top, 2)
                                        }
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(formatCurrency(item.total))
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.black)
                                    if let source = item.source, !source.isEmpty {
                                        Text(source)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(AppGray.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.white)
                                            .clipShape(Capsule())
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(AppGray.border, lineWidth: 1)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                    }
                }
                .background(AppGray.bgSubtle)
            }

            Divider()
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        guard value != 0 else { return "N/A" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "N/A"
    }

    private func formatQty(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func sourceURLValue(_ source: String?) -> URL? {
        guard let s = source, !s.isEmpty else { return nil }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(s.startIndex..., in: s)
            if let match = detector.firstMatch(in: s, range: range), let url = match.url {
                return url
            }
        }
        return nil
    }
}

// MARK: - Estimate Card
struct EstimateCard: View {
    @Binding var estimateDescription: String
    @Binding var estimatePrice: String
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HapticButton(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppBrand.accent)
                    
                    Text("Estimate")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                    
                    Spacer()
                    
                    if !estimatePrice.isEmpty {
                        Text("$\(estimatePrice)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppBrand.accent)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppGray.muted)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                        
                        TextField("Describe the job...", text: $estimateDescription, axis: .vertical)
                            .font(.system(size: 15))
                            .lineLimit(3...6)
                            .padding(12)
                            .background(AppGray.bgFaint)
                            .cornerRadius(10)
                    }
                    
                    // Price
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Price")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                        
                        HStack {
                            Text("$")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(AppGray.secondary)
                            
                            TextField("0.00", text: $estimatePrice)
                                .font(.system(size: 16))
                                .keyboardType(.decimalPad)
                        }
                        .padding(12)
                        .background(AppGray.bgFaint)
                        .cornerRadius(10)
                    }
                    
                    // Create with Handoff AI - green gradient pill
                    HapticButton(action: {}) {
                        Text("Create with Handoff AI")
                            .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            AppBrand.accent
                        )
                        .clipShape(Capsule())
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
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
                    Text("Save this project first")
                        .font(.system(size: 20, weight: .bold))
                    Text("Every invoice must be connected to one project.")
                        .font(.system(size: 15))
                        .foregroundColor(AppGray.secondary)
                }
            } else if invoices.isEmpty {
                VStack(spacing: 16) {
                    Spacer().frame(height: 60)
                    Text("No invoices yet")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppGray.ink)
                    Text("Bill your client for completed work\nand collect payment.")
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
                            Text("Create invoice")
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
    }

    private var invoiceHeaderCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Invoices")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Text("\(invoices.count) invoice\(invoices.count == 1 ? "" : "s") for this project")
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
                Label("Create Invoice", systemImage: "plus")
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

// MARK: - Create Invoice Card (empty state)
struct CreateInvoiceCard: View {
    let hasEstimate: Bool
    let onCreateFromEstimate: () -> Void
    let onBlank: () -> Void

    private let brandBlue = AppBrand.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 28)

            // Title + subtitle
            VStack(spacing: 10) {
                Text("Create an invoice")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)

                Text(hasEstimate
                     ? "Turn your estimate into an itemized\ninvoice and send it to your client\nto get paid."
                     : "Bill your client for completed work\nand collect payment.")
                    .font(.system(size: 15))
                    .foregroundColor(AppGray.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)

            // Actions
            if hasEstimate {
                HapticButton(action: onCreateFromEstimate) {
                    Text("Create from estimate")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(brandBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)
                }
                .buttonStyle(PlainButtonStyle())

                HapticButton(action: onBlank) {
                    Text("Start blank")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(AppGray.secondary)
                        .padding(.vertical, 12)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            } else {
                HapticButton(action: onBlank) {
                    Text("Create invoice")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppGray.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(AppGray.border, lineWidth: 1)
                        )
                        .padding(.horizontal, 50)
                        .padding(.bottom, 10)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer().frame(height: 12)
            }
        }
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
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
                    Text(invoice.title.isEmpty ? "Untitled invoice" : invoice.title)
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
                    Text(invoice.status)
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
            Text(text)
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

// MARK: - Job Context Card (for new projects)
struct JobContextCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add job context")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(AppBrand.accent)
                
                Spacer()
                
                HapticButton(action: {}) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppGray.secondary)
                }
            }
            
            Text("Better context in → better estimates out")
                .font(.system(size: 14))
                .foregroundColor(AppGray.secondary)
            
            // Action items. Recording and live walkthroughs are intentionally
            // not offered in the first release.
            VStack(alignment: .leading, spacing: 18) {
                JobContextRow(icon: "photo", text: "Attach job photos")
                JobContextRow(icon: "arrow.up.doc", text: "Upload project files")
            }
        }
        .padding(20)
        .background(AppBrand.accent.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(AppBrand.accent.opacity(0.15), lineWidth: 1)
        )
    }
}

struct JobContextRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.black)
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppGray.muted)
        }
    }
}

// MARK: - Client Details Card
struct ClientDetailsCard: View {
    let client: Client
    let onChangeClient: () -> Void

    private var detailRows: [(label: String, value: String)] {
        [
            ("Company", client.company),
            ("Email", client.email),
            ("Phone Number", client.phone),
            ("Address", client.address)
        ].filter { !$0.value.isEmpty }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Client Details")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppGray.secondary)

                    Text(client.name)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                        .padding(.top, -2)
                }

                Spacer()

                HapticButton(action: onChangeClient) {
                    Text("Change")
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
                        Text(row.label)
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

// MARK: - Add Client Card (for new projects)
struct AddClientCard: View {
    let selectedClient: Client?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let client = selectedClient {
                // Selected state — show client row + change button
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AppGray.badge)
                            .frame(width: 44, height: 44)
                        Text(client.initials)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppGray.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                        if !client.company.isEmpty {
                            Text(client.company)
                                .font(.system(size: 13))
                                .foregroundColor(AppGray.secondary)
                        } else if !client.phone.isEmpty {
                            Text(client.phone)
                                .font(.system(size: 13))
                                .foregroundColor(AppGray.secondary)
                        }
                    }
                    Spacer()
                    HapticButton(action: onTap) {
                        Text("Change")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.clear)
                            .overlay(
                                Capsule()
                                    .strokeBorder(AppGray.borderStrong, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(20)
            } else {
                // Empty state — centered icon, title, subtitle, stroke button
                VStack(spacing: 0) {
                    Spacer().frame(height: 28)

                    // Title + subtitle
                    VStack(spacing: 10) {
                        Text("Add a client")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.center)

                        Text("Add client information to keep track of\nwho you are working with\nand stay organized")
                            .font(.system(size: 15))
                            .foregroundColor(AppGray.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)

                    // Stroke button
                    HapticButton(action: onTap) {
                        Text("Add client")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppGray.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(AppGray.border, lineWidth: 1)
                            )
                            .padding(.horizontal, 50)
                            .padding(.bottom, 10)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer().frame(height: 20)
                }
            }
        }
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

struct ClientInputField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(AppGray.secondary)
                .frame(width: 20)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .keyboardType(keyboard)
        }
        .padding(12)
        .background(AppGray.bgFaint)
        .cornerRadius(10)
    }
}

// MARK: - Add Contact Sheet
struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var email: String = ""
    @State private var company: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(AppGray.badge)
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 32))
                                .foregroundColor(AppGray.borderStrong)
                        }
                        .padding(.top, 20)
                        
                        // Form Fields
                        VStack(spacing: 16) {
                            ContactField(label: "Name", text: $name, icon: "person")
                            ContactField(label: "Phone", text: $phone, icon: "phone")
                            ContactField(label: "Email", text: $email, icon: "envelope")
                            ContactField(label: "Company", text: $company, icon: "building.2")
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .navigationTitle("Add Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HapticButton("Cancel") { dismiss() }
                        .foregroundColor(AppGray.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HapticButton("Save") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppBrand.accent)
                }
            }
        }
    }
}

struct ContactField: View {
    let label: String
    @Binding var text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppGray.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(AppGray.secondary)
                
                TextField(label, text: $text)
                    .font(.system(size: 16))
            }
        }
        .padding(14)
        .background(AppGray.bgFaint)
        .cornerRadius(12)
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

struct MaterialsTabContent: View {
    let estimate: Estimate
    @Binding var rows: [EstimateItemRow]?

    private var supabaseRows: [EstimateItemRow]? {
        get { rows }
    }
    @State private var loadError: String? = nil
    @State private var editingPriceIndex: Int? = nil
    @State private var editingPriceText: String = ""
    @State private var showingPriceEdit: Bool = false

    private let titleText = AppGray.ink
    private let rowText = AppGray.itemText
    private let labelGray = AppGray.secondary

    private func formatted(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formattedQty(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private var materials: [EstimateLineItem] {
        if let rows = supabaseRows, !rows.isEmpty {
            return rows.map { r in
                EstimateLineItem(
                    name: r.name,
                    quantity: r.quantity,
                    unitLabel: r.unit_label ?? "ea",
                    unitPrice: r.unit_price,
                    total: r.total,
                    source: r.source,
                    url: r.url,
                    description: r.description,
                    onHand: r.on_hand
                )
            }
        }
        return estimate.materials
    }
    private var subtotal: Double {
        if let rows = supabaseRows, !rows.isEmpty {
            return materials.reduce(0) { $0 + $1.total }
        }
        return estimate.materialsSubtotal
    }
    private var onHandCount: Int { materials.filter { $0.onHand }.count }

    private func adjustQty(at index: Int, delta: Double) async {
        guard var current = rows, current.indices.contains(index) else { return }
        let newQty = max(0, current[index].quantity + delta)
        let newTotal = newQty * current[index].unit_price
        let rowId = current[index].id

        struct ItemPatch: Encodable { let quantity: Double; let total: Double }
        do {
            let saved: EstimateItemRow = try await supabase
                .from("estimate_items")
                .update(ItemPatch(quantity: newQty, total: newTotal))
                .eq("id", value: rowId)
                .select()
                .single()
                .execute()
                .value
            current[index] = saved
            await MainActor.run {
                self.rows = current
                self.loadError = nil
            }
        } catch {
            await MainActor.run {
                self.loadError = SafeErrorMessages.data(error, action: "material change")
            }
        }
    }

    private func saveItemEdit(at index: Int, updated: EstimateLineItem) async {
        guard var current = rows, current.indices.contains(index) else { return }
        let rowId = current[index].id

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
                .update(ItemPatch(
                    name: updated.name,
                    quantity: updated.quantity,
                    unit_price: updated.unitPrice,
                    total: updated.total,
                    description: updated.description
                ))
                .eq("id", value: rowId)
                .select()
                .single()
                .execute()
                .value
            current[index] = saved
            await MainActor.run {
                self.rows = current
                self.loadError = nil
            }
        } catch {
            await MainActor.run {
                self.loadError = SafeErrorMessages.data(error, action: "material change")
            }
        }
    }

    private func editUnitPrice(at index: Int, newPrice: Double) async {
        guard var current = rows, current.indices.contains(index) else { return }
        let newTotal = newPrice * current[index].quantity
        let rowId = current[index].id
        struct PricePatch: Encodable { let unit_price: Double; let total: Double }
        do {
            let saved: EstimateItemRow = try await supabase
                .from("estimate_items")
                .update(PricePatch(unit_price: newPrice, total: newTotal))
                .eq("id", value: rowId)
                .select()
                .single()
                .execute()
                .value
            current[index] = saved
            await MainActor.run {
                self.rows = current
                self.loadError = nil
            }
        } catch {
            await MainActor.run {
                self.loadError = SafeErrorMessages.data(error, action: "material change")
            }
        }
    }

    var body: some View {
        if materials.isEmpty {
            VStack(spacing: 16) {
                Spacer().frame(height: 60)
                Text("No materials on this estimate")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppGray.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // ── Header ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("Materials")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(labelGray)
                    Text(estimate.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(titleText)
                        .padding(.top, -2)
                    HStack(spacing: 8) {
                        headerButton(icon: "plus", label: "Add") {}
                        Text("\(materials.count) items")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(labelGray)
                    }
                    .padding(.top, 6)
                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

                Rectangle()
                    .fill(AppGray.badge)
                    .frame(height: 0.7)

                // ── Material rows ───────────────────────────────────
                VStack(spacing: 0) {
                    ForEach(Array(materials.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle()
                                .fill(AppGray.badge)
                                .frame(height: 0.7)
                        }
                        MaterialRow(
                            item: item,
                            qtyText: formattedQty(item.quantity),
                            unitPriceText: formatted(item.unitPrice),
                            totalText: formatted(item.total),
                            onMinus: supabaseRows == nil ? nil : {
                                _Concurrency.Task<Void, Never> { await adjustQty(at: idx, delta: -1) }
                            },
                            onPlus: supabaseRows == nil ? nil : {
                                _Concurrency.Task<Void, Never> { await adjustQty(at: idx, delta: 1) }
                            },
                            onEditUnitPrice: supabaseRows == nil ? nil : {
                                editingPriceText = String(format: "%.2f", item.unitPrice)
                                editingPriceIndex = idx
                                showingPriceEdit = true
                            },
                            onAdjustUnitPrice: supabaseRows == nil ? nil : { delta in
                                let newPrice = max(0, item.unitPrice + delta)
                                _Concurrency.Task<Void, Never> { await editUnitPrice(at: idx, newPrice: newPrice) }
                            },
                            onSaveItem: supabaseRows == nil ? nil : { updated in
                                _Concurrency.Task<Void, Never> { await saveItemEdit(at: idx, updated: updated) }
                            }
                        )
                    }
                }

                Rectangle()
                    .fill(AppGray.badge)
                    .frame(height: 0.7)

                // ── Subtotal footer ─────────────────────────────────
                HStack {
                    Text("Subtotal")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(labelGray)
                    Spacer()
                    Text(formatted(subtotal))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            .alert("Edit Labor Rate", isPresented: $showingPriceEdit) {
                TextField("0.00", text: $editingPriceText)
                    .keyboardType(.decimalPad)
                HapticButton("Save") {
                    let clean = editingPriceText
                        .replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: ",", with: "")
                    if let price = Double(clean), let idx = editingPriceIndex {
                        _Concurrency.Task<Void, Never> { await editUnitPrice(at: idx, newPrice: price) }
                    }
                    showingPriceEdit = false
                }
                HapticButton("Cancel", role: .cancel) { showingPriceEdit = false }
            } message: {
                Text("Enter the hourly rate")
            }

            if onHandCount > 0 {
                Text("\(onHandCount) of \(materials.count) marked on hand")
                    .font(.system(size: 12))
                    .foregroundColor(labelGray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func headerButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        HapticButton(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(labelGray)
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
}

private struct MaterialRow: View {
    let item: EstimateLineItem
    let qtyText: String
    let unitPriceText: String
    let totalText: String
    var onMinus: (() -> Void)? = nil
    var onPlus: (() -> Void)? = nil
    var onEditUnitPrice: (() -> Void)? = nil
    var onAdjustUnitPrice: ((Double) -> Void)? = nil
    var onSaveItem: ((EstimateLineItem) -> Void)? = nil

    @State private var showEdit = false

    private var isLabor: Bool {
        let l = item.unitLabel.lowercased()
        return l == "hr" || l == "hrs" || l == "hour" || l == "hours"
    }

    private var hasURL: Bool {
        if let u = item.url, !u.isEmpty, URL(string: u) != nil { return true }
        return false
    }

    private let rowText = AppGray.ink
    private let subtleGray = AppGray.secondary
    private let onHandGreen = Color(red: 0.20, green: 0.50, blue: 0.27)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: name on left, price/control on right
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(rowText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if item.onHand {
                    Text("On Hand")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(onHandGreen)
                } else if !isLabor {
                    Text(unitPriceText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(rowText)
                }
            }

            // Bottom row: quantity stepper, labor rate / Order link
            HStack(spacing: 10) {
                quantityStepper
                Spacer()
                if isLabor && !item.onHand {
                    laborRateControl
                } else {
                    HapticButton(action: { showEdit = true }) {
                        Text("Edit Line")
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
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .sheet(isPresented: $showEdit) {
            MaterialEditSheet(item: item, onSave: { updated in
                onSaveItem?(updated)
                showEdit = false
            })
        }
    }

    private var laborRateControl: some View {
        HStack(spacing: 0) {
            HapticButton(action: { onAdjustUnitPrice?(-10) }) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
                    .frame(width: 36)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(onAdjustUnitPrice == nil)

            HapticButton(action: { onEditUnitPrice?() }) {
                HStack(spacing: 3) {
                    Text(unitPriceText)
                        .font(.system(size: 15, weight: .semibold))
                    Text("/ hr")
                        .font(.system(size: 13))
                }
                .foregroundColor(rowText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())

            HapticButton(action: { onAdjustUnitPrice?(10) }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
                    .frame(width: 36)
                    .frame(maxHeight: .infinity)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(onAdjustUnitPrice == nil)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppGray.border, lineWidth: 1)
        )
    }

    private var quantityStepper: some View {
        HStack(spacing: 0) {
            HapticButton(action: { onMinus?() }) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(onMinus == nil)

            Text(qtyText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppGray.secondary)
                .frame(minWidth: 32)

            HapticButton(action: { onPlus?() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(onPlus == nil)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppGray.border, lineWidth: 1)
        )
    }

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
