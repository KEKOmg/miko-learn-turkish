import SwiftUI

/// Main application shell with a five-item bottom tab bar.
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: AppTab = .home

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HomeView(isActive: selectedTab == .home) {
                    selectedTab = .courseMap
                }
                    .opacity(selectedTab == .home ? 1 : 0)
                    .allowsHitTesting(selectedTab == .home)
                    .accessibilityHidden(selectedTab != .home)

                CourseMapView()
                    .opacity(selectedTab == .courseMap ? 1 : 0)
                    .allowsHitTesting(selectedTab == .courseMap)
                    .accessibilityHidden(selectedTab != .courseMap)

                RankingView(isActive: selectedTab == .ranking)
                    .opacity(selectedTab == .ranking ? 1 : 0)
                    .allowsHitTesting(selectedTab == .ranking)
                    .accessibilityHidden(selectedTab != .ranking)

                ShopView(isActive: selectedTab == .shop)
                    .opacity(selectedTab == .shop ? 1 : 0)
                    .allowsHitTesting(selectedTab == .shop)
                    .accessibilityHidden(selectedTab != .shop)

                ProfileView(isActive: selectedTab == .profile)
                    .opacity(selectedTab == .profile ? 1 : 0)
                    .allowsHitTesting(selectedTab == .profile)
                    .accessibilityHidden(selectedTab != .profile)
            }
            .allowsHitTesting(appState.activeLessonID == nil)

            TDTabBar(selection: $selectedTab)
                .allowsHitTesting(appState.activeLessonID == nil)
        }
        .background(TDColor.background)
        .lessonFlowLauncher()
    }
}
