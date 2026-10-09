import Foundation
import Observation
import Supabase

/// Loads the games and markets mirrored from Polymarket. Read-only.
@MainActor
@Observable
final class MarketStore {
    static let leagues = ["nfl", "nba", "mlb", "nhl"]

    /// The Games tab: one entry per upcoming game with its main moneyline, spread and total.
    var board: [GameLines] = []
    var games: [Game] = []
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

    /// Upcoming games, one per game, listed from its moneyline market.
    func loadGames(league: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let leagues = league.map { [$0] } ?? Self.leagues
            let rows: [MarketRow] = try await supabase.from("market_listing")
                .select(Self.columns)
                .eq("phase", value: "upcoming")
                .eq("market_type", value: "moneyline")
                .in("league", values: leagues)
                .order("game_start", ascending: true)
                .limit(500)
                .execute()
                .value
            games = rows.map { Game(id: $0.eventId, title: $0.eventTitle, league: $0.league, start: $0.gameStart) }
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
