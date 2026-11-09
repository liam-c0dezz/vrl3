//
//  WeeklyProgressWidget.swift
//  EasyBidWidget
//
//  Home screen and Lock Screen widget: week streak and this week's progress.
//  Reads the snapshot the app writes to the shared App Group.
//

import SwiftUI
import WidgetKit

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: RetentionSnapshot
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: Date(), snapshot: RetentionSnapshot.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let snapshot = RetentionSnapshot.load() ?? RetentionSnapshot(
            streakWeeks: 0, freezesAvailable: 0, isActiveThisWeek: false,
            weekActions: 0, weekValue: 0, weeklyGoal: 3, language: "en", updatedAt: Date()
        )
        let entry = ProgressEntry(date: Date(), snapshot: rolledOver(snapshot))
        // Refresh after the next Monday so a new week starts at zero; the app
        // also reloads the widget whenever something changes.
        let calendar = WeeklyStreak.calendar()
        let nextWeek = calendar.date(
            byAdding: .weekOfYear, value: 1,
            to: WeeklyStreak.weekStart(of: Date(), calendar: calendar)
        ) ?? Date().addingTimeInterval(86_400)
        completion(Timeline(entries: [entry], policy: .after(min(nextWeek, Date().addingTimeInterval(6 * 3600)))))
    }

    /// If the snapshot is from an earlier week, this week has no actions yet.
    private func rolledOver(_ snapshot: RetentionSnapshot) -> RetentionSnapshot {
        let calendar = WeeklyStreak.calendar()
        guard WeeklyStreak.weekStart(of: snapshot.updatedAt, calendar: calendar)
                < WeeklyStreak.weekStart(of: Date(), calendar: calendar)
        else { return snapshot }
        var copy = snapshot
        copy.weekActions = 0
        copy.weekValue = 0
        copy.isActiveThisWeek = false
        return copy
    }
}

struct WeeklyProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklyProgress", provider: ProgressProvider()) { entry in
            WeeklyProgressView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0.043, green: 0.180, blue: 0.353), Color(red: 0.204, green: 0.498, blue: 0.898)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .widgetURL(RetentionShared.deepLink("new-estimate"))
        }
        .configurationDisplayName("EasyBid")
        .description("Week streak and this week's estimates.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct WeeklyProgressView: View {
    let snapshot: RetentionSnapshot
    @Environment(\.widgetFamily) private var family

    private var lang: String { snapshot.language }
    private var progress: Double {
        guard snapshot.weeklyGoal > 0 else { return 0 }
        return min(Double(snapshot.weekActions) / Double(snapshot.weeklyGoal), 1)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: progress) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(snapshot.streakWeeks)")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("\(snapshot.streakWeeks) · \(SharedText.weekStreak.text(lang))", systemImage: "flame.fill")
                    .font(.headline)
                Text("\(SharedText.thisWeek.text(lang)): \(snapshot.weekActions)/\(snapshot.weeklyGoal)")
                    .font(.caption)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                streakBlock
                Divider().overlay(.white.opacity(0.3))
                weekBlock
            }
            .foregroundStyle(.white)
        default:
            VStack(alignment: .leading, spacing: 10) {
                streakBlock
                Spacer(minLength: 0)
                progressBar
                Text(snapshot.isAtRisk ? SharedText.keepStreak.text(lang) : "\(SharedText.thisWeek.text(lang)) \(snapshot.weekActions)/\(snapshot.weeklyGoal)")
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
        }
    }

    private var streakBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(snapshot.isAtRisk ? .orange : .white)
                Text(SharedText.weekStreak.text(lang))
                    .font(.caption.weight(.semibold))
                    .opacity(0.85)
            }
            Text("\(snapshot.streakWeeks)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            if snapshot.freezesAvailable > 0 {
                Label(SharedText.freezeReady.text(lang), systemImage: "snowflake")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.85)
            }
        }
    }

    private var weekBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SharedText.thisWeek.text(lang))
                .font(.caption.weight(.semibold))
                .opacity(0.85)
            Text("\(snapshot.weekActions)/\(snapshot.weeklyGoal)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            progressBar
            Text(snapshot.weekActions >= snapshot.weeklyGoal
                 ? SharedText.goalReached.text(lang)
                 : (snapshot.streakWeeks == 0 ? SharedText.startStreak.text(lang) : SharedText.keepStreak.text(lang)))
                .font(.caption2.weight(.medium))
                .lineLimit(2)
                .opacity(0.85)
            Spacer(minLength: 0)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}
