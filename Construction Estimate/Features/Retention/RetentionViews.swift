//
//  RetentionViews.swift
//  Construction Estimate
//
//  Streak card, weekly recap (with share card), trial banner, notification
//  pre-prompt and notification settings.
//

import SwiftUI
import UIKit
import UserNotifications

// MARK: - Pre-prompt (shown after the first win, never on launch)

struct NotificationPrePromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var center: RetentionCenter { RetentionCenter.shared }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(AppBrand.accent)
                .frame(width: 84, height: 84)
                .background(AppBrand.accent.opacity(0.1))
                .clipShape(Circle())
                .padding(.top, 8)

            Text(L("Know the moment a client says yes"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppGray.ink)
                .multilineTextAlignment(.center)

            Text(L("Get notified when a client views or approves an estimate, plus a reminder before your trial ends. You choose how often in Settings."))
                .font(.system(size: 16))
                .foregroundStyle(AppGray.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            HapticButton {
                Task {
                    await center.requestNotificationPermission()
                    dismiss()
                }
            } label: {
                Text(L("Turn on notifications"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(AppBrand.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            HapticButton {
                center.declineNotificationPrompt()
                dismiss()
            } label: {
                Text(L("Not now"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppGray.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { center.notificationPromptShown() }
    }
}

// MARK: - Streak card (Home)

struct StreakCard: View {
    private var center: RetentionCenter { RetentionCenter.shared }

    var body: some View {
        let streak = center.streak
        let week = center.thisWeek
        let actions = week.estimatesSent + week.invoicesSent + week.paymentsRecorded
        let goal = RetentionCenter.weeklyGoal

        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(streak.isAtRisk ? Color.orange.opacity(0.14) : AppBrand.accent.opacity(0.1))
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(streak.isAtRisk ? Color.orange : AppBrand.accent)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text(streak.weeks == 1 ? L("1-week streak") : L("%@-week streak", streak.weeks.formatted()))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                Text(subtitle(streak: streak, actions: actions, goal: goal))
                    .font(.system(size: 13))
                    .foregroundStyle(AppGray.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text("\(min(actions, goal))/\(goal)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                    .monospacedDigit()
                if streak.freezesAvailable > 0 {
                    Label(streak.freezesAvailable.formatted(), systemImage: "snowflake")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                        .accessibilityLabel(L("Streak freezes: %@", streak.freezesAvailable.formatted()))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .accessibilityElement(children: .combine)
    }

    private func subtitle(streak: WeeklyStreak, actions: Int, goal: Int) -> String {
        if streak.weeks == 0 { return L("Send an estimate this week to start a streak.") }
        if streak.isAtRisk { return L("Send one estimate this week to keep it going.") }
        if streak.freezeUsedLastWeek { return L("A streak freeze saved your streak last week.") }
        if actions >= goal { return L("Weekly goal reached. Nice work!") }
        return L("Every week with a sent estimate or invoice counts.")
    }
}

// MARK: - Weekly recap

struct WeeklyRecapCard: View {
    let recap: WeeklyRecap
    @State private var shareImage: Image?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L("This week you…"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                Spacer()
                if let shareImage {
                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(L("My week in EasyBid"), image: shareImage)
                    ) {
                        Label(L("Share"), systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppBrand.accent)
                    }
                    .simultaneousGesture(TapGesture().onEnded { RetentionCenter.shared.log("recap_shared", [:]) })
                }
            }

            HStack(spacing: 10) {
                RecapMetric(value: recap.estimatesSent.formatted(), label: L("Estimates"))
                RecapMetric(value: recap.invoicesSent.formatted(), label: L("Invoices"))
                RecapMetric(value: RetentionCenter.currency(recap.quotedValue), label: L("Quoted"))
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .task(id: recap) { renderShareImage() }
    }

    private func renderShareImage() {
        let renderer = ImageRenderer(content: RecapShareCard(recap: recap).frame(width: 360, height: 360))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            shareImage = Image(uiImage: uiImage)
        }
    }
}

private struct RecapMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppGray.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppGray.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppGray.pill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The image people share: brand gradient, the week's numbers, the streak.
struct RecapShareCard: View {
    let recap: WeeklyRecap

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L("This week you…"))
                .font(.system(size: 26, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 10) {
                line(L("Sent %@ estimates", recap.estimatesSent.formatted()))
                line(L("Sent %@ invoices", recap.invoicesSent.formatted()))
                line(L("Quoted %@", RetentionCenter.currency(recap.quotedValue)))
                if recap.streakWeeks > 1 {
                    line(L("Kept a %@-week streak", recap.streakWeeks.formatted()))
                }
            }
            Spacer()
            Text("EasyBid")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppBrand.verticalGradient)
    }

    private func line(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
    }
}

// MARK: - Trial banner

struct TrialEndingBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppBrand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Your free trial ends tomorrow"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppGray.ink)
                Text(L("Manage or cancel anytime in iPhone Settings > Subscriptions."))
                    .font(.system(size: 13))
                    .foregroundStyle(AppGray.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppBrand.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Settings

struct NotificationSettingsView: View {
    @State private var preferences = RetentionCenter.shared.preferences
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        List {
            if status == .denied {
                Section {
                    Text(L("Notifications are turned off for EasyBid in iPhone Settings."))
                        .font(.system(size: 15))
                    HapticButton("Open Settings") { AppPermissions.openSettings() }
                }
            } else if status == .notDetermined {
                Section {
                    HapticButton("Turn on notifications") {
                        Task {
                            await RetentionCenter.shared.requestNotificationPermission()
                            status = await NotificationService.shared.authorizationStatus
                        }
                    }
                }
            }

            Section {
                Picker(L("Reminders"), selection: $preferences.frequency) {
                    ForEach(ReminderFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text(L("How often"))
            } footer: {
                Text(preferences.frequency.detail)
            }

            if preferences.frequency == .all {
                Section {
                    Toggle(L("Streak reminders"), isOn: $preferences.streakReminders)
                    Toggle(L("Weekly recap"), isOn: $preferences.weeklyRecap)
                }
            }

            Section {
                Picker(L("Starts"), selection: $preferences.quietStart) {
                    ForEach(0..<24, id: \.self) { hour in Text(Self.hourLabel(hour)).tag(hour) }
                }
                Picker(L("Ends"), selection: $preferences.quietEnd) {
                    ForEach(0..<24, id: \.self) { hour in Text(Self.hourLabel(hour)).tag(hour) }
                }
            } header: {
                Text(L("Quiet hours"))
            } footer: {
                Text(L("Reminders wait until quiet hours end. Times follow this iPhone's time zone."))
            }

            Section {
                Toggle(L("Tips and product emails"), isOn: $preferences.productEmails)
            } footer: {
                Text(L("Trial and account emails are always sent."))
            }
        }
        .navigationTitle(L("Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: preferences) { _, newValue in
            RetentionCenter.shared.updatePreferences(newValue)
        }
        .task {
            status = await NotificationService.shared.authorizationStatus
        }
    }

    private static func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(appLocale))
    }
}
