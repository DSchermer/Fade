import Foundation
import Observation
import Supabase

/// Loads the games and markets mirrored from Polymarket. Read-only.
@MainActor
@Observable
final class MarketStore {
    /// The Games tab: one entry per upcoming game with its main moneyline, spread and total.
    var board: [GameLines] = []
    var isLoading = false
    var errorMessage: String?

    private static let columns =
        "id, league, market_type, question, outcomes, line, game_start, event_id, event_title, outcome_prices"

    private struct BoardParams: Encodable {
        let league: String?

        enum CodingKeys: String, CodingKey { case league = "p_league" }
    }

    /// Upcoming games for the Games tab (nil league = all four leagues).
    func loadBoard(league: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [GameLines] = try await supabase.rpc("game_lines", params: BoardParams(league: league))
                .execute()
                .value
            board = rows
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load games: \(Session.describe(error))"
        }
    }

    /// Every open market for one game (moneyline, all spread lines, all total lines).
    func markets(forGame eventID: String) async -> [MarketRow] {
        do {
            return try await supabase.from("market_listing")
                .select(Self.columns)
                .eq("event_id", value: eventID)
                .eq("phase", value: "upcoming")
                .limit(500)
                .execute()
                .value
        } catch {
            errorMessage = "Couldn't load markets: \(Session.describe(error))"
            return []
        }
    }
}
