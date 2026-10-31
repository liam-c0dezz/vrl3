//
//  AppGray.swift
//  Construction Estimate
//
//  Central gray palette. Every gray in the app maps to one of these
//  semantic tokens, so a "make X match Y" tweak is a one-line change here.
//

import SwiftUI

enum AppBrand {
    /// Primary brand gradient: dark at the top, light at the bottom.
    static let dark = Color(hex: 0x0B2E5A)
    static let light = Color(hex: 0x347FE5)
    /// Solid blue used throughout the app outside onboarding.
    static let accent = Color(hex: 0x1D5297)

    static let verticalGradient = LinearGradient(
        colors: [dark, light],
        startPoint: .top,
        endPoint: .bottom
    )
}

enum AppGray {
    // MARK: Text (dark → light)

    /// Titles & prices — pure black, max contrast.
    static let title = Color.black

    /// Near-black headings / strong labels.
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.10)

    /// Dark body text (e.g. chat estimate text).
    static let textDark = Color(red: 0.15, green: 0.15, blue: 0.15)

    /// Item names / subtitles — dark gray, NOT black. e.g. "Standard Wax Ring",
    /// "Labor", spreadsheet line names, "What's not included" heading.
    static let itemText = Color(red: 0.30, green: 0.30, blue: 0.33)

    /// Mid gray — units, fine captions (e.g. "each", part numbers).
    static let subtle = Color(red: 0.475, green: 0.475, blue: 0.490)

    /// Subtext — small gray text: "+ Add", "6 items", chevrons, labels.
    static let secondary = Color(UIColor.systemGray)

    /// Faint text — least-emphasis captions.
    static let muted = Color(UIColor.systemGray2)

    // MARK: Strokes / dividers

    /// Hairline strokes & dividers — "+ Add", pills, card borders.
    static let border = Color(UIColor.systemGray4)

    /// Heavier 1.5pt strokes — buttons like "Edit estimate".
    static let borderStrong = Color(UIColor.systemGray3)

    // MARK: Fills / badges

    /// Badge background — nav button circles (settings / bell) and badge fills.
    static let badge = Color(UIColor.systemGray5)

    /// Lighter badge — top-nav button circles + tab pill count badges.
    static let pill = Color(hex: 0xF6F6F7)

    // MARK: Backgrounds

    /// Faint section background.
    static let bgFaint = Color(UIColor.systemGray6)

    /// Light screen / section background.
    static let bgSubtle = Color(red: 0.95, green: 0.95, blue: 0.95)

    /// Very pale background — near white.
    static let bgPale = Color(red: 0.975, green: 0.975, blue: 0.975)

    /// Estimate card dropdown background.
    static let bgDropdown = Color(hex: 0xF6F6F8)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
