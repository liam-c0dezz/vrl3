//
//  ContentView.swift
//  Construction Estimate
//
//

import SwiftUI
import Observation
import StoreKit

/// Lets pushed screens (e.g. a project) hide the floating bottom nav.
@Observable final class TabBarVisibility {
    var isHidden = false
}

struct ContentView: View {
    @State private var selectedTabIndex: Int = 0
    @State private var tabBar = TabBarVisibility()
    @State private var showSupport = false
    @Environment(\.requestReview) private var requestReview
    private var retention: RetentionCenter { RetentionCenter.shared }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            LinearGradient(
                colors: [.white, AppGray.bgPale],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Main content based on selected tab
            NavigationStack {
                Group {
                    switch selectedTabIndex {
                    case 0:
                        DashboardHomeView(onOpenProjects: {
                            selectedTabIndex = 1
                        })
                    case 1:
                        HomeView()
                    case 2:
                        ClientsView()
                    default:
                        DashboardHomeView(onOpenProjects: {
                            selectedTabIndex = 1
                        })
                    }
                }
            }
            .environment(tabBar)

            // Bottom Tab Bar (hidden once you're inside a project)
            if !tabBar.isHidden {
                VStack(spacing: 0) {
                    Spacer()

                    if selectedTabIndex == 0 {
                        HStack {
                            Spacer()
                            helpButton
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                    }

                    BottomTabBar(selectedIndex: $selectedTabIndex)
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .onChange(of: AppRouter.shared.pending, initial: true) { _, route in
            // Routes handled on Home need the Home tab; the top bar handles the rest.
            switch route {
            case .home?, .recap?, .newEstimate?:
                selectedTabIndex = 0
                tabBar.isHidden = false
            default:
                break
            }
        }
        .onChange(of: retention.shouldRequestReview) { _, shouldAsk in
            guard shouldAsk else { return }
            retention.shouldRequestReview = false
            requestReview()
        }
        .sheet(isPresented: Binding(
            get: { retention.shouldOfferNotifications },
            set: { if !$0 { retention.shouldOfferNotifications = false } }
        )) {
            NotificationPrePromptSheet()
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color.white)
        }
        .sheet(isPresented: $showSupport) {
            SupportContactSheet()
                .presentationDetents([.height(350)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(Color.white)
        }
    }

    private var helpButton: some View {
        HapticButton { showSupport = true } label: {
            Text(L("Help?"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
                .background(AppBrand.accent)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Help and support"))
    }
}

#Preview {
    ContentView()
        .environment(AuthStore())
}
