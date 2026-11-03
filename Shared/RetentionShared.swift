//
//  RetentionShared.swift
//  Shared by the EasyBid app and the EasyBidWidget extension.
//
//  Everything here is plain value logic so both targets compile it as-is:
//  the App Group store the widget reads, the weekly streak engine (with
//  streak freezes), the Live Activity attributes for estimate generation,
//  and the small set of strings the widget renders in English or Spanish.
//

import Foundation
import ActivityKit

// MARK: - App Group

nonisolated enum RetentionShared {
    /// Must match the App Groups entitlement of both targets.
    static let appGroupID = "group.com.constructionestimate.Construction-Estimate"
    static let snapshotKey = "retention.snapshot.v1"
    /// URL scheme already registered by the app (CFBundleURLSchemes).
    static let urlScheme = "com.constructionestimate.Construction-Estimate"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func deepLink(_ host: String) -> URL {
        URL(string: "\(urlScheme)://\(host)")!
    }
}

// MARK: - Widget snapshot

/// What the home-screen widget shows. The app writes it after every change;
/// the widget only reads it, so the widget never needs network access.
nonisolated struct RetentionSnapshot: Codable, Equatable {
    var streakWeeks: Int
    var freezesAvailable: Int
    var isActiveThisWeek: Bool
    var weekActions: Int
    var weekValue: Double
    var weeklyGoal: Int
    var language: String
    var updatedAt: Date

    static let placeholder = RetentionSnapshot(
        streakWeeks: 3,
        freezesAvailable: 1,
        isActiveThisWeek: true,
        weekActions: 2,
        weekValue: 12_400,
        weeklyGoal: 3,
        language: "en",
        updatedAt: Date()
    )

    var isAtRisk: Bool { streakWeeks > 0 && !isActiveThisWeek }

    static func load() -> RetentionSnapshot? {
        guard let data = RetentionShared.defaults.data(forKey: RetentionShared.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(RetentionSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        RetentionShared.defaults.set(data, forKey: RetentionShared.snapshotKey)
    }
}

// MARK: - Weekly streak engine

/// A streak counts consecutive weeks (Monday to Sunday, in the user's time
/// zone) with at least one action: an estimate created or sent, an invoice
/// sent, or a payment recorded.
///
/// Streak freeze: every 4 active weeks in a row earns one freeze (holding at
/// most 2). A week with no action automatically spends a freeze instead of
/// resetting the streak. The current week never breaks a streak while it is
/// still in progress; it is only "at risk".
nonisolated struct WeeklyStreak: Equatable {
    var weeks: Int
    var longestWeeks: Int
    var freezesAvailable: Int
    var isActiveThisWeek: Bool
    var freezeUsedLastWeek: Bool

    static let weeksPerFreeze = 4
    static let maxFreezes = 2

    var isAtRisk: Bool { weeks > 0 && !isActiveThisWeek }

    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Start of the week (Monday 00:00) containing `date`.
    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func compute(
        activityDates: [Date],
        now: Date = Date(),
        calendar: Calendar = WeeklyStreak.calendar()
    ) -> WeeklyStreak {
        let activeWeeks = Set(activityDates.filter { $0 <= now }.map { weekStart(of: $0, calendar: calendar) })
        let currentWeek = weekStart(of: now, calendar: calendar)
        guard let firstWeek = activeWeeks.min() else {
            return WeeklyStreak(weeks: 0, longestWeeks: 0, freezesAvailable: 0, isActiveThisWeek: false, freezeUsedLastWeek: false)
        }

        var streak = 0
        var longest = 0
        var run = 0
        var freezes = 0
        var freezeUsedLastWeek = false
        var week = firstWeek

        while week <= currentWeek {
            let isCurrent = week == currentWeek
            if activeWeeks.contains(week) {
                streak += 1
                run += 1
                if run % weeksPerFreeze == 0 && freezes < maxFreezes {
                    freezes += 1
                }
                if !isCurrent { freezeUsedLastWeek = false }
            } else if !isCurrent {
                if streak > 0 && freezes > 0 {
                    freezes -= 1
                    freezeUsedLastWeek = true
                } else {
                    streak = 0
                    run = 0
                    freezeUsedLastWeek = false
                }
            }
            longest = max(longest, streak)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }

        return WeeklyStreak(
            weeks: streak,
            longestWeeks: longest,
            freezesAvailable: freezes,
            isActiveThisWeek: activeWeeks.contains(currentWeek),
            freezeUsedLastWeek: freezeUsedLastWeek
        )
    }
}

// MARK: - Live Activity

/// Lock Screen / Dynamic Island progress while an AI estimate is generated.
nonisolated struct EstimateGenerationAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var progress: Int
        var isComplete: Bool
    }

    var language: String
}

// MARK: - Widget strings

/// The widget extension cannot load the app's translation table, so the few
/// strings it renders live here in both languages.
nonisolated enum SharedText: String {
    case weekStreak, weeksInARow, thisWeek, estimatesSent, goalReached, keepStreak
    case freezeReady, startStreak, newEstimate, creatingEstimate, estimateReady, openToReview

    func text(_ language: String) -> String {
        let spanish = language.hasPrefix("es")
        switch self {
        case .weekStreak: return spanish ? "Racha semanal" : "Week streak"
        case .weeksInARow: return spanish ? "semanas seguidas" : "weeks in a row"
        case .thisWeek: return spanish ? "Esta semana" : "This week"
        case .estimatesSent: return spanish ? "acciones" : "actions"
        case .goalReached: return spanish ? "¡Meta cumplida!" : "Goal reached!"
        case .keepStreak: return spanish ? "Envía una cotización para mantener tu racha" : "Send an estimate to keep your streak"
        case .freezeReady: return spanish ? "Protección lista" : "Freeze ready"
        case .startStreak: return spanish ? "Envía una cotización para empezar tu racha" : "Send an estimate to start a streak"
        case .newEstimate: return spanish ? "Nueva cotización" : "New estimate"
        case .creatingEstimate: return spanish ? "Creando tu cotización" : "Creating your estimate"
        case .estimateReady: return spanish ? "Tu cotización está lista" : "Your estimate is ready"
        case .openToReview: return spanish ? "Abre EasyBid para revisarla" : "Open EasyBid to review it"
        }
    }
}
