//
//  RetentionCenter.swift
//  Construction Estimate
//
//  The habit loop: trigger (reminder at the user's usual hour, widget,
//  streak at risk) -> one small action (send an estimate) -> reward (streak,
//  weekly recap) -> investment (history, streak freezes).
//
//  Everything here works on-device with no extra services. Remote pushes and
//  lifecycle email are handled by the `retention-dispatch` edge function.
//

import Foundation
import Auth
import Observation
import PostgREST
import Supabase
import SuperwallKit
import UserNotifications
import WidgetKit

enum RetentionEvent {
    case estimateSent(amount: Double)
    case invoiceSent(amount: Double)
    case paymentRecorded(amount: Double)

    var kind: String {
        switch self {
        case .estimateSent: "estimate_sent"
        case .invoiceSent: "invoice_sent"
        case .paymentRecorded: "payment_recorded"
        }
    }

    var amount: Double {
        switch self {
        case .estimateSent(let amount), .invoiceSent(let amount), .paymentRecorded(let amount): amount
        }
    }
}

/// How many reminders the user wants. Client activity and the trial-ending
/// reminder count as "important".
enum ReminderFrequency: String, CaseIterable, Identifiable, Codable {
    case all
    case important
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L("All reminders")
        case .important: L("Important only")
        case .off: L("Off")
        }
    }

    var detail: String {
        switch self {
        case .all: L("Client activity, trial reminders, streak reminders and your weekly recap.")
        case .important: L("Only client activity and trial reminders.")
        case .off: L("No notifications from EasyBid.")
        }
    }
}

struct NotificationPreferences: Codable, Equatable {
    var frequency: ReminderFrequency = .all
    /// Local hours, 0-23. Reminders never fire from `quietStart` to `quietEnd`.
    var quietStart = 21
    var quietEnd = 8
    var streakReminders = true
    var weeklyRecap = true
    var productEmails = true

    func isQuiet(hour: Int) -> Bool {
        if quietStart == quietEnd { return false }
        if quietStart < quietEnd { return hour >= quietStart && hour < quietEnd }
        return hour >= quietStart || hour < quietEnd
    }

    /// Moves an hour out of quiet hours to the end of the quiet window.
    func allowedHour(_ hour: Int) -> Int {
        isQuiet(hour: hour) ? quietEnd : hour
    }
}

struct ActivityRecord: Codable, Hashable {
    var id: String
    var kind: String
    var date: Date
    var amount: Double
}

struct WeeklyRecap: Equatable {
    var weekStart: Date
    var estimatesSent: Int
    var invoicesSent: Int
    var paymentsRecorded: Int
    var quotedValue: Double
    var collectedValue: Double
    var streakWeeks: Int

    var isEmpty: Bool { estimatesSent + invoicesSent + paymentsRecorded == 0 }
}

@MainActor
@Observable
final class RetentionCenter {
    static let shared = RetentionCenter()

    private enum Key {
        static let activity = "retention.activity.v1"
        static let preferences = "retention.preferences.v1"
        static let wins = "retention.wins"
        static let promptsShown = "retention.notificationPromptsShown"
        static let lastReviewRequest = "retention.lastReviewRequest"
        static let firstLaunch = "retention.firstLaunch"
        static let trialStartedAt = "retention.trialStartedAt"
        static let everSubscribed = "retention.everSubscribed"
        static let lastWinBack = "retention.lastWinBack"
        static let lastProfileSync = "retention.lastProfileSync"
    }

    static let weeklyGoal = 3

    private(set) var streak = WeeklyStreak(weeks: 0, longestWeeks: 0, freezesAvailable: 0, isActiveThisWeek: false, freezeUsedLastWeek: false)
    private(set) var thisWeek = WeeklyRecap(weekStart: Date(), estimatesSent: 0, invoicesSent: 0, paymentsRecorded: 0, quotedValue: 0, collectedValue: 0, streakWeeks: 0)
    private(set) var lastWeek = WeeklyRecap(weekStart: Date(), estimatesSent: 0, invoicesSent: 0, paymentsRecorded: 0, quotedValue: 0, collectedValue: 0, streakWeeks: 0)
    private(set) var preferredHour = 9
    private(set) var trialStartedAt: Date?
    private(set) var preferences: NotificationPreferences

    func updatePreferences(_ newValue: NotificationPreferences) {
        guard newValue != preferences else { return }
        preferences = newValue
        persist(newValue, key: Key.preferences)
        Task {
            await rescheduleLocalReminders()
            await syncProfile(force: true)
        }
    }

    /// Set after a win when the system permission has not been asked yet;
    /// ContentView shows the pre-prompt sheet while this is true.
    var shouldOfferNotifications = false
    /// Set after a win when it is a good moment to ask for an App Store review.
    var shouldRequestReview = false

    @ObservationIgnored private var activity: [ActivityRecord]
    @ObservationIgnored private let defaults = UserDefaults.standard

    private init() {
        activity = Self.load([ActivityRecord].self, key: Key.activity) ?? []
        preferences = Self.load(NotificationPreferences.self, key: Key.preferences) ?? NotificationPreferences()
        trialStartedAt = defaults.object(forKey: Key.trialStartedAt) as? Date
        if defaults.object(forKey: Key.firstLaunch) == nil {
            defaults.set(Date(), forKey: Key.firstLaunch)
        }
        recompute()
    }

    // MARK: Wins

    /// Call after the user completes a meaningful action.
    func record(_ event: RetentionEvent) {
        activity.append(ActivityRecord(id: UUID().uuidString, kind: event.kind, date: Date(), amount: event.amount))
        activity = Array(activity.suffix(500))
        persist(activity, key: Key.activity)
        defaults.set(defaults.integer(forKey: Key.wins) + 1, forKey: Key.wins)
        recompute()
        log("win", ["kind": event.kind])

        Task {
            await rescheduleLocalReminders()
            await considerNotificationPrompt()
        }
        considerReviewPrompt(after: event)
    }

    /// Recomputes the streak from the activity log plus existing estimates and
    /// invoices, so people who used the app before this feature keep credit.
    func refresh() {
        recompute()
        Task {
            await rescheduleLocalReminders()
            await syncProfile(force: false)
            checkWinBack()
        }
    }

    private func recompute() {
        let calendar = WeeklyStreak.calendar()
        var records = activity
        let known = Set(records.map(\.id))
        for project in ProjectStore.shared.projects {
            if let estimate = project.estimate, !known.contains(estimate.id.uuidString) {
                records.append(ActivityRecord(id: estimate.id.uuidString, kind: "estimate_created", date: estimate.createdAt, amount: estimate.total))
            }
        }
        for invoice in InvoiceStore.shared.invoices where invoice.status.caseInsensitiveCompare("Draft") != .orderedSame {
            let id = "invoice-\(invoice.id.uuidString)"
            if !known.contains(id) {
                records.append(ActivityRecord(id: id, kind: "invoice_sent", date: invoice.createdAt, amount: invoice.total))
            }
        }

        streak = WeeklyStreak.compute(activityDates: records.map(\.date), calendar: calendar)
        let currentWeek = WeeklyStreak.weekStart(of: Date(), calendar: calendar)
        let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek) ?? currentWeek
        thisWeek = recap(for: currentWeek, records: records, calendar: calendar)
        lastWeek = recap(for: previousWeek, records: records, calendar: calendar)
        preferredHour = Self.usualHour(from: records.map(\.date), calendar: calendar)

        RetentionSnapshot(
            streakWeeks: streak.weeks,
            freezesAvailable: streak.freezesAvailable,
            isActiveThisWeek: streak.isActiveThisWeek,
            weekActions: thisWeek.estimatesSent + thisWeek.invoicesSent + thisWeek.paymentsRecorded,
            weekValue: thisWeek.quotedValue,
            weeklyGoal: Self.weeklyGoal,
            language: LanguageStore.shared.current.rawValue,
            updatedAt: Date()
        ).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func recap(for weekStart: Date, records: [ActivityRecord], calendar: Calendar) -> WeeklyRecap {
        let end = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
        let week = records.filter { $0.date >= weekStart && $0.date < end }
        let estimates = week.filter { $0.kind == "estimate_sent" || $0.kind == "estimate_created" }
        let invoices = week.filter { $0.kind == "invoice_sent" }
        let payments = week.filter { $0.kind == "payment_recorded" }
        return WeeklyRecap(
            weekStart: weekStart,
            estimatesSent: estimates.count,
            invoicesSent: invoices.count,
            paymentsRecorded: payments.count,
            quotedValue: estimates.reduce(0) { $0 + $1.amount },
            collectedValue: payments.reduce(0) { $0 + $1.amount },
            streakWeeks: streak.weeks
        )
    }

    /// The hour the user most often works in the app (weekday activity),
    /// used to time reminders. Defaults to 9 AM until there is history.
    static func usualHour(from dates: [Date], calendar: Calendar) -> Int {
        let recent = dates.sorted().suffix(40)
        guard recent.count >= 3 else { return 9 }
        var counts: [Int: Int] = [:]
        for date in recent {
            counts[calendar.component(.hour, from: date), default: 0] += 1
        }
        let best = counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key ?? 9
        return min(max(best, 7), 20)
    }

    // MARK: Notification permission (asked after the first win, never on launch)

    private func considerNotificationPrompt() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        let shown = defaults.integer(forKey: Key.promptsShown)
        guard shown < 2, defaults.integer(forKey: Key.wins) >= 1 else { return }
        shouldOfferNotifications = true
    }

    func notificationPromptShown() {
        defaults.set(defaults.integer(forKey: Key.promptsShown) + 1, forKey: Key.promptsShown)
        log("notification_prompt_shown", [:])
    }

    func requestNotificationPermission() async {
        shouldOfferNotifications = false
        let granted = await NotificationService.shared.requestAuthorization()
        log("notification_permission", ["granted": granted ? "true" : "false"])
        await rescheduleLocalReminders()
    }

    func declineNotificationPrompt() {
        shouldOfferNotifications = false
        log("notification_prompt_declined", [:])
    }

    // MARK: Review prompt (after a win, at most every 120 days)

    private func considerReviewPrompt(after event: RetentionEvent) {
        let wins = defaults.integer(forKey: Key.wins)
        let firstLaunch = defaults.object(forKey: Key.firstLaunch) as? Date ?? Date()
        let lastAsked = defaults.object(forKey: Key.lastReviewRequest) as? Date ?? .distantPast
        guard wins >= 3,
              Date().timeIntervalSince(firstLaunch) > 3 * 86_400,
              Date().timeIntervalSince(lastAsked) > 120 * 86_400
        else { return }
        if case .estimateSent = event {} else if case .paymentRecorded = event {} else { return }
        defaults.set(Date(), forKey: Key.lastReviewRequest)
        shouldRequestReview = true
        log("review_prompt", [:])
    }

    /// A client approving an estimate is the strongest win; ask then too.
    func clientApprovedEstimate() {
        let lastAsked = defaults.object(forKey: Key.lastReviewRequest) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAsked) > 120 * 86_400 else { return }
        defaults.set(Date(), forKey: Key.lastReviewRequest)
        shouldRequestReview = true
        log("review_prompt", ["trigger": "client_approved"])
    }

    // MARK: Subscription lifecycle

    /// Call when a purchase completes. The first purchase starts the free
    /// trial; the trial-ending reminder is scheduled from it.
    func subscriptionStarted() {
        defaults.set(true, forKey: Key.everSubscribed)
        if trialStartedAt == nil {
            let now = Date()
            trialStartedAt = now
            defaults.set(now, forKey: Key.trialStartedAt)
        }
        Task {
            await rescheduleLocalReminders()
            await syncProfile(force: true)
        }
    }

    var trialEndsAt: Date? {
        trialStartedAt.map { $0.addingTimeInterval(Double(SuperwallService.freeTrialDays) * 86_400) }
    }

    /// True during the last 24 hours of the trial; Home shows a banner then.
    var isTrialEndingSoon: Bool {
        guard let end = trialEndsAt else { return false }
        let remaining = end.timeIntervalSinceNow
        return remaining > 0 && remaining < 86_400
    }

    /// Lapsed subscribers see the Superwall "win_back" campaign (configure the
    /// campaign and an App Store win-back offer in the Superwall dashboard).
    func checkWinBack() {
        guard SuperwallService.isConfigured, defaults.bool(forKey: Key.everSubscribed) else { return }
        guard case .inactive = Superwall.shared.subscriptionStatus else { return }
        let last = defaults.object(forKey: Key.lastWinBack) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 86_400 else { return }
        defaults.set(Date(), forKey: Key.lastWinBack)
        Superwall.shared.register(placement: "win_back")
        log("win_back_placement", [:])
    }

    // MARK: Local reminders (no server or Apple key needed)

    private enum ReminderID {
        static let streak = "retention.streak"
        static let recap = "retention.recap"
        static let trial = "retention.trial"
    }

    func rescheduleLocalReminders() async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [ReminderID.streak, ReminderID.recap, ReminderID.trial])
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus),
              preferences.frequency != .off
        else { return }

        let calendar = WeeklyStreak.calendar()
        let hour = preferences.allowedHour(preferredHour)

        // Trial ending: always scheduled unless notifications are off.
        if let end = trialEndsAt {
            var fire = end.addingTimeInterval(-86_400)
            let fireHour = calendar.component(.hour, from: fire)
            if preferences.isQuiet(hour: fireHour) {
                fire = calendar.date(bySettingHour: preferences.quietEnd, minute: 0, second: 0, of: fire) ?? fire
            }
            if fire > Date() {
                await add(
                    id: ReminderID.trial,
                    category: "trial_ending",
                    title: L("Your free trial ends tomorrow"),
                    body: L("Keep sending estimates and invoices. Manage your plan anytime in Settings."),
                    at: fire,
                    route: "settings"
                )
            }
        }

        guard preferences.frequency == .all else { return }

        // Streak at risk: Friday at the user's usual hour, only if nothing yet this week.
        if preferences.streakReminders, streak.weeks > 0, !streak.isActiveThisWeek,
           let friday = nextDate(weekday: 6, hour: hour, calendar: calendar),
           calendar.isDate(friday, equalTo: Date(), toGranularity: .weekOfYear) {
            let variant = Self.variant(for: "streak")
            await add(
                id: ReminderID.streak,
                category: "streak_at_risk",
                title: variant == "a" ? L("Your %@-week streak is at risk", "\(streak.weeks)") : L("Keep your streak going"),
                body: streak.freezesAvailable > 0
                    ? L("Send one estimate this week. You also have a streak freeze ready.")
                    : L("Send one estimate before Sunday to keep your streak."),
                at: friday,
                route: "new-estimate",
                variant: variant
            )
        }

        // Weekly recap: Monday at the usual hour, only when there is something to show.
        if preferences.weeklyRecap, !thisWeek.isEmpty,
           let monday = nextDate(weekday: 2, hour: hour, calendar: calendar) {
            let variant = Self.variant(for: "recap")
            let total = thisWeek.estimatesSent + thisWeek.invoicesSent
            await add(
                id: ReminderID.recap,
                category: "weekly_recap",
                title: variant == "a" ? L("Your week in EasyBid") : L("This week you…"),
                body: thisWeek.quotedValue > 0
                    ? L("You sent %@ estimates and invoices worth %@. See your recap.", "\(total)", Self.currency(thisWeek.quotedValue))
                    : L("You sent %@ estimates and invoices. See your recap.", "\(total)"),
                at: monday,
                route: "recap",
                variant: variant
            )
        }
    }

    private func nextDate(weekday: Int, hour: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = 0
        return calendar.nextDate(after: Date(), matching: components, matchingPolicy: .nextTime)
    }

    private func add(id: String, category: String, title: String, body: String, at date: Date, route: String, variant: String = "a") async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = category
        content.userInfo = ["route": route, "category": category, "variant": variant]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Stable A/B copy variant per user and category, so opens can be compared.
    static func variant(for category: String) -> String {
        let seed = (UserDefaults.standard.string(forKey: "retention.installID") ?? {
            let id = UUID().uuidString
            UserDefaults.standard.set(id, forKey: "retention.installID")
            return id
        }()) + category
        let sum = seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return sum % 2 == 0 ? "a" : "b"
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)).locale(appLocale))
    }

    // MARK: Server sync (Supabase)

    /// Stores time zone, language, usual hour, quiet hours and frequency so
    /// server pushes and lifecycle email follow the same rules.
    func syncProfile(force: Bool) async {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let last = defaults.object(forKey: Key.lastProfileSync) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > 6 * 3600 else { return }
        let row = RetentionProfileRow(
            user_id: userID,
            timezone: TimeZone.current.identifier,
            language: LanguageStore.shared.current.rawValue,
            preferred_hour: preferredHour,
            quiet_start: preferences.quietStart,
            quiet_end: preferences.quietEnd,
            frequency: preferences.frequency.rawValue,
            email_opt_in: preferences.productEmails,
            trial_started_at: trialStartedAt,
            last_active_at: Date()
        )
        do {
            try await supabase.from("retention_profiles").upsert(row, onConflict: "user_id").execute()
            defaults.set(Date(), forKey: Key.lastProfileSync)
        } catch {
            // Retried on the next refresh; reminders keep working locally.
        }
    }

    /// Opt-in rate, push -> open and copy tests are measured from these rows.
    func log(_ event: String, _ properties: [String: String]) {
        guard let userID = supabase.auth.currentUser?.id else { return }
        let row = EngagementEventRow(user_id: userID, event: event, properties: properties)
        Task {
            _ = try? await supabase.from("engagement_events").insert(row).execute()
        }
    }

    func reset() {
        activity = []
        persist(activity, key: Key.activity)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [ReminderID.streak, ReminderID.recap, ReminderID.trial])
        recompute()
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

private struct RetentionProfileRow: Encodable {
    let user_id: UUID
    let timezone: String
    let language: String
    let preferred_hour: Int
    let quiet_start: Int
    let quiet_end: Int
    let frequency: String
    let email_opt_in: Bool
    let trial_started_at: Date?
    let last_active_at: Date
}

private struct EngagementEventRow: Encodable {
    let user_id: UUID
    let event: String
    let properties: [String: String]
}
