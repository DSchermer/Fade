import Foundation

/// One member of a group's leaderboard, from the `group_leaderboard` view.
struct LeaderboardRow: Decodable, Identifiable {
    let groupId: UUID
    let userId: UUID
    let username: String?
    let role: String
    let available: Int64
    let escrow: Int64
    let balance: Int64
    let buybackCount: Int
    let buybackCoins: Int64
    /// balance − starting balance − buyback coins (buybacks count against you)
    let netProfit: Int64

    enum CodingKeys: String, CodingKey {
        case role, available, escrow, balance, username
        case groupId = "group_id"
        case userId = "user_id"
        case buybackCount = "buyback_count"
        case buybackCoins = "buyback_coins"
        case netProfit = "net_profit"
    }

    var id: UUID { userId }
    var displayName: String { "@" + (username ?? "deleted user") }
}

/// A recorded buyback, visible to the whole group.
struct BuybackRow: Decodable, Identifiable {
    let id: UUID
    let groupId: UUID
    let userId: UUID
    let username: String?
    let amount: Int64
    let via: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, username, amount, via
        case groupId = "group_id"
        case userId = "user_id"
        case createdAt = "created_at"
    }

    var displayName: String { "@" + (username ?? "deleted user") }
}

/// Whether I can buy back into a group right now, and why not if I can't.
struct BuybackStatus: Decodable {
    let busted: Bool
    let policy: String
    let amount: Int64
    let used: Int
    let allowed: Int?
    let nextAvailable: Date?
    let canClaim: Bool
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case busted, policy, amount, used, allowed, reason
        case nextAvailable = "next_available"
        case canClaim = "can_claim"
    }
}

/// My global lifetime score (finished seasons + live profit in every group) and record.
struct MyScore: Decodable {
    let wins: Int
    let losses: Int
    let closedProfit: Int64
    let liveProfit: Int64
    let score: Int64

    enum CodingKeys: String, CodingKey {
        case wins, losses, score
        case closedProfit = "closed_profit"
        case liveProfit = "live_profit"
    }
}

extension Int64 {
    /// "+12.5" / "-3" / "0" — for profits.
    var signedCoins: String {
        self > 0 ? "+" + Coins.format(self) : Coins.format(self)
    }
}
