import Foundation

/// A row of the friends leaderboard (you plus your accepted friends).
struct FriendScore: Decodable, Identifiable {
    let userId: UUID
    let username: String?
    let score: Int64
    let wins: Int
    let losses: Int
    let isMe: Bool

    enum CodingKeys: String, CodingKey {
        case username, score, wins, losses
        case userId = "user_id"
        case isMe = "is_me"
    }

    var id: UUID { userId }
    var displayName: String { "@" + (username ?? "deleted user") }
}

struct FriendRequest: Decodable, Identifiable {
    let userId: UUID
    let username: String?
    let direction: String        // "incoming" | "outgoing"
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case username, direction
        case userId = "user_id"
        case createdAt = "created_at"
    }

    var id: String { "\(direction)-\(userId)" }
    var displayName: String { "@" + (username ?? "deleted user") }
}

struct FriendSuggestion: Decodable, Identifiable {
    let userId: UUID
    let username: String?
    let sharedGroups: Int

    enum CodingKeys: String, CodingKey {
        case username
        case userId = "user_id"
        case sharedGroups = "shared_groups"
    }

    var id: UUID { userId }
    var displayName: String { "@" + (username ?? "deleted user") }
}
