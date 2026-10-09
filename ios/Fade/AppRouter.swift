import Foundation
import Observation

/// The five tabs of the floating bar.
enum AppTab: String, CaseIterable, Identifiable {
    case feed, games, bets, groups, me

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feed: return "Feed"
        case .games: return "Games"
        case .bets: return "Bets"
        case .groups: return "Groups"
        case .me: return "Me"
        }
    }

    /// SF Symbol names: the outline, and the filled one used when the tab is selected.
    var symbol: String {
        switch self {
        case .feed: return "house"
        case .games: return "sportscourt"
        case .bets: return "ticket"
        case .groups: return "person.2"
        case .me: return "person"
        }
    }

    var selectedSymbol: String { symbol + ".fill" }
}

/// Sheets that can be opened from anywhere in the app.
enum AppSheet: String, Identifiable {
    case createGroup, joinGroup

    var id: String { rawValue }
}

/// Which tab is showing, and which app-wide sheet is open.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .feed
    var sheet: AppSheet?
    /// The group that offers made from the Games tab go to (nil = your first group).
    var gamesGroupID: UUID?
}
