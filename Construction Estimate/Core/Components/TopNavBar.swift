//
//  TopNavBar.swift
//  Construction Estimate
//
//

import SwiftUI

struct TopNavBar: View {
    var onNewTapped: (() -> Void)? = nil
    @State private var notificationStore = NotificationStore.shared
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var showProjectSearch = false
    @State private var pendingSearchedProject: Project?
    @State private var selectedSearchedProject: Project?
    @State private var showSearchedProject = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Settings gear
            HapticButton {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    showSettings = true
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(AppGray.pill)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false))
            }
            .buttonStyle(.plain)
            
            // Notification bell
            HapticButton { showNotifications = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false))

                    if notificationStore.unreadCount > 0 {
                        Text(notificationStore.unreadCount > 9 ? "9+" : "\(notificationStore.unreadCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(AppBrand.accent)
                            .clipShape(Capsule())
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Search
            HapticButton { showProjectSearch = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(AppGray.pill)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false))
            }
            .padding(.trailing, 8)

            // + New button
            HapticButton(action: { onNewTapped?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                    Text(L("New"))
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .background(AppBrand.accent)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .task {
            notificationStore.startPolling()
            await notificationStore.refresh()
        }
        .onChange(of: AppRouter.shared.pending, initial: true) { _, route in
            switch route {
            case .notifications?:
                AppRouter.shared.pending = nil
                showNotifications = true
            case .settings?:
                AppRouter.shared.pending = nil
                showSettings = true
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: $showNotifications) {
            NotificationsView()
        }
        .sheet(isPresented: $showProjectSearch, onDismiss: openPendingSearchedProject) {
            ProjectSearchSheet { project in
                pendingSearchedProject = project
                showProjectSearch = false
            }
                .presentationDetents([.medium, .large])
        }
        .navigationDestination(isPresented: $showSearchedProject) {
            if let project = selectedSearchedProject {
                ProjectDetailView(
                    project: project,
                    onSave: nil,
                    onUpdate: { ProjectStore.shared.update($0) }
                )
            }
        }
    }

    private func openPendingSearchedProject() {
        guard let project = pendingSearchedProject else { return }
        pendingSearchedProject = nil
        selectedSearchedProject = project
        showSearchedProject = true
    }
}

private struct ProjectSearchSheet: View {
    let onSelect: (Project) -> Void
    @State private var store = ProjectStore.shared
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var matches: [Project] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return store.projects.filter {
            $0.title.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                navigationHeader

                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(AppGray.secondary)
                        TextField(L("Search project title"), text: $query)
                            .font(.system(size: 16))
                            .foregroundColor(AppGray.ink)
                            .textInputAutocapitalization(.words)
                    }
                    .padding(.horizontal, 15)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(AppGray.border, lineWidth: 1)
                    )

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(L("Type a project title to search."))
                            .font(.system(size: 14))
                            .foregroundColor(AppGray.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if matches.isEmpty {
                        Text(L("No matching projects."))
                            .font(.system(size: 14))
                            .foregroundColor(AppGray.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(matches) { project in
                                    HapticButton { onSelect(project) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(project.title)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(AppGray.ink)
                                                Text(project.projectNumber)
                                                    .font(.system(size: 13))
                                                    .foregroundColor(AppGray.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(AppGray.secondary)
                                        }
                                        .padding(16)
                                        .background(Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .background(AppGray.bgPale.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await store.refresh() }
    }

    private var navigationHeader: some View {
        ZStack {
            Text(L("Search projects"))
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
