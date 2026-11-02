import SwiftUI
import MessageUI

struct DashboardHomeView: View {
    let onOpenProjects: () -> Void

    @State private var projectStore = ProjectStore.shared
    @State private var invoiceStore = InvoiceStore.shared
    @State private var businessStore = BusinessSettingsStore.shared
    @State private var showNewProject = false
    @State private var projectAction: ProjectQuickCreateAction?
    @State private var businessSetupDestination: BusinessSetupDestination?
    @State private var isGettingStartedExpanded = true
    @State private var subscriptionError: String?

    private let brandBlue = AppBrand.accent

    private var estimates: [Estimate] {
        projectStore.projects.compactMap(\.estimate)
    }

    private func estimateCount(for status: HomeEstimateStatus) -> Int {
        estimates.filter { status.matches($0.status) }.count
    }

    private func invoiceCount(for status: String) -> Int {
        invoiceStore.invoices.filter {
            $0.status.caseInsensitiveCompare(status) == .orderedSame
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
                TopNavBar(onNewTapped: { showNewProject = true })

                HStack {
                    Text(L("Home"))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppGray.ink)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        if gettingStartedCompletedCount < 4 {
                            gettingStartedSection
                        }
                        quickCreateSection
                        estimatesSection
                        invoicesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 140)
                }
        }
        .fullScreenCover(isPresented: $showNewProject) {
            NavigationStack {
                ProjectDetailView(project: nil, onSave: { project in
                    projectStore.add(project)
                    showNewProject = false
                })
            }
        }
        .fullScreenCover(item: $projectAction) { action in
            ProjectActionPickerView(action: action)
        }
        .sheet(item: $businessSetupDestination) { destination in
            switch destination {
            case .business:
                BusinessSetupView()
            case .hourlyRates:
                NavigationStack {
                    HourlyRatesSetupView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                HapticButton("Cancel") { businessSetupDestination = nil }
                            }
                        }
                }
            case .upsells:
                NavigationStack {
                    BusinessUpsellsSetupView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                HapticButton("Cancel") { businessSetupDestination = nil }
                            }
                        }
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
        .task {
            async let projects: Void = projectStore.refresh()
            async let invoices: Void = invoiceStore.refresh()
            async let business: Void = businessStore.refresh()
            _ = await (projects, invoices, business)
        }
    }

    private var gettingStartedCompletedCount: Int {
        [
            businessStore.profile.isSetupComplete,
            !businessStore.hourlyRates.isEmpty,
            !estimates.isEmpty,
            estimates.contains { estimate in
                ["sent", "viewed", "delivered", "accepted", "approved", "won"]
                    .contains(estimate.status.lowercased())
            }
        ].filter { $0 }.count
    }

    private var gettingStartedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Getting Started"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)

            VStack(spacing: 0) {
                HapticButton {
                    isGettingStartedExpanded.toggle()
                } label: {
                    HStack(spacing: 14) {
                        Text(L("%@ of 4", gettingStartedCompletedCount.formatted()))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color.white)
                            .fixedSize()

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.3))
                                Capsule()
                                    .fill(Color.white)
                                    .frame(
                                        width: proxy.size.width
                                            * CGFloat(gettingStartedCompletedCount) / 4
                                    )
                            }
                        }
                        .frame(height: 6)

                        Image(systemName: isGettingStartedExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 16)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(AppBrand.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGettingStartedExpanded ? L("Collapse Getting Started") : L("Expand Getting Started"))

                if isGettingStartedExpanded {
                    Group {
                        GettingStartedRow(
                            title: L("Set up your Business"),
                            icon: "building.2",
                            isComplete: businessStore.profile.isSetupComplete,
                            action: { businessSetupDestination = .business }
                        )
                        GettingStartedRow(
                            title: L("Set up your hourly rates"),
                            icon: "dollarsign",
                            isComplete: !businessStore.hourlyRates.isEmpty,
                            action: { businessSetupDestination = .hourlyRates }
                        )
                        GettingStartedRow(
                            title: L("Create your first estimate"),
                            icon: "doc",
                            isComplete: !estimates.isEmpty,
                            action: beginQuickEstimate
                        )
                        GettingStartedRow(
                            title: L("Send it to a client"),
                            icon: "paperplane",
                            isComplete: estimates.contains { estimate in
                                ["sent", "viewed", "delivered", "accepted", "approved", "won"]
                                    .contains(estimate.status.lowercased())
                            },
                            showsDivider: false,
                            action: onOpenProjects
                        )
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
    }

    private var quickCreateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Quick create"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                HomeQuickAction(
                    title: L("Estimate"),
                    icon: "doc.text.fill",
                    titleSize: 11.7,
                    action: beginQuickEstimate
                )
                HomeQuickAction(
                    title: L("Invoice"),
                    icon: "doc.plaintext.fill",
                    titleSize: 11.7,
                    action: { beginQuickAction(.invoice) }
                )
                HomeQuickAction(
                    title: L("Project"),
                    icon: "folder.fill.badge.plus",
                    action: { showNewProject = true }
                )
                HomeQuickAction(
                    title: L("Render"),
                    icon: "camera.fill",
                    action: { beginQuickAction(.render) }
                )
            }
        }
    }

    private func beginQuickEstimate() {
        SuperwallService.performPremiumAction(
            .createEstimate,
            params: ["source": "home_quick_create"],
            onFailure: { subscriptionError = $0 },
            action: { showNewProject = true }
        )
    }

    private func beginQuickAction(_ action: ProjectQuickCreateAction) {
        let placement: PremiumPlacement = action == .invoice ? .createInvoice : .createRender
        SuperwallService.performPremiumAction(
            placement,
            params: ["source": "home_quick_create"],
            onFailure: { subscriptionError = $0 },
            action: { projectAction = action }
        )
    }

    private var estimatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(L("Estimates"), action: onOpenProjects)

            VStack(spacing: 10) {
                ForEach(HomeEstimateStatus.allCases, id: \.self) { status in
                    HapticButton(action: onOpenProjects) {
                        HomeStatusRow(
                            title: status.title,
                            count: estimateCount(for: status),
                            icon: status.icon
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var invoicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Invoices"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Spacer()
                HapticNavigationLink(destination: InvoicesView()) {
                    viewAllLabel
                }
                .buttonStyle(PlainButtonStyle())
            }

            VStack(spacing: 10) {
                HapticNavigationLink(destination: InvoicesView(initialTab: "Draft")) {
                    HomeStatusRow(
                        title: L("Draft"),
                        count: invoiceCount(for: "Draft"),
                        icon: "doc.text"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                HapticNavigationLink(destination: InvoicesView(initialTab: "Sent")) {
                    HomeStatusRow(
                        title: L("Sent"),
                        count: invoiceCount(for: "Sent"),
                        icon: "paperplane"
                    )
                }
                .buttonStyle(PlainButtonStyle())

                HapticNavigationLink(destination: InvoicesView(initialTab: "Paid")) {
                    HomeStatusRow(
                        title: L("Paid"),
                        count: invoiceCount(for: "Paid"),
                        icon: "checkmark.circle"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func sectionHeader(_ title: String, action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(L(title))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppGray.ink)
            Spacer()
            if let action {
                HapticButton(action: action) {
                    viewAllLabel
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var viewAllLabel: some View {
        Text(L("View all"))
            .font(.system(size: 15, weight: .regular, design: .rounded))
            .foregroundColor(AppGray.secondary)
    }
}

struct SupportContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showMailComposer = false
    @State private var unavailableMessage: String?

    private let supportEmail = "jack@viralappdev.com"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(L("Help & Support"))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppGray.ink)

                Spacer()

                HapticButton { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppGray.ink)
                        .frame(width: 36, height: 36)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close support"))
            }

            Text(L("Feel free to contact us for any concerns or support needed, and we will respond within 24 hours."))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppGray.itemText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AppGray.ink)

                Text(supportEmail)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppGray.ink)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            HapticButton(action: openSupportEmail) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L("Send Email"))
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(AppGray.ink)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .background(Color.white.ignoresSafeArea())
        .sheet(isPresented: $showMailComposer) {
            SupportMailComposer(
                recipient: supportEmail,
                subject: "EasyBid Support"
            ) {
                showMailComposer = false
            }
        }
        .alert(
            L("Can’t send email"),
            isPresented: Binding(
                get: { unavailableMessage != nil },
                set: { if !$0 { unavailableMessage = nil } }
            )
        ) {
            HapticButton("OK", role: .cancel) {}
        } message: {
            Text(unavailableMessage ?? "")
        }
    }

    private func openSupportEmail() {
        guard MFMailComposeViewController.canSendMail() else {
            unavailableMessage = L("Mail isn’t configured on this device.")
            return
        }
        showMailComposer = true
    }
}

private struct SupportMailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([recipient])
        controller.setSubject(subject)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onFinish()
            }
        }
    }
}

private struct GettingStartedRow: View {
    let title: String
    let icon: String
    let isComplete: Bool
    var showsDivider = true
    let action: () -> Void

    var body: some View {
        HapticButton(action: action) {
            HStack(spacing: 11) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppGray.secondary)
                    .frame(width: 20)
                Text(L(title))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppGray.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppGray.secondary)
            }
            .offset(y: -1)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .contentShape(Rectangle())
            .overlay(alignment: .bottomTrailing) {
                if showsDivider {
                    Rectangle()
                        .fill(AppGray.border.opacity(0.75))
                        .frame(height: 1)
                        .padding(.leading, 47)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private enum HomeEstimateStatus: CaseIterable {
    case draft
    case sent
    case approved

    var title: String {
        switch self {
        case .draft: return L("Draft")
        case .sent: return L("Sent")
        case .approved: return L("Approved")
        }
    }

    var icon: String {
        switch self {
        case .draft: return "doc.text"
        case .sent: return "paperplane"
        case .approved: return "checkmark.circle"
        }
    }

    func matches(_ rawStatus: String) -> Bool {
        let status = rawStatus.lowercased()
        switch self {
        case .draft:
            return !["sent", "viewed", "delivered", "accepted", "approved", "won"].contains(status)
        case .sent:
            return ["sent", "viewed", "delivered"].contains(status)
        case .approved:
            return ["accepted", "approved", "won"].contains(status)
        }
    }
}

private struct HomeQuickAction: View {
    let title: String
    let icon: String
    var titleSize: CGFloat = 13
    let action: () -> Void

    private let brandBlue = AppBrand.accent

    var body: some View {
        HapticButton(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(brandBlue)

                Text(L(title))
                    .font(.system(size: titleSize, weight: .medium))
                    .foregroundColor(AppGray.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

private struct HomeStatusRow: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(AppGray.secondary)
                .frame(width: 24)

            Text(L(title))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppGray.ink)

            Spacer()

            Text("\(count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppGray.ink)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppGray.muted)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .contentShape(Rectangle())
    }
}
