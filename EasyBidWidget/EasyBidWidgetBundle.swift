//
//  EasyBidWidgetBundle.swift
//  EasyBidWidget
//

import SwiftUI
import WidgetKit

@main
struct EasyBidWidgetBundle: WidgetBundle {
    var body: some Widget {
        WeeklyProgressWidget()
        EstimateGenerationLiveActivity()
    }
}
