import Foundation

/// One Polymarket market (a moneyline, one spread line, or one total line) from the `market_listing` view.
struct MarketRow: Decodable, Identifiable {
    let id: String
    let league: String
    let marketType: String      // "moneyline" | "spreads" | "totals"
    let question: String
    let outcomes: [String]
    let line: Double?
    let gameStart: Date
    let eventId: String
    let eventTitle: String
    let outcomePrices: [Double]?

    enum CodingKeys: String, CodingKey {
        case id, league, question, outcomes, line
        case marketType = "market_type"
        case gameStart = "game_start"
        case eventId = "event_id"
        case eventTitle = "event_title"
        case outcomePrices = "outcome_prices"
    }

    /// Short description of what you'd be betting on.
    var title: String {
        switch marketType {
        case "moneyline":
            return outcomes.count == 2 ? "\(outcomes[0]) vs \(outcomes[1])" : question
        case "totals":
            if let line { return "Over / Under \(line.formatted())" }
            return question
        default:
            return question      // e.g. "Spread: Cowboys (-9.5)"
        }
    }

    var subtitle: String? {
        switch marketType {
        case "moneyline": return "Which team wins"
        case "spreads": return outcomes.count == 2 ? "Bet either \(outcomes[0]) or \(outcomes[1])" : nil
        case "totals": return "Total points / runs / goals"
        default: return nil
        }
    }
}

/// The markets of one game, organised for display.
struct GameMarkets {
    let moneylines: [MarketRow]
    let spreads: [MarketRow]
    let totals: [MarketRow]

    init(_ rows: [MarketRow]) {
        moneylines = rows.filter { $0.marketType == "moneyline" }
        spreads = rows.filter { $0.marketType == "spreads" }.sorted(by: Self.lineOrder)
        totals = rows.filter { $0.marketType == "totals" }.sorted(by: Self.lineOrder)
    }

    private static func lineOrder(_ a: MarketRow, _ b: MarketRow) -> Bool {
        if a.outcomes.first != b.outcomes.first { return (a.outcomes.first ?? "") < (b.outcomes.first ?? "") }
        return (a.line ?? 0) < (b.line ?? 0)
    }

    /// Polymarket lists dozens of alternate lines. The "main" one is the line whose market price is
    /// closest to 50/50. (Used only to decide what to show first — never to set odds.)
    static func mainLine(_ rows: [MarketRow]) -> MarketRow? {
        rows.min { distance($0) < distance($1) }
    }

    private static func distance(_ row: MarketRow) -> Double {
        guard let first = row.outcomePrices?.first else { return 1 }
        return abs(first - 0.5)
    }
}
