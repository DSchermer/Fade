import Foundation

/// A group vote (reset or buyback), from the `vote_listing` view.
struct VoteRow: Decodable, Identifiable {
    let id: UUID
    let groupId: UUID
    let kind: String                 // "reset" | "buyback"
    let subjectId: UUID?
    let subjectUsername: String?
    let calledBy: UUID
    let calledByUsername: String?
    let opensAt: Date
    let closesAt: Date
    let status: String               // "open" | "passed" | "failed" | "cancelled"
    let decidedAt: Date?
    let decisionNote: String?
    let yesCount: Int
    let noCount: Int
    let electorate: Int
    let myVote: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, status
        case groupId = "group_id"
        case subjectId = "subject_id"
        case subjectUsername = "subject_username"
        case calledBy = "called_by"
        case calledByUsername = "called_by_username"
        case opensAt = "opens_at"
        case closesAt = "closes_at"
        case decidedAt = "decided_at"
        case decisionNote = "decision_note"
        case yesCount = "yes_count"
        case noCount = "no_count"
        case electorate
        case myVote = "my_vote"
        case createdAt = "created_at"
    }

    var isOpen: Bool { status == "open" }

    var title: String {
        kind == "reset" ? "Reset the group" : "Buyback for @\(subjectUsername ?? "unknown")"
    }

    /// Same rule as the server: min(members, max(2, ceil(25% of members))).
    var quorum: Int { min(electorate, max(2, Int((Double(electorate) * 0.25).rounded(.up)))) }

    var resultText: String {
        switch status {
        case "passed": return "Passed"
        case "failed": return "Failed" + (decisionNote.map { " — \($0)" } ?? "")
        case "cancelled": return "Cancelled" + (decisionNote.map { " — \($0)" } ?? "")
        default: return "Open"
        }
    }
}

/// One member's result in a finished season, from the `season_history` view.
struct SeasonStandingRow: Decodable, Identifiable {
    let seasonId: UUID
    let groupId: UUID
    let number: Int
    let startedAt: Date
    let endedAt: Date?
    let userId: UUID
    let username: String?
    let finalBalance: Int64
    let buybackCount: Int
    let buybackCoins: Int64
    let netProfit: Int64

    enum CodingKeys: String, CodingKey {
        case number, username
        case seasonId = "season_id"
        case groupId = "group_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case userId = "user_id"
        case finalBalance = "final_balance"
        case buybackCount = "buyback_count"
        case buybackCoins = "buyback_coins"
        case netProfit = "net_profit"
    }

    var id: String { "\(seasonId)-\(userId)" }
    var displayName: String { "@" + (username ?? "unknown") }
}
