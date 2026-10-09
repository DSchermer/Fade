import Foundation

/// How a feed item reads on its card. Pure text logic, so it can be tested without a screen.
extension FeedItem {
    /// "Moneyline", "Spread" or "Over/Under" (nil when the item has no market).
    var marketKindLabel: String? {
        switch marketType {
        case "moneyline": return "Moneyline"
        case "spreads": return "Spread"
        case "totals": return "Over/Under"
        default: return nil
        }
    }

    /// The person the card is about, if there is one (the avatar and the bold name), and what they did.
    var header: (name: String?, verb: String) {
        let p = payload
        let shares = p.shares ?? 0
        let plural = shares == 1 ? "" : "s"
        switch kind {
        case "offer_posted":
            return (p.maker, "posted an offer")
        case "offer_taken":
            return (p.taker, "took \(shares) share\(plural) from \(p.maker ?? "someone")")
        case "bet_settled":
            if p.result == "void" { return (nil, "Bet between \(p.maker ?? "?") and \(p.taker ?? "?") was voided") }
            return (p.winner, "beat \(p.loser ?? "someone")")
        case "buyback":
            return (p.who, p.via == "vote" ? "bought back in after a vote" : "bought back in")
        case "vote_called":
            return (p.caller, p.voteKind == "reset" ? "called a vote to reset the group" : "asked the group for a buyback")
        case "vote_result":
            return (nil, "Vote result")
        default:
            return (actorUsername, "did something")
        }
    }

    /// The big line on the card.
    var title: String {
        let p = payload
        switch kind {
        case "offer_posted": return p.side ?? "An offer"
        case "offer_taken": return p.takerSide ?? "A bet"
        case "bet_settled": return p.result == "void" ? (p.eventTitle ?? "Bet voided") : (p.winnerSide ?? "Bet settled")
        case "buyback": return "Back in with a fresh stack"
        case "vote_called":
            return p.voteKind == "reset" ? "Reset the group?" : "Buyback for @\(p.subject ?? "someone")?"
        case "vote_result":
            let what = p.voteKind == "reset" ? "The reset vote" : "@\(p.subject ?? "someone")'s buyback vote"
            return "\(what) \(p.status ?? "ended")"
        default: return "Activity"
        }
    }

    /// The small gray line under the title: game, kind of bet, league and (for offers) when the game starts.
    func contextLine(now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard ["offer_posted", "offer_taken", "bet_settled"].contains(kind) else { return nil }
        var parts: [String] = []
        if let event = payload.eventTitle { parts.append(event) }
        if let label = marketKindLabel { parts.append(label) }
        if let league = payload.league { parts.append(league.uppercased()) }
        if kind == "offer_posted", let start = gameStart { parts.append(GameTime.label(start, now: now, calendar: calendar)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// An offer someone could still take: open, shares left, and the game hasn't started.
    func canBeFaded(now: Date = Date()) -> Bool {
        guard kind == "offer_posted", offerStatus == "open", (offerSharesOpen ?? 0) > 0 else { return false }
        if let start = gameStart, start <= now { return false }
        return true
    }

    /// The status word on the card's top right, with its tone.
    func statusBadge(now: Date = Date()) -> (text: String, tone: FeedTone)? {
        switch kind {
        case "offer_posted":
            if canBeFaded(now: now) { return ("Open", .open) }
            if offerStatus == "filled" || (offerStatus == "open" && (offerSharesOpen ?? 0) == 0) { return ("Filled", .neutral) }
            return ("Closed", .neutral)
        case "offer_taken":
            switch betStatus {
            case "void": return ("Void", .neutral)
            case "won_maker", "won_taker": return ("Settled", .neutral)
            default: return ("Pending", .pending)
            }
        case "bet_settled":
            return payload.result == "void" ? ("Void", FeedTone.neutral) : ("Won", FeedTone.win)
        case "vote_called": return ("Vote", .pending)
        case "vote_result": return payload.status == "passed" ? ("Passed", FeedTone.win) : ("Failed", FeedTone.loss)
        default: return nil
        }
    }
}

/// The colour family of a status pill; the screen maps it to a real colour.
enum FeedTone: Equatable {
    case open, pending, win, loss, neutral
}
