//
//  Estimate.swift
//  Construction Estimate
//

import Foundation

struct EstimateLineItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var quantity: Double
    var unitLabel: String
    var unitPrice: Double
    var total: Double
    var source: String?
    var url: String?
    var description: String?
    var onHand: Bool

    init(
        id: UUID = UUID(),
        name: String,
        quantity: Double,
        unitLabel: String,
        unitPrice: Double,
        total: Double,
        source: String? = nil,
        url: String? = nil,
        description: String? = nil,
        onHand: Bool = false
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unitLabel = unitLabel
        self.unitPrice = unitPrice
        self.total = total
        self.source = source
        self.url = url
        self.description = description
        self.onHand = onHand
    }
}

struct EstimateCategory: Identifiable, Codable {
    var id = UUID()
    let name: String
    let items: [EstimateLineItem]
    let subtotal: Double
}

struct EstimatePlanSection: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var steps: [String]
}

struct SiteConditions: Codable {
    let interior: Bool?
    let floorLevel: String?
    let occupiedSpace: Bool?
    let tightAccess: Bool?
    let laborRateAdjustment: Double?
    let notes: String?
}

struct PermitInfo: Codable {
    let priorUnpermittedWork: Bool?
    let estimatedFee: Double?
    let notes: String?
}

struct ContingencyInfo: Codable {
    let percent: Double
    let amount: Double
    let reason: String?
}

struct ToolRentalInfo: Codable {
    let amount: Double
    let notes: String?
}

enum EstimateAccent: String, Codable, CaseIterable, Identifiable {
    case blue, black, gray, green
    var id: String { rawValue }
    var hex: String {
        switch self {
        case .blue: return "#285C9B"
        case .black: return "#202124"
        case .gray: return "#60646C"
        case .green: return "#287052"
        }
    }
}

struct EstimateAppearance: Codable, Equatable {
    var accent: EstimateAccent = .blue
    var businessName: String = ""
}

struct Estimate: Identifiable, Codable {
    var id = UUID()
    let estimateNumber: String
    let title: String
    let categories: [EstimateCategory]
    let subtotal: Double
    let markupPercent: Double
    let markupAmount: Double
    let total: Double
    var status: String = "Draft"
    let createdAt: Date
    let chatSessionId: UUID

    // New structured fields from the edge function
    let siteConditions: SiteConditions?
    let permitInfo: PermitInfo?
    let contingency: ContingencyInfo?
    let toolRental: ToolRentalInfo?
    let wasteFactors: [String: Double]?
    let exclusions: [String]?
    let paymentTerms: String?
    let sanityCheckNote: String?
    let crossReferenceNotes: String?

    /// Ordered contractor-editable work phases generated from the same scope
    /// used to build the price. Optional keeps locally cached legacy estimates
    /// decodable; the UI treats nil as an empty plan.
    var workPlan: [EstimatePlanSection]? = nil
    var notes: String? = nil
    var appearance: EstimateAppearance? = nil

    /// The row id in Supabase's `estimates` table. Set when the edge function
    /// stored this estimate; nil for estimates that predate Supabase storage.
    var supabaseEstimateId: String?

    var itemCount: Int { categories.flatMap(\.items).count }

    var materials: [EstimateLineItem] {
        categories
            .filter { $0.name.lowercased().contains("material") }
            .flatMap { $0.items }
    }

    var materialsSubtotal: Double {
        categories
            .filter { $0.name.lowercased().contains("material") }
            .reduce(0) { $0 + $1.subtotal }
    }

    var formattedTotal: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: total)) ?? "$0.00"
    }

    var formattedSubtotal: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: subtotal)) ?? "$0.00"
    }

    var shortDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: createdAt)
    }

    /// Decode from the raw JSON dictionary returned by the edge function
    static func from(dict: [String: Any], chatSessionId: UUID, estimateNumber: String, supabaseEstimateId: String? = nil) -> Estimate? {
        guard let title = dict["title"] as? String,
              let categoriesArr = dict["categories"] as? [[String: Any]],
              let subtotal = dict["subtotal"] as? Double,
              let markupPercent = dict["markupPercent"] as? Double,
              let markupAmount = dict["markupAmount"] as? Double,
              let total = dict["total"] as? Double else { return nil }

        let categories: [EstimateCategory] = categoriesArr.compactMap { catDict in
            guard let name = catDict["name"] as? String,
                  let itemsArr = catDict["items"] as? [[String: Any]] else { return nil }

            let items: [EstimateLineItem] = itemsArr.compactMap { itemDict in
                guard let itemName = itemDict["name"] as? String,
                      let qty = itemDict["quantity"] as? Double,
                      let unitLabel = itemDict["unitLabel"] as? String,
                      let unitPrice = itemDict["unitPrice"] as? Double,
                      let itemTotal = itemDict["total"] as? Double else { return nil }
                let urlStr = (itemDict["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let onHand = (itemDict["onHand"] as? Bool) ?? false
                return EstimateLineItem(
                    name: itemName,
                    quantity: qty,
                    unitLabel: unitLabel,
                    unitPrice: unitPrice,
                    total: itemTotal,
                    source: itemDict["source"] as? String,
                    url: urlStr,
                    description: itemDict["description"] as? String,
                    onHand: onHand
                )
            }

            // Trust the items-summed total over whatever the LLM put in `subtotal` —
            // the model frequently returns 0 here even when items have real prices.
            let summedFromItems = items.reduce(0.0) { $0 + $1.total }
            let providedSubtotal = (catDict["subtotal"] as? Double) ?? 0
            let resolvedSubtotal = summedFromItems > 0 ? summedFromItems : providedSubtotal

            return EstimateCategory(name: name, items: items, subtotal: resolvedSubtotal)
        }

        // Site conditions
        let siteConditions: SiteConditions? = (dict["siteConditions"] as? [String: Any]).map { sc in
            SiteConditions(
                interior: sc["interior"] as? Bool,
                floorLevel: sc["floorLevel"] as? String,
                occupiedSpace: sc["occupiedSpace"] as? Bool,
                tightAccess: sc["tightAccess"] as? Bool,
                laborRateAdjustment: sc["laborRateAdjustment"] as? Double,
                notes: sc["notes"] as? String
            )
        }

        // Permit info
        let permitInfo: PermitInfo? = (dict["permitInfo"] as? [String: Any]).map { p in
            PermitInfo(
                priorUnpermittedWork: p["priorUnpermittedWork"] as? Bool,
                estimatedFee: p["estimatedFee"] as? Double,
                notes: p["notes"] as? String
            )
        }

        // Contingency: accept either a dict {percent, amount, reason} or a flat number
        let contingency: ContingencyInfo? = {
            if let c = dict["contingency"] as? [String: Any],
               let percent = c["percent"] as? Double,
               let amount = c["amount"] as? Double {
                return ContingencyInfo(percent: percent, amount: amount, reason: c["reason"] as? String)
            }
            if let amount = dict["contingencyAmount"] as? Double,
               let percent = dict["contingencyPercent"] as? Double {
                return ContingencyInfo(percent: percent, amount: amount, reason: nil)
            }
            return nil
        }()

        // Tool rental: accept dict {amount, notes} or flat number
        let toolRental: ToolRentalInfo? = {
            if let t = dict["toolRental"] as? [String: Any],
               let amount = t["amount"] as? Double {
                return ToolRentalInfo(amount: amount, notes: t["notes"] as? String)
            }
            if let amount = dict["toolRental"] as? Double {
                return ToolRentalInfo(amount: amount, notes: nil)
            }
            return nil
        }()

        let wasteFactors = dict["wasteFactors"] as? [String: Double]
        let exclusions = dict["exclusions"] as? [String]
            ?? (dict["whatsNotIncluded"] as? [String])
        let paymentTerms = dict["paymentTerms"] as? String
        let sanityCheckNote = (dict["sanityCheck"] as? String)
            ?? (dict["sanityCheckNote"] as? String)
        let crossReferenceNotes = (dict["crossReferenceNotes"] as? String)
            ?? (dict["sourceReconciliation"] as? String)
        let workPlan: [EstimatePlanSection] = {
            guard let rawSections = dict["workPlan"] as? [[String: Any]] else { return [] }
            return rawSections.compactMap { raw in
                guard let title = raw["title"] as? String,
                      let steps = raw["steps"] as? [String],
                      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !steps.isEmpty else { return nil }
                return EstimatePlanSection(
                    id: (raw["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
                    title: title,
                    steps: steps
                )
            }
        }()
        let notes = dict["notes"] as? String

        var built = Estimate(
            estimateNumber: estimateNumber,
            title: title,
            categories: categories,
            subtotal: subtotal,
            markupPercent: markupPercent,
            markupAmount: markupAmount,
            total: total,
            createdAt: Date(),
            chatSessionId: chatSessionId,
            siteConditions: siteConditions,
            permitInfo: permitInfo,
            contingency: contingency,
            toolRental: toolRental,
            wasteFactors: wasteFactors,
            exclusions: exclusions,
            paymentTerms: paymentTerms,
            sanityCheckNote: sanityCheckNote,
            crossReferenceNotes: crossReferenceNotes,
            workPlan: workPlan,
            notes: notes
        )
        built.supabaseEstimateId = supabaseEstimateId
        return built
    }
}
