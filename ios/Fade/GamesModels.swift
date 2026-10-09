import Foundation

/// One game on the Games tab: the moneyline plus the main spread and total (from the `game_lines()` function).
struct GameLines: Decodable, Identifiable, Hashable {
    let eventId: String
    let eventTitle: String
    let league: String
    let gameStart: Date
    let mlMarket: String
    let mlOutcomes: [String]
    let spMarket: String?
    let spOutcomes: [String]?
    let spLine: Double?
    let toMarket: String?
    let toOutcomes: [String]?
    let toLine: Double?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventTitle = "event_title"
        case league
        case gameStart = "game_start"
        case mlMarket = "ml_market"
        case mlOutcomes = "ml_outcomes"
        case spMarket = "sp_market"
        case spOutcomes = "sp_outcomes"
        case spLine = "sp_line"
        case toMarket = "to_market"
        case toOutcomes = "to_outcomes"
        case toLine = "to_line"
    }

    var id: String { eventId }

    static func == (a: GameLines, b: GameLines) -> Bool { a.eventId == b.eventId }
    func hash(into hasher: inout Hasher) { hasher.combine(eventId) }

    /// The two teams, in the order the moneyline lists them (the first row on the Games list).
    var teams: [String] {
        mlOutcomes.count == 2 ? mlOutcomes : ["Side 1", "Side 2"]
    }

    var moneyline: MarketRef {
        MarketRef(id: mlMarket, marketType: "moneyline", outcomes: mlOutcomes, line: nil,
                  question: eventTitle, eventId: eventId, eventTitle: eventTitle, league: league, gameStart: gameStart)
    }

    var spread: MarketRef? {
        guard let spMarket, let spOutcomes, spOutcomes.count == 2 else { return nil }
        return MarketRef(id: spMarket, marketType: "spreads", outcomes: spOutcomes, line: spLine,
                         question: eventTitle, eventId: eventId, eventTitle: eventTitle, league: league, gameStart: gameStart)
    }

    var total: MarketRef? {
        guard let toMarket, let toOutcomes, toOutcomes.count == 2 else { return nil }
        return MarketRef(id: toMarket, marketType: "totals", outcomes: toOutcomes, line: toLine,
                         question: eventTitle, eventId: eventId, eventTitle: eventTitle, league: league, gameStart: gameStart)
    }
}

/// A market, reduced to what the betting screens need to name its sides ("Rangers -1.5", "Over 5.5") and know when it starts.
struct MarketRef: MarketDescribing, Identifiable, Hashable {
    let id: String
    let marketType: String
    let outcomes: [String]
    let line: Double?
    let question: String
    let eventId: String
    let eventTitle: String
    let league: String
    let gameStart: Date

    /// A short name for one side: "Rangers" on a moneyline, "Rangers -1.5" on a spread, "Over 5.5" on a total.
    func sideName(_ index: Int) -> String {
        guard outcomes.indices.contains(index) else { return "?" }
        return marketType == "moneyline" ? outcomes[index] : sideLabel(index)
    }

    /// "Moneyline", "Spread" or "Over/Under"
    var kindLabel: String {
        switch marketType {
        case "spreads": return "Spread"
        case "totals": return "Over/Under"
        default: return "Moneyline"
        }
    }
}

extension MarketRow {
    var ref: MarketRef {
        MarketRef(id: id, marketType: marketType, outcomes: outcomes, line: line, question: question,
                  eventId: eventId, eventTitle: eventTitle, league: league, gameStart: gameStart)
    }
}

// MARK: - Best prices from a group's open offers

/// The best price a person could get today for each side of one market, and how many offers stand behind each side.
struct MarketBest: Equatable {
    /// Lowest price (in cents) to BACK side 0 / side 1, or nil if no one is offering it.
    var cents: [Int?] = [nil, nil]
    var offers: [Int] = [0, 0]

    var totalOffers: Int { offers[0] + offers[1] }
}

enum OrderBook {
    /// An offer is "live" when shares are left and the game hasn't started.
    static func isLive(_ offer: OfferRow, now: Date = Date()) -> Bool {
        offer.status == "open" && offer.sharesOpen > 0 && offer.gameStart > now
    }

    /// For every market: the cheapest way to back each side. A maker backing side k at price p lets a taker back the OTHER side at 100 − p.
    static func best(from offers: [OfferRow], now: Date = Date()) -> [String: MarketBest] {
        var result: [String: MarketBest] = [:]
        for offer in offers where isLive(offer, now: now) && (0...1).contains(offer.outcome) {
            let side = 1 - offer.outcome
            let price = offer.takerCents
            var entry = result[offer.marketId] ?? MarketBest()
            entry.offers[side] += 1
            if let current = entry.cents[side] { entry.cents[side] = min(current, price) } else { entry.cents[side] = price }
            result[offer.marketId] = entry
        }
        return result
    }

    /// Live offers on one market that let you back `side`, cheapest first (older first when prices tie).
    static func offers(backing side: Int, in offers: [OfferRow], marketID: String, now: Date = Date()) -> [OfferRow] {
        offers
            .filter { $0.marketId == marketID && isLive($0, now: now) && 1 - $0.outcome == side }
            .sorted { a, b in a.takerCents != b.takerCents ? a.takerCents < b.takerCents : a.createdAt < b.createdAt }
    }

    /// How many live offers stand on a whole game (any market).
    static func liveOfferCount(eventID: String, in offers: [OfferRow], now: Date = Date()) -> Int {
        offers.filter { $0.eventId == eventID && isLive($0, now: now) }.count
    }
}

// MARK: - The Games list

/// One tappable price on a game's row: Spread, Total or Win, for one team.
struct BoardCell: Identifiable {
    let market: MarketRef
    let side: Int
    /// "−1.5", "O 5.5", or nil for the win cell
    let line: String?
    /// Best price to back this side, or nil when no one is offering it ("+" is shown instead).
    let cents: Int?

    var id: String { "\(market.id)-\(side)" }
}

struct BoardRow: Identifiable {
    let game: GameLines
    /// cells[team][column]: column 0 = Spread, 1 = Total, 2 = Win. nil when the game has no such market.
    let cells: [[BoardCell?]]
    let openOffers: Int

    var id: String { game.eventId }
}

enum GamesBoard {
    static func rows(lines: [GameLines], offers: [OfferRow], now: Date = Date()) -> [BoardRow] {
        let best = OrderBook.best(from: offers, now: now)
        return lines.map { game in
            let teams = game.teams
            var cells: [[BoardCell?]] = []
            for t in 0..<2 {
                cells.append([
                    spreadCell(game, team: teams[t], row: t, best: best),
                    totalCell(game, row: t, best: best),
                    winCell(game, row: t, best: best),
                ])
            }
            return BoardRow(game: game, cells: cells, openOffers: OrderBook.liveOfferCount(eventID: game.eventId, in: offers, now: now))
        }
    }

    private static func winCell(_ game: GameLines, row: Int, best: [String: MarketBest]) -> BoardCell {
        BoardCell(market: game.moneyline, side: row, line: nil, cents: best[game.mlMarket]?.cents[row] ?? nil)
    }

    private static func spreadCell(_ game: GameLines, team: String, row: Int, best: [String: MarketBest]) -> BoardCell? {
        guard let market = game.spread, let line = market.line else { return nil }
        let side = market.outcomes.firstIndex { $0.caseInsensitiveCompare(team) == .orderedSame } ?? row
        let value = side == 0 ? line : -line
        return BoardCell(market: market, side: side, line: signedLine(value), cents: best[market.id]?.cents[side] ?? nil)
    }

    private static func totalCell(_ game: GameLines, row: Int, best: [String: MarketBest]) -> BoardCell? {
        guard let market = game.total, let line = market.line else { return nil }
        let letter = market.outcomes[row].first.map { String($0).uppercased() } ?? (row == 0 ? "O" : "U")
        return BoardCell(market: market, side: row, line: "\(letter) \(lineText(line))", cents: best[market.id]?.cents[row] ?? nil)
    }

    /// 5.5 → "5.5", 6.0 → "6"
    static func lineText(_ value: Double) -> String {
        let a = abs(value)
        return a.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(a)) : String(a)
    }

    /// -1.5 → "−1.5", 1.5 → "+1.5", 0 → "0"
    static func signedLine(_ value: Double) -> String {
        if value > 0 { return "+" + lineText(value) }
        if value < 0 { return "−" + lineText(value) }
        return "0"
    }

    /// "Total goals" / "Total points" / "Total runs"
    static func totalTitle(league: String) -> String {
        switch league.lowercased() {
        case "nhl": return "Total goals"
        case "mlb": return "Total runs"
        default: return "Total points"
        }
    }
}
