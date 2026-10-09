import Foundation

/// Everything a feed item might say. The server fills in whichever fields apply to the kind of item.
struct FeedPayload: Decodable {
    var maker: String?
    var taker: String?
    var who: String?
    var winner: String?
    var loser: String?
    var caller: String?
    var subject: String?
    var eventTitle: String?
    var league: String?
    var side: String?
    var makerSide: String?
    var takerSide: String?
    var winnerSide: String?
    var result: String?
    var voteKind: String?
    var status: String?
    var note: String?
    var via: String?
    var priceCents: Int?
    var shares: Int?
    var makerStake: Int64?
    var takerStake: Int64?
    var gain: Int64?
    var amount: Int64?
    var yes: Int?
    var no: Int?

    enum CodingKeys: String, CodingKey {
        case maker, taker, who, winner, loser, caller, subject, league, side, result, status, note, via, shares, gain, amount, yes, no
        case eventTitle = "event_title"
        case makerSide = "maker_side"
        case takerSide = "taker_side"
        case winnerSide = "winner_side"
        case voteKind = "vote_kind"
        case priceCents = "price_cents"
        case makerStake = "maker_stake"
        case takerStake = "taker_stake"
    }
}

/// One entry in a group's feed, from the `feed_listing` view.
struct FeedItem: Decodable, Identifiable {
    let id: UUID
    let groupId: UUID
    let kind: String
    let actorId: UUID?
    let actorUsername: String?
    let payload: FeedPayload
    let createdAt: Date
    let commentCount: Int
    let reactions: [String: Int]
    let myReactions: [String]

    enum CodingKeys: String, CodingKey {
        case id, kind, payload, reactions
        case groupId = "group_id"
        case actorId = "actor_id"
        case actorUsername = "actor_username"
        case createdAt = "created_at"
        case commentCount = "comment_count"
        case myReactions = "my_reactions"
    }

    var icon: String {
        switch kind {
        case "offer_posted": return "megaphone"
        case "offer_taken": return "arrow.left.arrow.right"
        case "bet_settled": return payload.result == "void" ? "arrow.uturn.backward.circle" : "checkmark.seal"
        case "buyback": return "arrow.clockwise.circle"
        default: return "hand.raised"
        }
    }

    /// The sentence shown in the feed. Prices follow the viewer's chosen format.
    func headline(_ format: PriceFormat) -> String {
        let p = payload
        func price(_ cents: Int?) -> String { cents.map { Odds.priceText(cents: $0, format: format) } ?? "" }
        switch kind {
        case "offer_posted":
            return "@\(p.maker ?? "?") is backing \(p.side ?? "a side") at \(price(p.priceCents)) — \(p.shares ?? 0) shares"
        case "offer_taken":
            return "@\(p.taker ?? "?") took \(p.shares ?? 0) shares from @\(p.maker ?? "?"), backing \(p.takerSide ?? "the other side") at \(price(p.priceCents.map { 100 - $0 }))"
        case "bet_settled":
            if p.result == "void" {
                return "Bet between @\(p.maker ?? "?") and @\(p.taker ?? "?") was voided — stakes refunded"
            }
            return "@\(p.winner ?? "?") beat @\(p.loser ?? "?") (\(p.winnerSide ?? "")) and won \(Coins.format(p.gain ?? 0)) coins"
        case "buyback":
            return "@\(p.who ?? "?") bought back in for \(Coins.format(p.amount ?? 0)) coins" + (p.via == "vote" ? " after a group vote" : "")
        case "vote_called":
            return p.voteKind == "reset"
                ? "@\(p.caller ?? "?") called a vote to reset the group"
                : "@\(p.caller ?? "?") asked the group for a buyback"
        case "vote_result":
            let what = p.voteKind == "reset" ? "The reset vote" : "@\(p.subject ?? "?")'s buyback vote"
            return "\(what) \(p.status ?? "ended") (\(p.yes ?? 0) yes · \(p.no ?? 0) no)"
        default:
            return "Activity"
        }
    }

    /// The game or detail line under the headline, if any.
    var subline: String? { payload.eventTitle }
}

struct CommentRow: Decodable, Identifiable {
    let id: UUID
    let feedItemId: UUID
    let groupId: UUID
    let userId: UUID
    let username: String?
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, body
        case feedItemId = "feed_item_id"
        case groupId = "group_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }

    var displayName: String { "@" + (username ?? "deleted user") }
}

struct BlockedUser: Decodable, Identifiable {
    let userId: UUID
    let username: String?
    let kind: String            // "blocked" | "muted"

    enum CodingKeys: String, CodingKey {
        case username, kind
        case userId = "user_id"
    }

    var id: String { "\(kind)-\(userId)" }
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam, harassment, hate, sexual, violence
    case selfHarm = "self_harm"
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment or bullying"
        case .hate: return "Hate speech"
        case .sexual: return "Sexual content"
        case .violence: return "Threats or violence"
        case .selfHarm: return "Self-harm"
        case .other: return "Something else"
        }
    }
}

let reactionEmoji = ["🔥", "😂", "👍", "👎", "😮", "💀", "🎯", "💰"]
