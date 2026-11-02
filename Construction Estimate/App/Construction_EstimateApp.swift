//
//  Construction_EstimateApp.swift
//  Construction Estimate
//
//

import SwiftUI
import Supabase
import UIKit

@main
struct Construction_EstimateApp: App {
    @State private var authStore: AuthStore

    init() {
        UIScrollView.appearance().keyboardDismissMode = .interactive
        SuperwallService.configure()
        _authStore = State(initialValue: AuthStore())
    }

    var body: some Scene {
        WindowGroup {
            AppLocaleRoot {
                AuthRootView()
            }
            .preferredColorScheme(.light)
            .environment(authStore)
            .swipeDownToDismissKeyboard()
            .onOpenURL { url in
                let allowedHosts = Set(["auth-callback", "reset-password"])
                guard
                    url.scheme?.lowercased() ==
                        SupabaseConfig.authCallbackURL.scheme?.lowercased(),
                    let host = url.host?.lowercased(),
                    allowedHosts.contains(host)
                else { return }
                Task {
                    await authStore.handleIncomingAuthURL(url)
                }
            }
        }
    }
}

/// Re-renders with the active app language's locale so SwiftUI-formatted
/// dates, numbers and pickers follow the EN/ES toggle instantly.
private struct AppLocaleRoot<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.locale, appLocale)
    }
}

private extension View {
    func swipeDownToDismissKeyboard() -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .global)
                .onChanged { value in
                    let verticalTravel = value.translation.height
                    let horizontalTravel = abs(value.translation.width)
                    guard verticalTravel > 28, verticalTravel > horizontalTravel else {
                        return
                    }

                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil,
                        from: nil,
                        for: nil
                    )
                }
        )
    }
}
