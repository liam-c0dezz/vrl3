//
//  RetentionTests.swift
//  Construction EstimateTests
//

import Foundation
import Testing
@testable import Construction_Estimate

struct RetentionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }()

    /// Wednesday noon of the week `offset` weeks from the reference week.
    private func week(_ offset: Int) -> Date {
        let reference = calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        return calendar.date(byAdding: .weekOfYear, value: offset, to: reference)!
    }

    @Test func noActivityMeansNoStreak() {
        let streak = WeeklyStreak.compute(activityDates: [], now: week(0), calendar: calendar)
        #expect(streak.weeks == 0)
        #expect(!streak.isAtRisk)
    }

    @Test func consecutiveWeeksCount() {
        let streak = WeeklyStreak.compute(activityDates: [week(-2), week(-1), week(0)], now: week(0), calendar: calendar)
        #expect(streak.weeks == 3)
        #expect(streak.isActiveThisWeek)
        #expect(!streak.isAtRisk)
    }

    @Test func currentWeekInProgressIsAtRiskNotBroken() {
        let streak = WeeklyStreak.compute(activityDates: [week(-2), week(-1)], now: week(0), calendar: calendar)
        #expect(streak.weeks == 2)
        #expect(streak.isAtRisk)
    }

    @Test func missedWeekWithoutFreezeResetsStreak() {
        let streak = WeeklyStreak.compute(activityDates: [week(-4), week(-3), week(-1)], now: week(0), calendar: calendar)
        #expect(streak.weeks == 1)
        #expect(streak.longestWeeks == 2)
    }

    @Test func fourWeeksEarnAFreezeThatSavesAMissedWeek() {
        let dates = [week(-6), week(-5), week(-4), week(-3), week(-1)]
        let streak = WeeklyStreak.compute(activityDates: dates, now: week(0), calendar: calendar)
        #expect(streak.weeks == 5)
        #expect(streak.freezesAvailable == 0)
        #expect(!streak.freezeUsedLastWeek)
    }

    @Test func freezeUsedLastWeekIsReported() {
        let dates = [week(-5), week(-4), week(-3), week(-2)]
        let streak = WeeklyStreak.compute(activityDates: dates, now: week(0), calendar: calendar)
        #expect(streak.weeks == 4)
        #expect(streak.freezeUsedLastWeek)
        #expect(streak.isAtRisk)
    }

    @Test func freezesAreCappedAtTwo() {
        let dates = (-13...0).map(week)
        let streak = WeeklyStreak.compute(activityDates: dates, now: week(0), calendar: calendar)
        #expect(streak.weeks == 14)
        #expect(streak.freezesAvailable == WeeklyStreak.maxFreezes)
    }

    @Test func weeksStartOnMondayInTheUsersTimeZone() {
        let sundayNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 23))!
        let mondayMorning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 7))!
        #expect(WeeklyStreak.weekStart(of: sundayNight, calendar: calendar) != WeeklyStreak.weekStart(of: mondayMorning, calendar: calendar))
    }

    @Test func quietHoursWrapPastMidnight() {
        let preferences = NotificationPreferences()
        #expect(preferences.isQuiet(hour: 22))
        #expect(preferences.isQuiet(hour: 3))
        #expect(!preferences.isQuiet(hour: 8))
        #expect(preferences.allowedHour(23) == 8)
        #expect(preferences.allowedHour(10) == 10)
    }

    @Test func usualHourFollowsActivityAndStaysInWorkingHours() {
        let dates = (0..<6).map { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + $0, hour: 15))! }
        #expect(RetentionCenter.usualHour(from: dates, calendar: calendar) == 15)
        let late = (0..<6).map { calendar.date(from: DateComponents(year: 2026, month: 10, day: 5 + $0, hour: 23))! }
        #expect(RetentionCenter.usualHour(from: late, calendar: calendar) == 20)
        #expect(RetentionCenter.usualHour(from: [], calendar: calendar) == 9)
    }
}
