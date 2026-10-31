import SwiftUI
import UIKit

/// Feedback belongs to intentional in-app actions, never authentication or typing.
enum AppHaptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }
}

/// Keeps standard Button behavior, including disabled controls and accessibility actions.
/// Existing styles and labels are inherited without adding a competing tap gesture.
struct HapticButton<Label: View>: View {
    private let role: ButtonRole?
    private let action: () -> Void
    private let label: Label

    init(role: ButtonRole? = nil, action: @escaping () -> Void,
         @ViewBuilder label: () -> Label) {
        self.role = role
        self.action = action
        self.label = label()
    }

    init<S: StringProtocol>(_ title: S, role: ButtonRole? = nil,
                            action: @escaping () -> Void) where Label == Text {
        self.init(role: role, action: action) { Text(String(title)) }
    }

    var body: some View {
        Button(role: role) {
            AppHaptics.tap()
            action()
        } label: {
            label
        }
    }
}

struct HapticNavigationLink<Destination: View, Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    private let destination: Destination
    private let label: Label

    init(destination: Destination, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        NavigationLink(destination: destination) { label }
            .simultaneousGesture(TapGesture().onEnded {
                if isEnabled { AppHaptics.tap() }
            })
    }
}
