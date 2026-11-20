import SwiftUI

/// Type-safe tab identifier for the main application shell.
enum AppTab: Hashable, CaseIterable {
    case home
    case courseMap
    case ranking
    case shop
    case profile

    var titleKey: LocalizedStringKey {
        switch self {
        case .home:      return "tab.home"
        case .courseMap: return "tab.map"
        case .ranking:   return "tab.ranking"
        case .shop:      return "tab.shop"
        case .profile:   return "tab.profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home:      return "house"
        case .courseMap: return "map"
        case .ranking:   return "chart.bar"
        case .shop:      return "bag"
        case .profile:   return "person"
        }
    }

    /// Stable identifier for accessibility and UI testing.
    var accessibilityIdentifier: String {
        switch self {
        case .home:      return "home"
        case .courseMap: return "courseMap"
        case .ranking:   return "ranking"
        case .shop:      return "shop"
        case .profile:   return "profile"
        }
    }
}
