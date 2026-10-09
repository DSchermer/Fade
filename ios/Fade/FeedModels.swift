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

/// The newest visible comment on a feed item, shown as a preview on its card.
struct LatestComment: Decodable {
    let username: String?
    let body: String
}

/// One entry in a group's feed, from the `feed_listing` view.
/// The fields after `myReactions` were added in migration 0015; they are optional so the app still works before it is applied.
struct FeedItem: Decodable, Identifiable, Hashable {
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
    let refType: String?
    let refId: UUID?
    let groupName: String?
    let offerStatus: String?
    let offerSharesOpen: Int?
    let marketType: String?
    let gameStart: Date?
    let betStatus: String?
    let latestComment: LatestComment?

    enum CodingKeys: String, CodingKey {
        case id, kind, payload, reactions
        case groupId = "group_id"
        case actorId = "actor_id"
        case actorUsername = "actor_username"
        case createdAt = "created_at"
        case commentCount = "comment_count"
        case myReactions = "my_reactions"
        case refType = "ref_type"
        case refId = "ref_id"
        case groupName = "group_name"
        case offerStatus = "offer_status"
        case offerSharesOpen = "offer_shares_open"
        case marketType = "market_type"
        case gameStart = "game_start"
        case betStatus = "bet_status"
        case latestComment = "latest_comment"
    }

    static func == (a: FeedItem, b: FeedItem) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
