//
//  EstimateLiveActivity.swift
//  Construction Estimate
//
//  Shows AI estimate generation on the Lock Screen and in the Dynamic Island,
//  so people can leave the app while the estimate is built.
//

import ActivityKit
import Foundation

@MainActor
enum EstimateLiveActivity {
    private static var activity: Activity<EstimateGenerationAttributes>?
    private static var lastProgress = -1

    static func start() {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = EstimateGenerationAttributes(language: LanguageStore.shared.current.rawValue)
        let state = EstimateGenerationAttributes.ContentState(progress: 0, isComplete: false)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60)),
            pushType: nil
        )
        lastProgress = 0
    }

    /// Updates at most every 5 percentage points to stay within ActivityKit's budget.
    static func update(progress: Int) {
        guard let activity, progress - lastProgress >= 5 else { return }
        lastProgress = progress
        let state = EstimateGenerationAttributes.ContentState(progress: progress, isComplete: false)
        Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(10 * 60))) }
    }

    static func finish(success: Bool) {
        guard let activity else { return }
        let state = EstimateGenerationAttributes.ContentState(progress: success ? 100 : max(lastProgress, 0), isComplete: success)
        self.activity = nil
        lastProgress = -1
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: success ? .after(Date().addingTimeInterval(15 * 60)) : .immediate
            )
        }
    }
}
