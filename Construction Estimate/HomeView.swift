//
//  HomeView.swift
//  Construction Estimate
//
//

import SwiftUI

// MARK: - Main Home View
struct HomeView: View {

    @State private var selectedTab: String = "All"
    @State private var aiText: String = ""
    @State private var showNewProject: Bool = false
    @State private var store = ProjectStore.shared
    @State private var cardsAppeared: Bool = false

    let filterTabs = ["All", "Draft", "Bidding", "Sent", "Approved", "Completed"]

    var projects: [Project] { store.projects }

    // Counts per tab
    var tabCounts: [String: Int] {
        var counts: [String: Int] = [:]
        counts["All"] = projects.count
        for tab in filterTabs where tab != "All" {
            counts[tab] = projects.filter { $0.workflowStatus == tab }.count
        }
        return counts
    }

    var filteredProjects: [Project] {
        if selectedTab == "All" { return projects }
        return projects.filter { $0.workflowStatus == selectedTab }
    }

    var nextProjectNumber: String {
        let base = 10000 + projects.count
        return "PRJ-\(base)"
    }

    func loadProjects() {
        Task { await store.refresh() }
    }

    func addProject(_ project: Project) {
        store.add(project)
    }

    func deleteProject(_ project: Project) {
        store.delete(project)
    }

    func updateProject(_ updated: Project) {
        store.update(updated)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // MARK: - Top Icons Row
                TopNavBar(onNewTapped: { showNewProject = true })
                
                // MARK: - "Projects" Title
                HStack {
                    Text("Projects")
                        .font(.system(size: 32, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                
                // MARK: - Filter Tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filterTabs, id: \.self) { tab in
                            FilterTabButton(
                                title: tab,
                                count: tabCounts[tab] ?? 0,
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
                
                // MARK: - Scrollable Content
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(filteredProjects.enumerated()), id: \.element.id) { index, project in
                            HapticNavigationLink(destination: ProjectDetailView(
                                project: project,
                                onSave: nil,
                                onUpdate: { updated in updateProject(updated) }
                            )) {
                                ProjectCardView(project: project, onDelete: { deleteProject(project) })
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(cardsAppeared ? 1 : 0)
                            .scaleEffect(cardsAppeared ? 1 : 0.96)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.75)
                                    .delay(0.25 + Double(index) * 0.1),
                                value: cardsAppeared
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 140)
                }
            }
        }
        .fullScreenCover(isPresented: $showNewProject) {
            NavigationStack {
                ProjectDetailView(project: nil, onSave: { newProject in
                    addProject(newProject)
                    showNewProject = false
                })
            }
        }
        .onAppear {
            loadProjects()
            cardsAppeared = false
            DispatchQueue.main.async { cardsAppeared = true }
        }
    }
}

// MARK: - Filter Tab HapticButton
struct FilterTabButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        HapticButton(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? AppBrand.accent : AppGray.secondary)
                
                // Badge count
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .white : AppGray.secondary)
                    .frame(width: 22, height: 22)
                    .background(isSelected ? AppBrand.accent : AppGray.pill)
                    .clipShape(Circle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? AppBrand.accent.opacity(0.08) : Color.white)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? AppBrand.accent.opacity(0.3) : AppGray.border, lineWidth: 1)
            )
        }
    }
}

// MARK: - Next Steps Banner
struct NextStepsBanner: View {
    var body: some View {
        HStack(spacing: 14) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(AppGray.badge, lineWidth: 4)
                    .frame(width: 50, height: 50)
                
                Circle()
                    .trim(from: 0, to: 0.2) // 1/5
                    .stroke(AppBrand.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))
                
                Text("1/5")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Next steps")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                
                Text("Complete your onboarding")
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppGray.muted)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppBrand.accent.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppBrand.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Project Card View
struct ProjectCardView: View {
    let project: Project
    var onDelete: (() -> Void)? = nil
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(alignment: .top) {
                Text(project.projectNumber)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)

                Spacer()

                HapticButton(action: { showDeleteConfirm = true }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(AppGray.secondary)
                        .rotationEffect(.degrees(90))
                        .frame(width: 28, height: 28)
                }
                .confirmationDialog("Project Options", isPresented: $showDeleteConfirm) {
                    HapticButton("Delete Project", role: .destructive) { onDelete?() }
                    HapticButton("Cancel", role: .cancel) {}
                }
            }
            
            // Title
            Text(project.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
            
            // Price
            Text(project.formattedPrice)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
                .padding(.bottom, 4)
            
            // Tags row
            FlowLayout(spacing: 8) {
                TagPill(icon: "circle.dotted", text: project.workflowStatus)
                TagPill(icon: "person", text: project.clientName ?? "Client")
                AddressTagPill(text: project.address ?? "Address")
            }
            
            // Assignee row
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppGray.secondary)
                Text(project.assignee ?? "No assignee")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppGray.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AppGray.border, lineWidth: 1)
            )
        }
        .padding(23)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 5)
    }
}

// MARK: - Tag Pill
struct TagPill: View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppGray.border, lineWidth: 1)
        )
    }
}

// MARK: - Address Tag Pill (uses custom location pin image)
struct AddressTagPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppGray.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppGray.border, lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout (wrapping tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }
        
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Bottom Tab Bar
struct BottomTabBar: View {
    @Binding var selectedIndex: Int
    
    let tabs: [(icon: String, label: String)] = [
        ("house.fill", "Home"),
        ("folder.fill", "Projects"),
        ("person.2.fill", "Clients")
    ]
    
    private let brandBlue = AppBrand.accent

    var body: some View {
        HStack {
            ForEach(0..<tabs.count, id: \.self) { index in
                Spacer()

                HapticButton(action: {
                    selectedIndex = index
                }) {
                    VStack(spacing: 4) {
                        Image(systemName: tabs[index].icon)
                            .font(.system(size: 20))
                        Text(tabs[index].label)
                            .font(.system(size: 11, weight: selectedIndex == index ? .semibold : .regular))
                    }
                    .foregroundColor(selectedIndex == index ? brandBlue : AppGray.ink)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
        }
        .padding(.top, 15)
        .padding(.bottom, 20)
        .background(
            Color.white
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }
}

#Preview {
    ContentView()
}
