//
//  EstimateExtrasView.swift
//  Construction Estimate
//

import SwiftUI

/// Renders the supplementary sections that the edge function now returns alongside
/// the categorized line items: contingency, tool rental, permits, exclusions,
/// payment terms, sanity-check warning, and source-reconciliation notes.
struct EstimateExtrasView: View {
    let estimate: Estimate
    var compact: Bool = false

    private let darkText = AppGray.ink
    private let darkGray = AppGray.itemText
    private let warningBg = Color(red: 1.0, green: 0.96, blue: 0.86)
    private let warningStroke = Color(red: 0.85, green: 0.65, blue: 0.20)
    private let warningText = Color(red: 0.55, green: 0.38, blue: 0.05)

    private func formatted(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            adders
            disclosures
        }
    }

    /// Cost adders that sit alongside the line-item categories
    /// (permits, tool rental, contingency).
    @ViewBuilder
    var adders: some View {
        if let permit = estimate.permitInfo, permit.estimatedFee != nil || permit.priorUnpermittedWork == true {
            permitRow(permit)
            Divider()
        }
        if let tool = estimate.toolRental {
            summaryRow(
                label: L("Tool Rental"),
                value: formatted(tool.amount),
                detail: tool.notes
            )
            Divider()
        }
    }

    /// Disclosure text blocks (site conditions, exclusions, payment terms, sources).
    @ViewBuilder
    var disclosures: some View {
        if let site = estimate.siteConditions, hasSiteConditions(site) {
            infoBlock(title: L("Site Conditions"), body: siteConditionsText(site))
        }
        if let note = estimate.crossReferenceNotes, !note.isEmpty {
            infoBlock(title: L("Pricing Sources"), body: note)
        }
    }

    // MARK: - Rows / blocks

    private func summaryRow(label: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L(label))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(darkGray)
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(darkGray)
            }
            if let d = detail, !d.isEmpty {
                Text(d)
                    .font(.system(size: 12))
                    .foregroundColor(AppGray.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func permitRow(_ permit: PermitInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L("Permits"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(darkGray)
                Spacer()
                if let fee = permit.estimatedFee {
                    Text(formatted(fee))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(darkGray)
                } else {
                    Text(L("TBD"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppGray.muted)
                }
            }
            if permit.priorUnpermittedWork == true {
                Text(L("Prior unpermitted work flagged — may require remediation."))
                    .font(.system(size: 12))
                    .foregroundColor(warningText)
            }
            if let n = permit.notes, !n.isEmpty {
                Text(n)
                    .font(.system(size: 12))
                    .foregroundColor(AppGray.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    private func sanityCheckBanner(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(warningStroke)
                .padding(.top, 1)
            Text(note)
                .font(.system(size: 13))
                .foregroundColor(warningText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(warningBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(warningStroke.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func exclusionsBlock(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("What's not included"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkGray)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 14))
                        .foregroundColor(AppGray.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private func infoBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L(title))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(darkGray)
            Text(body)
                .font(.system(size: 13))
                .foregroundColor(AppGray.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var insetDivider: some View {
        Rectangle()
            .fill(AppGray.badge)
            .frame(height: 1)
            .padding(.horizontal, 20)
    }

    // MARK: - Formatting helpers

    private func formatPercent(_ p: Double) -> String {
        // Edge function may send 0.10 or 10.0 — normalize.
        let pct = p > 1 ? p : p * 100
        if pct == pct.rounded() {
            return "\(Int(pct))%"
        }
        return String(format: "%.1f%%", pct)
    }

    private func hasSiteConditions(_ s: SiteConditions) -> Bool {
        s.interior != nil || s.floorLevel != nil || s.occupiedSpace != nil ||
        s.tightAccess != nil || s.laborRateAdjustment != nil ||
        (s.notes?.isEmpty == false)
    }

    private func siteConditionsText(_ s: SiteConditions) -> String {
        var parts: [String] = []
        if let interior = s.interior {
            parts.append(interior ? L("Interior") : L("Exterior"))
        }
        if let floor = s.floorLevel, !floor.isEmpty {
            parts.append(L("Floor: %@", "\(floor)"))
        }
        if s.occupiedSpace == true { parts.append(L("Occupied space")) }
        if s.tightAccess == true { parts.append(L("Tight access")) }
        if let adj = s.laborRateAdjustment {
            let pct = adj > 1 ? adj : adj * 100
            let sign = pct >= 0 ? "+" : ""
            parts.append(L("Labor adj. %@%@%%", "\(sign)", "\(Int(pct.rounded()))"))
        }
        var line = parts.joined(separator: " · ")
        if let notes = s.notes, !notes.isEmpty {
            if !line.isEmpty { line += "\n" }
            line += notes
        }
        return line
    }
}
