//
//  WalletDashboard.swift
//  Construction Estimate
//
//  The Home screen's wallet-style top: a Liquid Glass balance card with the
//  money collected, round quick actions, a billed-vs-collected chart and a
//  recent activity feed, all from the business's real invoices and payments.
//

import SwiftUI
import Charts

// MARK: - Figures

/// Everything the wallet shows, worked out once from the stores.
struct WalletFigures {
    struct MonthPoint: Identifiable {
        let month: Date
        let billed: Double
        let collected: Double
        var id: Date { month }
    }

    struct Activity: Identifiable {
        enum Kind { case payment, invoiceSent, invoicePaid, invoiceDraft }
        let id: String
        let kind: Kind
        let title: String
        let date: Date
        let amount: Double
    }

    let collectedThisMonth: Double
    let collectedLastMonth: Double
    let outstanding: Double
    let overdue: Double
    let pipeline: Double
    let months: [MonthPoint]
    let activity: [Activity]

    /// Month-over-month change of money collected, or nil with nothing to compare.
    var change: Double? {
        guard collectedLastMonth > 0 else { return nil }
        return (collectedThisMonth - collectedLastMonth) / collectedLastMonth * 100
    }

    @MainActor
    static func current(
        invoices: [Invoice],
        payments: [Payment],
        estimates: [Estimate],
        clientName: (Invoice) -> String,
        monthCount: Int = 6,
        now: Date = Date()
    ) -> WalletFigures {
        let calendar = Calendar.current
        let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
        func isStatus(_ invoice: Invoice, _ status: String) -> Bool {
            invoice.status.caseInsensitiveCompare(status) == .orderedSame
        }

        // Money in: recorded payments; paid invoices stand in when none are recorded.
        var collections: [(Date, Double)] = payments.map { ($0.receivedAt, $0.amount) }
        if collections.isEmpty {
            collections = invoices.filter { isStatus($0, "Paid") }.map { ($0.createdAt, $0.total) }
        }
        let billed = invoices.filter { !isStatus($0, "Draft") }

        func sum(_ items: [(Date, Double)], in month: Date) -> Double {
            items.filter { calendar.isDate($0.0, equalTo: month, toGranularity: .month) }.reduce(0) { $0 + $1.1 }
        }

        let months: [MonthPoint] = (0..<monthCount).reversed().compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: -offset, to: thisMonth) else { return nil }
            return MonthPoint(
                month: month,
                billed: sum(billed.map { ($0.createdAt, $0.total) }, in: month),
                collected: sum(collections, in: month)
            )
        }

        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let open = invoices.filter { !isStatus($0, "Paid") && !isStatus($0, "Draft") }
        let startOfToday = calendar.startOfDay(for: now)
        let wonOrLost: Set<String> = ["accepted", "approved", "won", "declined", "rejected", "lost"]
        let pipeline = estimates
            .filter { !wonOrLost.contains($0.status.lowercased()) }
            .reduce(0) { $0 + $1.total }

        var activity: [Activity] = payments.map {
            Activity(id: "p-\($0.id)", kind: .payment, title: L("Payment received"), date: $0.receivedAt, amount: $0.amount)
        }
        activity += invoices.map { invoice in
            let kind: Activity.Kind = isStatus(invoice, "Paid") ? .invoicePaid : (isStatus(invoice, "Draft") ? .invoiceDraft : .invoiceSent)
            return Activity(id: "i-\(invoice.id)", kind: kind, title: clientName(invoice), date: invoice.createdAt, amount: invoice.total)
        }
        activity.sort { $0.date > $1.date }

        return WalletFigures(
            collectedThisMonth: sum(collections, in: thisMonth),
            collectedLastMonth: sum(collections, in: lastMonth),
            outstanding: open.reduce(0) { $0 + $1.total },
            overdue: open.filter { ($0.dueAt ?? .distantFuture) < startOfToday }.reduce(0) { $0 + $1.total },
            pipeline: pipeline,
            months: months,
            activity: Array(activity.prefix(5))
        )
    }
}

private func walletMoney(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(value.rounded() == value ? 0 : 2)).locale(appLocale))
}

// MARK: - Balance card

/// The hero card: a deep-blue glass slab with flowing particles behind the
/// balance, which rolls up from zero when the screen appears.
struct WalletBalanceCard: View {
    let figures: WalletFigures

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownBalance: Double = 0
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(L("Collected this month"), systemImage: "wallet.bifold.fill")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(Date().formatted(Date.FormatStyle().month(.wide).locale(appLocale)).capitalized(with: appLocale))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .liquidGlassCapsule(tint: .white.opacity(0.12), interactive: false)
            }

            Text(walletMoney(shownBalance))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(value: shownBalance))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .padding(.top, 14)

            if let change = figures.change {
                HStack(spacing: 6) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                    Text(L("%@ vs last month", (change >= 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(0...1)).locale(appLocale)) + "%"))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(change >= 0 ? Color(hex: 0xB9F5CF) : Color(hex: 0xFFC9C4))
                .padding(.top, 6)
            }

            HStack(spacing: 10) {
                stat(L("Outstanding"), figures.outstanding, icon: "clock.fill")
                stat(L("Overdue"), figures.overdue, icon: "exclamationmark.circle.fill")
                stat(L("Pipeline"), figures.pipeline, icon: "doc.text.fill")
            }
            .padding(.top, 22)
        }
        .padding(22)
        .background {
            ZStack {
                OnboardingBackdrop()
                FlowParticlesView(color: .white, opacity: 0.45, density: 0.9)
                LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .shadow(color: AppBrand.dark.opacity(0.35), radius: 26, y: 16)
        .onAppear { rollUp() }
        .onChange(of: figures.collectedThisMonth) { _, _ in rollUp() }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: Double, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .labelStyle(.titleOnly)
            Text(walletMoney(value))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassEffect(.clear.tint(.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The balance counts up with a long, eased roll: the screen's big moment.
    private func rollUp() {
        guard !reduceMotion else {
            shownBalance = figures.collectedThisMonth
            return
        }
        shownBalance = 0
        withAnimation(.spring(response: 1.4, dampingFraction: 0.9).delay(0.15)) {
            shownBalance = figures.collectedThisMonth
        }
    }
}

// MARK: - Quick actions

/// Round glass actions under the balance, like a wallet's Send / Receive.
struct WalletActionsRow: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let icon: String
        let action: () -> Void
    }

    let items: [Item]
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button(action: item.action) {
                        VStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppBrand.accent)
                                .frame(width: 58, height: 58)
                                .glassEffect(.regular.tint(.white.opacity(0.4)).interactive(), in: Circle())
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(AppGray.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassPressStyle(pressedScale: 0.88))
                    // Actions pop in one after another.
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.4)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.58).delay(0.25 + Double(index) * 0.07), value: appeared)
                }
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Cash flow

/// Billed vs collected per month, drawn in once as a glass panel.
struct WalletCashFlowCard: View {
    let figures: WalletFigures

    @State private var drawn = false
    @State private var selected: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var billedTotal: Double { figures.months.reduce(0) { $0 + $1.billed } }
    private var collectedTotal: Double { figures.months.reduce(0) { $0 + $1.collected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Cash flow"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGray.ink)
                Spacer()
                Text(L("Last 6 months"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppGray.secondary)
            }

            HStack(spacing: 24) {
                legend(L("Billed"), billedTotal, color: AppBrand.light.opacity(0.55))
                legend(L("Collected"), collectedTotal, color: AppBrand.accent)
            }

            Chart(figures.months) { point in
                AreaMark(
                    x: .value(L("Month"), point.month, unit: .month),
                    y: .value(L("Collected"), drawn ? point.collected : 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [AppBrand.accent.opacity(0.28), AppBrand.accent.opacity(0)], startPoint: .top, endPoint: .bottom))

                LineMark(
                    x: .value(L("Month"), point.month, unit: .month),
                    y: .value(L("Collected"), drawn ? point.collected : 0),
                    series: .value("Series", "collected")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(AppBrand.accent)

                LineMark(
                    x: .value(L("Month"), point.month, unit: .month),
                    y: .value(L("Billed"), drawn ? point.billed : 0),
                    series: .value("Series", "billed")
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
                .foregroundStyle(AppBrand.light.opacity(0.7))

                if let selected, Calendar.current.isDate(selected, equalTo: point.month, toGranularity: .month) {
                    RuleMark(x: .value(L("Month"), point.month, unit: .month))
                        .foregroundStyle(AppBrand.accent.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            Text(walletMoney(point.collected))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppGray.ink)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .liquidGlassCapsule(interactive: false)
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).locale(appLocale))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
            .frame(height: 150)
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 26)
        .onAppear {
            guard !drawn else { return }
            if reduceMotion { drawn = true; return }
            // The lines rise out of the baseline.
            withAnimation(.spring(response: 1.1, dampingFraction: 0.82).delay(0.35)) { drawn = true }
        }
    }

    private func legend(_ title: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppGray.secondary)
            }
            Text(walletMoney(value))
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(AppGray.ink)
                .monospacedDigit()
        }
    }
}

// MARK: - Activity

/// The latest money movements, like a wallet's transaction list.
struct WalletActivityList: View {
    let activity: [WalletFigures.Activity]

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("Recent activity"))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGray.ink)
                Spacer()
                HapticNavigationLink(destination: InvoicesView()) {
                    HStack(spacing: 4) {
                        Text(L("View all"))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppBrand.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 6)

            if activity.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(AppBrand.light)
                    Text(L("No activity yet"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppGray.ink)
                    Text(L("Payments and invoices will show up here."))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(AppGray.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ForEach(Array(activity.enumerated()), id: \.element.id) { index, item in
                    row(item)
                        .offset(x: appeared || reduceMotion ? 0 : 40)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.45 + Double(index) * 0.06), value: appeared)
                    if index < activity.count - 1 {
                        Divider().opacity(0.5).padding(.leading, 54)
                    }
                }
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 26)
        .onAppear { appeared = true }
    }

    private func row(_ item: WalletFigures.Activity) -> some View {
        let incoming = item.kind == .payment || item.kind == .invoicePaid
        let icon: String = switch item.kind {
        case .payment: "arrow.down.left"
        case .invoicePaid: "checkmark"
        case .invoiceSent: "paperplane.fill"
        case .invoiceDraft: "doc.text"
        }
        let subtitle: String = switch item.kind {
        case .payment: L("Payment")
        case .invoicePaid: L("Paid")
        case .invoiceSent: L("Sent")
        case .invoiceDraft: L("Draft")
        }
        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(incoming ? Color(hex: 0x1E7B34) : AppBrand.accent)
                .frame(width: 42, height: 42)
                .glassEffect(.regular.tint((incoming ? Color(hex: 0x34C759) : AppBrand.light).opacity(0.18)), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppGray.ink)
                    .lineLimit(1)
                Text(subtitle + " · " + item.date.formatted(Date.FormatStyle().month(.abbreviated).day().locale(appLocale)))
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(AppGray.secondary)
            }
            Spacer(minLength: 8)
            Text((incoming ? "+" : "") + walletMoney(item.amount))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(incoming ? Color(hex: 0x1E7B34) : AppGray.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
