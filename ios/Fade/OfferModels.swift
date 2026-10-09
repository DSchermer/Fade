import Foundation

/// Anything that describes one Polymarket market, so offers and bets can name the side being backed.
protocol MarketDescribing {
    var marketType: String { get }
    var outcomes: [String] { get }
    var line: Double? { get }
    var question: String { get }
}

extension MarketDescribing {
    /// "Celtics to win", "Cavaliers -1.5", "Over 220.5"
    func sideLabel(_ index: Int) -> String {
        guard outcomes.indices.contains(index) else { return "?" }
        switch marketType {
        case "spreads":
            guard let line else { return outcomes[index] }
            let value = index == 0 ? line : -line
            return "\(outcomes[index]) \(value.formatted(.number.sign(strategy: .always())))"
        case "totals":
            guard let line else { return outcomes[index] }
            return "\(outcomes[index]) \(line.formatted())"
        default:
            return "\(outcomes[index]) to win"
        }
    }
}

extension MarketRow: MarketDescribing {}

/// One offer, from the `offer_listing` view.
struct OfferRow: Decodable, Identifiable, MarketDescribing {
    let id: UUID
    let groupId: UUID
    let makerId: UUID
    let makerUsername: String?
    let marketId: String
    let outcome: Int
    let priceCents: Int
    let sharesTotal: Int
    let sharesOpen: Int
    let sharesCancelled: Int
    let status: String          // "open" | "filled" | "cancelled"
    let cancelReason: String?
    let createdAt: Date
    let question: String
    let outcomes: [String]
    let marketType: String
    let line: Double?
    let gameStart: Date
    let eventTitle: String
    let league: String
    /// Which game this offer belongs to (added to the view's output for the Games tab).
    let eventId: String?

    enum CodingKeys: String, CodingKey {
        case id, status, question, outcomes, line, outcome, league
        case eventId = "event_id"
        case groupId = "group_id"
        case makerId = "maker_id"
        case makerUsername = "maker_username"
        case marketId = "market_id"
        case priceCents = "price_cents"
        case sharesTotal = "shares_total"
        case sharesOpen = "shares_open"
        case sharesCancelled = "shares_cancelled"
        case cancelReason = "cancel_reason"
        case createdAt = "created_at"
        case marketType = "market_type"
        case gameStart = "game_start"
        case eventTitle = "event_title"
    }

    var makerName: String { "@" + (makerUsername ?? "deleted user") }
    var backedSide: String { sideLabel(outcome) }
    var takerSide: String { sideLabel(1 - outcome) }
    var takerCents: Int { 100 - priceCents }
    var sharesTaken: Int { sharesTotal - sharesOpen - sharesCancelled }

    var cancelText: String {
        switch cancelReason {
        case "maker": return "Cancelled by maker"
        case "started": return "Cancelled at game start"
        case "market_closed": return "Cancelled — market closed"
        case "reset": return "Cancelled — group reset"
        default: return "Cancelled"
        }
    }
}

/// One bet (a take of some shares of an offer), from the `bet_listing` view.
struct BetRow: Decodable, Identifiable, MarketDescribing {
    let id: UUID
    let offerId: UUID
    let groupId: UUID
    let marketId: String
    let makerId: UUID
    let makerUsername: String?
    let takerId: UUID
    let takerUsername: String?
    let makerOutcome: Int
    let priceCents: Int
    let shares: Int
    let makerStake: Int64
    let takerStake: Int64
    let status: String          // "pending" | "won_maker" | "won_taker" | "void"
    let createdAt: Date
    let question: String
    let outcomes: [String]
    let marketType: String
    let line: Double?
    let gameStart: Date
    let eventTitle: String
    let league: String
    let phase: String?

    enum CodingKeys: String, CodingKey {
        case id, status, question, outcomes, line, shares, league, phase
        case offerId = "offer_id"
        case groupId = "group_id"
        case marketId = "market_id"
        case makerId = "maker_id"
        case makerUsername = "maker_username"
        case takerId = "taker_id"
        case takerUsername = "taker_username"
        case makerOutcome = "maker_outcome"
        case priceCents = "price_cents"
        case makerStake = "maker_stake"
        case takerStake = "taker_stake"
        case createdAt = "created_at"
        case marketType = "market_type"
        case gameStart = "game_start"
        case eventTitle = "event_title"
    }

    func iAmMaker(_ me: UUID) -> Bool { makerId == me }
    func mySide(_ me: UUID) -> String { sideLabel(iAmMaker(me) ? makerOutcome : 1 - makerOutcome) }
    func myStake(_ me: UUID) -> Int64 { iAmMaker(me) ? makerStake : takerStake }
    func theirStake(_ me: UUID) -> Int64 { iAmMaker(me) ? takerStake : makerStake }
    func opponent(_ me: UUID) -> String { "@" + ((iAmMaker(me) ? takerUsername : makerUsername) ?? "deleted user") }

    /// true = I won, false = I lost, nil = not decided (pending or void).
    func iWon(_ me: UUID) -> Bool? {
        switch status {
        case "won_maker": return iAmMaker(me)
        case "won_taker": return !iAmMaker(me)
        default: return nil
        }
    }

    /// "+30 coins" / "-20 coins" once decided.
    func netText(_ me: UUID) -> String? {
        guard let won = iWon(me) else { return nil }
        return won ? "+\(Coins.format(theirStake(me))) coins" : "-\(Coins.format(myStake(me))) coins"
    }

    func statusText(_ me: UUID) -> String {
        switch status {
        case "won_maker": return iAmMaker(me) ? "Won" : "Lost"
        case "won_taker": return iAmMaker(me) ? "Lost" : "Won"
        case "void": return "Voided — stakes refunded"
        default:
            switch phase {
            case "upcoming": return "Waiting for the game to start"
            case "started": return "Game started — awaiting official result"
            case "proposed": return "Result proposed — official soon"
            case "disputed": return "Result disputed — may take several days"
            case "settled", "void": return "Result is in — settling"
            default: return "Pending"
            }
        }
    }
}
