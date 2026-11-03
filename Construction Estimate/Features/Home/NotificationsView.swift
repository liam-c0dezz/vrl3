import SwiftUI
import Observation
import Supabase
import PostgREST

struct AppNotification: Identifiable {
    let id: String
    let projectId: UUID
    let estimateId: UUID
    let eventType: String
    let title: String
    let message: String
    var isRead: Bool
    let date: Date

    var icon: String {
        switch eventType {
        case "approved": return "checkmark.circle.fill"
        case "changes_requested": return "arrow.trianglehead.2.clockwise.rotate.90"
        default: return "eye.fill"
        }
    }
}

private struct EstimateShareActivityRow: Decodable {
    let id: UUID
    let estimate_id: UUID
    let project_id: UUID
    let status: String
    let first_viewed_at: String?
    let approved_at: String?
    let approved_by: String?
    let change_requested_at: String?
    let change_request: String?
    let snapshot: EstimateShareSnapshot
}

private struct EstimateShareSnapshot: Decodable {
    let estimate: EstimateShareSummary
}

private struct EstimateShareSummary: Decodable {
    let number: String
}

private enum NotificationDate {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard = ISO8601DateFormatter()

    static func parse(_ value: String?) -> Date {
        guard let value else { return Date() }
        return fractional.date(from: value) ?? standard.date(from: value) ?? Date()
    }
}

@Observable
@MainActor
final class NotificationStore {
    static let shared = NotificationStore()

    var notifications: [AppNotification] = []
    var isLoading = false
    var lastError: String?
    private var pollingTask: Task<Void, Never>?
    private var readIDs: Set<String>

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    private init() {
        readIDs = Set(UserDefaults.standard.stringArray(forKey: "readEstimateActivityIDs") ?? [])
    }

    func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let rows: [EstimateShareActivityRow] = try await supabase
                .from("estimate_share_links")
                .select(
                    """
                    id, estimate_id, project_id, status, first_viewed_at, approved_at, \
                    approved_by, change_requested_at, change_request, snapshot
                    """
                )
                .in("status", values: ["viewed", "approved", "changes_requested"])
                .order("updated_at", ascending: false)
                .limit(100)
                .execute()
                .value

            notifications = rows.map(makeNotification).sorted { $0.date > $1.date }
            lastError = nil
        } catch {
            lastError = SafeErrorMessages.data(error, action: "notification update")
        }
    }

    func markRead(_ notification: AppNotification) {
        guard !notification.isRead else { return }
        readIDs.insert(notification.id)
        persistReadIDs()
        if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
            notifications[index].isRead = true
        }
    }

    func markAllRead() {
        for notification in notifications {
            readIDs.insert(notification.id)
        }
        persistReadIDs()
        notifications = notifications.map {
            var notification = $0
            notification.isRead = true
            return notification
        }
    }

    private func makeNotification(from row: EstimateShareActivityRow) -> AppNotification {
        let notificationID = "\(row.id.uuidString):\(row.status)"
        let estimateNumber = row.snapshot.estimate.number

        switch row.status {
        case "approved":
            return AppNotification(
                id: notificationID,
                projectId: row.project_id,
                estimateId: row.estimate_id,
                eventType: row.status,
                title: L("Estimate approved"),
                message: L("%@ was approved by %@.", "\(estimateNumber)", row.approved_by ?? L("the client")),
                isRead: readIDs.contains(notificationID),
                date: NotificationDate.parse(row.approved_at)
            )
        case "changes_requested":
            return AppNotification(
                id: notificationID,
                projectId: row.project_id,
                estimateId: row.estimate_id,
                eventType: row.status,
                title: L("Changes requested"),
                message: row.change_request ?? L("%@ needs changes.", "\(estimateNumber)"),
                isRead: readIDs.contains(notificationID),
                date: NotificationDate.parse(row.change_requested_at)
            )
        default:
            return AppNotification(
                id: notificationID,
                projectId: row.project_id,
                estimateId: row.estimate_id,
                eventType: row.status,
                title: L("Estimate viewed"),
                message: L("%@ was opened by the client.", "\(estimateNumber)"),
                isRead: readIDs.contains(notificationID),
                date: NotificationDate.parse(row.first_viewed_at)
            )
        }
    }

    private func persistReadIDs() {
        UserDefaults.standard.set(Array(readIDs), forKey: "readEstimateActivityIDs")
    }
}

struct NotificationsView: View {
    @State private var store = NotificationStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if store.isLoading && store.notifications.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.notifications.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.notifications) { notification in
                                NotificationRow(notification: notification)
                                    .onTapGesture {
                                        AppHaptics.tap()
                                        store.markRead(notification)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .padding(.bottom, 110)
                    }
                    .refreshable {
                        await store.refresh()
                    }
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .task {
            await store.refresh()
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                HapticButton { dismiss() } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppGray.ink)
                        .frame(width: 44, height: 44)
                        .background(AppGray.pill)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                if store.unreadCount > 0 {
                    HapticButton("Mark all read") { store.markAllRead() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppGray.ink)
                }
            }
            .frame(height: 50)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            HStack {
                Text(L("Notifications"))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppGray.ink)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea(edges: .top))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(AppGray.secondary)
            Text(L("No notifications yet"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppGray.ink)
            Text(L("Client views, approvals, and change requests will appear here."))
                .font(.system(size: 14))
                .foregroundColor(AppGray.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: notification.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(AppGray.ink)
                .frame(width: 42, height: 42)
                .background(AppGray.pill)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notification.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppGray.ink)
                    Spacer()
                    Text(notification.date, style: .relative)
                        .font(.system(size: 12))
                        .foregroundColor(AppGray.secondary)
                }

                Text(notification.message)
                    .font(.system(size: 14))
                    .foregroundColor(AppGray.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !notification.isRead {
                Circle()
                    .fill(AppBrand.accent)
                    .frame(width: 7, height: 7)
                    .padding(.top, 6)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 7, x: 0, y: 2)
    }
}
