//
//  InvoicesView.swift
//  Construction Estimate
//
//  Invoices overview: period picker, swipeable Total / Collected summary,
//  search and status filter, the invoice list, and a Create Invoice button,
//  over a slow silk gradient with a faint drafting-paper grid.
//

import SwiftUI

struct InvoicesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabBarVisibility.self) private var tabBar

    @State private var store = InvoiceStore.shared
    @State private var clientStore = ClientStore.shared
    @State private var statusFilter: String?
    @State private var month: Date?
    @State private var summaryPage = 0
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var editingInvoice: Invoice?
    @State private var createAction: ProjectQuickCreateAction?
    @State private var subscriptionError: String?

    static let statuses = ["Draft", "Scheduled", "Sent", "Paid"]

    /// `initialTab` preselects a status ("Draft", "Sent", "Paid"); nil shows all.
    init(initialTab: String? = nil) {
        _statusFilter = State(initialValue: initialTab)
    }

    // MARK: Data

    private var inPeriod: [Invoice] {
        guard let month else { return store.invoices }
        return store.invoices.filter { Calendar.current.isDate($0.createdAt, equalTo: month, toGranularity: .month) }
    }

    private var visibleInvoices: [Invoice] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return inPeriod
            .filter { invoice in
                guard let statusFilter else { return true }
                return invoice.status.caseInsensitiveCompare(statusFilter) == .orderedSame
            }
            .filter { invoice in
                guard !query.isEmpty else { return true }
                return clientName(for: invoice).localizedCaseInsensitiveContains(query)
                    || invoice.invoiceNumber.localizedCaseInsensitiveContains(query)
                    || invoice.title.localizedCaseInsensitiveContains(query)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var periodTotal: Double { inPeriod.reduce(0) { $0 + $1.total } }

    /// Billed but not yet paid (drafts are not billed yet).
    private var balanceDue: Double {
        inPeriod.filter { !Self.isStatus($0, "Paid") && !Self.isStatus($0, "Draft") }.reduce(0) { $0 + $1.total }
    }

    private var paidInvoices: [Invoice] { inPeriod.filter { Self.isStatus($0, "Paid") } }

    /// The current month, the last 11 and any older month that has invoices.
    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let thisMonth = Self.startOfMonth(Date())
        var months = Set((0..<12).compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) })
        for invoice in store.invoices { months.insert(Self.startOfMonth(invoice.createdAt)) }
        return months.sorted(by: >)
    }

    private func clientName(for invoice: Invoice) -> String {
        if let id = invoice.clientId, let client = clientStore.clients.first(where: { $0.id == id }), !client.name.isEmpty {
            return client.name
        }
        return invoice.title.isEmpty ? L("No client") : invoice.title
    }

    static func isStatus(_ invoice: Invoice, _ status: String) -> Bool {
        invoice.status.caseInsensitiveCompare(status) == .orderedSame
    }

    static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    private func monthTitle(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.wide).year().locale(appLocale)).capitalized(with: appLocale)
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(value.rounded() == value ? 0 : 2)).locale(appLocale))
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .bottom) {
            InvoicesBackdrop()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 18) {
                        periodPicker
                        summaryPager
                        controlsRow
                        if isSearching { searchField }
                        if visibleInvoices.isEmpty { emptyState } else { invoiceList }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 140)
                }
                .scrollDismissesKeyboard(.interactively)
            }

            createButton
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { tabBar.isHidden = true }
        .onDisappear { tabBar.isHidden = false }
        .task {
            await store.refresh()
            if clientStore.clients.isEmpty { await clientStore.refresh() }
        }
        .sheet(item: $editingInvoice) { invoice in
            NavigationStack {
                InvoiceDetailView(invoice: invoice) { savedInvoice in
                    store.update(savedInvoice)
                }
            }
        }
        .fullScreenCover(item: $createAction) { action in
            ProjectActionPickerView(action: action)
        }
        .alert(
            L("Subscription unavailable"),
            isPresented: Binding(
                get: { subscriptionError != nil },
                set: { if !$0 { subscriptionError = nil } }
            )
        ) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(subscriptionError ?? L("Please try again."))
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            HapticButton {
                tabBar.isHidden = false
                dismiss()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppGray.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Back"))

            Text(L("Invoices"))
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(AppGray.ink)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Period

    private var periodPicker: some View {
        Menu {
            Button {
                month = nil
            } label: {
                if month == nil { Label(L("All time"), systemImage: "checkmark") } else { Text(L("All time")) }
            }
            Divider()
            ForEach(availableMonths, id: \.self) { option in
                Button {
                    month = option
                } label: {
                    if month == option { Label(monthTitle(option), systemImage: "checkmark") } else { Text(monthTitle(option)) }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppBrand.accent)
                    .frame(width: 30, height: 30)
                    .background(Color.white)
                    .clipShape(Circle())
                Text(month.map(monthTitle) ?? L("All time"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppGray.secondary)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.7))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
        }
        .accessibilityLabel(L("Choose period"))
    }

    // MARK: Summary

    private var summaryPager: some View {
        TabView(selection: $summaryPage) {
            summaryCard(label: L("Total"), amount: periodTotal) {
                HStack(spacing: 0) {
                    Text(L("Balance due") + ": ")
                        .foregroundColor(AppGray.itemText)
                    Text(money(balanceDue))
                        .foregroundColor(balanceDue > 0 ? Color(hex: 0xB42318) : AppGray.itemText)
                        .monospacedDigit()
                }
            }
            .tag(0)

            summaryCard(label: L("Collected"), amount: paidInvoices.reduce(0) { $0 + $1.total }) {
                Text(paidInvoices.count == 1 ? L("1 paid invoice") : L("%@ paid invoices", paidInvoices.count.formatted()))
                    .foregroundColor(AppGray.itemText)
            }
            .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 118)
    }

    private func summaryCard<Detail: View>(label: String, amount: Double, @ViewBuilder detail: () -> Detail) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppGray.itemText)
            Text(money(amount))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(AppGray.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: amount))
                .animation(.snappy, value: amount)
            detail()
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Controls

    private var controlsRow: some View {
        HStack {
            HapticButton {
                withAnimation(.snappy) { isSearching.toggle() }
                if isSearching { searchFocused = true } else { searchText = "" }
            } label: {
                controlCircle(systemName: isSearching ? "xmark" : "magnifyingglass", isActive: isSearching)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearching ? L("Close search") : L("Search invoices"))

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Button {
                        withAnimation(.snappy) { summaryPage = index }
                    } label: {
                        Capsule()
                            .fill(summaryPage == index ? AppBrand.accent : AppBrand.accent.opacity(0.22))
                            .frame(width: summaryPage == index ? 16 : 6, height: 6)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index == 0 ? L("Show total") : L("Show collected"))
                }
            }

            Spacer()

            Menu {
                Button {
                    statusFilter = nil
                } label: {
                    if statusFilter == nil { Label(L("All statuses"), systemImage: "checkmark") } else { Text(L("All statuses")) }
                }
                Divider()
                ForEach(Self.statuses, id: \.self) { status in
                    Button {
                        statusFilter = status
                    } label: {
                        if statusFilter == status { Label(L(status), systemImage: "checkmark") } else { Text(L(status)) }
                    }
                }
            } label: {
                controlCircle(systemName: "line.3.horizontal.decrease", isActive: statusFilter != nil)
            }
            .accessibilityLabel(L("Filter by status"))
        }
    }

    private func controlCircle(systemName: String, isActive: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(isActive ? .white : AppGray.ink)
            .frame(width: 40, height: 40)
            .background(isActive ? AppBrand.accent : Color.white.opacity(0.85))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.black.opacity(isActive ? 0 : 0.06), lineWidth: 0.5))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppGray.secondary)
            TextField(L("Search client or invoice number"), text: $searchText)
                .font(.system(size: 16))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppGray.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: List

    private var invoiceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(visibleInvoices.enumerated()), id: \.element.id) { index, invoice in
                HapticButton {
                    editingInvoice = invoice
                } label: {
                    InvoiceListRow(invoice: invoice, clientName: clientName(for: invoice))
                }
                .buttonStyle(.plain)

                if index < visibleInvoices.count - 1 {
                    Rectangle()
                        .fill(AppGray.badge)
                        .frame(height: 0.7)
                        .padding(.leading, 74)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
        .shadow(color: AppBrand.dark.opacity(0.06), radius: 14, x: 0, y: 6)
    }

    private var emptyState: some View {
        let filtered = statusFilter != nil || month != nil || !searchText.isEmpty
        return VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppBrand.light.opacity(0.25))
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-12))
                    .offset(x: -8, y: -4)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [AppBrand.light, AppBrand.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "doc.text")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
            .padding(.top, 10)

            Text(filtered ? L("No matching invoices") : L("No invoices yet"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(AppGray.ink)

            Text(filtered
                 ? L("Try a different period, status or search.")
                 : L("Create an invoice from a project and it will appear here."))
                .font(.system(size: 14))
                .foregroundColor(AppGray.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if filtered {
                HapticButton("Show all invoices") {
                    withAnimation(.snappy) {
                        statusFilter = nil
                        month = nil
                        searchText = ""
                        isSearching = false
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppBrand.accent)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.05), lineWidth: 0.5))
    }

    // MARK: Create

    private var createButton: some View {
        HapticButton {
            SuperwallService.performPremiumAction(
                .createInvoice,
                params: ["source": "invoices_screen"],
                onFailure: { subscriptionError = $0 },
                action: { createAction = .invoice }
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text(L("Create invoice"))
                    .font(.system(size: 16, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(colors: [AppBrand.dark, AppBrand.accent, AppBrand.light], startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(Capsule())
            .shadow(color: AppBrand.dark.opacity(0.18), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

private struct InvoiceListRow: View {
    let invoice: Invoice
    let clientName: String

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppBrand.accent.opacity(0.08))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(AppBrand.accent)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(clientName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                    .lineLimit(1)
                Text(invoice.invoiceNumber)
                    .font(.system(size: 13))
                    .foregroundColor(AppGray.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(invoice.formattedTotal)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppGray.ink)
                    .monospacedDigit()
                InvoiceStatusPill(invoice: invoice)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct InvoiceStatusPill: View {
    let invoice: Invoice

    private var style: (text: String, foreground: Color, background: Color) {
        if InvoicesView.isStatus(invoice, "Paid") {
            return (L("Paid"), Color(hex: 0x1E7B34), Color(hex: 0xE5F4E8))
        }
        if InvoicesView.isStatus(invoice, "Draft") {
            return (L("Draft"), AppGray.itemText, AppGray.pill)
        }
        if InvoicesView.isStatus(invoice, "Scheduled") {
            return (L("Scheduled"), AppBrand.accent, AppBrand.accent.opacity(0.1))
        }
        guard let due = invoice.dueAt else {
            return (L(invoice.status), AppBrand.accent, AppBrand.accent.opacity(0.1))
        }
        let calendar = Calendar.current
        if calendar.isDateInToday(due) {
            return (L("Due today"), Color(hex: 0x8A5A00), Color(hex: 0xFFF1CC))
        }
        if due < calendar.startOfDay(for: Date()) {
            return (L("Overdue"), Color(hex: 0xB42318), Color(hex: 0xFDECEC))
        }
        let date = due.formatted(Date.FormatStyle().month(.abbreviated).day().locale(appLocale))
        return (L("Due %@", date), AppBrand.accent, AppBrand.accent.opacity(0.1))
    }

    var body: some View {
        let style = style
        Text(style.text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(style.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(style.background)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: - Background

/// A slow, silk-like drift of the brand's pale blues over a faint
/// drafting-paper grid. No particles, no flashing; still with Reduce Motion.
struct InvoicesBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(hex: 0xD6E4F7), Color(hex: 0xEDF2FA), Color(hex: 0xCADCF5),
        Color(hex: 0xF3F6FB), Color(hex: 0xBFD3F1), Color(hex: 0xE3ECF8),
        Color(hex: 0xF9F9F9), Color(hex: 0xF6F8FB), Color(hex: 0xF9F9F9),
    ]

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height * 0.62
            let fade = LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ZStack(alignment: .top) {
                AppGray.bgPale

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: Self.points(at: reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate),
                        colors: Self.colors
                    )
                }
                .frame(height: height)
                .mask(fade)

                DraftingGrid()
                    .frame(height: height)
                    .mask(fade)
            }
        }
    }

    /// Corners stay put; edges and the center sway slowly on different
    /// periods (roughly 20-40 s), so the pattern never visibly repeats.
    static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        func wave(_ period: Double, _ phase: Double, _ amount: Double) -> Float {
            Float(sin(time * 2 * .pi / period + phase) * amount)
        }
        return [
            SIMD2(0, 0),
            SIMD2(0.5 + wave(29, 0.0, 0.10), 0),
            SIMD2(1, 0),
            SIMD2(0, 0.5 + wave(33, 1.3, 0.08)),
            SIMD2(0.5 + wave(23, 2.1, 0.12), 0.5 + wave(37, 0.7, 0.10)),
            SIMD2(1, 0.5 + wave(27, 2.9, 0.08)),
            SIMD2(0, 1),
            SIMD2(0.5 + wave(31, 1.7, 0.10), 1),
            SIMD2(1, 1),
        ]
    }
}

/// Faint construction-paper grid: fine lines every 24 pt, a slightly
/// stronger line every fourth one. Drawn once; it does not animate.
private struct DraftingGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 24
            var fine = Path()
            var major = Path()
            func line(_ from: CGPoint, _ to: CGPoint, _ index: Int) {
                if index % 4 == 0 {
                    major.move(to: from)
                    major.addLine(to: to)
                } else {
                    fine.move(to: from)
                    fine.addLine(to: to)
                }
            }
            for index in 0...Int(size.width / step) {
                let x = CGFloat(index) * step
                line(CGPoint(x: x, y: 0), CGPoint(x: x, y: size.height), index)
            }
            for index in 0...Int(size.height / step) {
                let y = CGFloat(index) * step
                line(CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y), index)
            }
            context.stroke(fine, with: .color(AppBrand.dark.opacity(0.035)), lineWidth: 0.5)
            context.stroke(major, with: .color(AppBrand.dark.opacity(0.06)), lineWidth: 0.6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        InvoicesView()
    }
    .environment(TabBarVisibility())
    .environment(AuthStore())
}
