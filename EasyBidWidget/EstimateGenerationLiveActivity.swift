//
//  EstimateGenerationLiveActivity.swift
//  EasyBidWidget
//
//  Lock Screen and Dynamic Island while an AI estimate is generated.
//

import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct EstimateGenerationLiveActivity: Widget {
    private static let accent = Color(red: 0.204, green: 0.498, blue: 0.898)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EstimateGenerationAttributes.self) { context in
            HStack(spacing: 14) {
                ring(context.state, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(context))
                        .font(.headline)
                    Text(context.state.isComplete ? SharedText.openToReview.text(context.attributes.language) : "\(context.state.progress)%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .activityBackgroundTint(Color(.systemBackground))
            .widgetURL(RetentionShared.deepLink("home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ring(context.state, size: 40)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(context))
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: Double(context.state.progress), total: 100)
                        .tint(Self.accent)
                }
            } compactLeading: {
                Image(systemName: context.state.isComplete ? "checkmark.circle.fill" : "doc.text.fill")
                    .foregroundStyle(Self.accent)
            } compactTrailing: {
                Text("\(context.state.progress)%")
                    .monospacedDigit()
            } minimal: {
                ring(context.state, size: 22)
            }
            .widgetURL(RetentionShared.deepLink("home"))
        }
    }

    private func title(_ context: ActivityViewContext<EstimateGenerationAttributes>) -> String {
        context.state.isComplete
            ? SharedText.estimateReady.text(context.attributes.language)
            : SharedText.creatingEstimate.text(context.attributes.language)
    }

    private func ring(_ state: EstimateGenerationAttributes.ContentState, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Self.accent.opacity(0.2), lineWidth: size / 9)
            Circle()
                .trim(from: 0, to: CGFloat(state.progress) / 100)
                .stroke(Self.accent, style: StrokeStyle(lineWidth: size / 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if state.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(Self.accent)
            }
        }
        .frame(width: size, height: size)
    }
}
