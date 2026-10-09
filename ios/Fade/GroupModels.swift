import Foundation

enum BuybackPolicy: String, Codable, CaseIterable, Identifiable {
    case unlimited
    case weekly
    case vote

    var id: String { rawValue }
    var label: String {
        switch self {
        case .unlimited: return "Unlimited"
        case .weekly: return "Limited per week"
        case .vote: return "By group vote"
        }
    }
}

/// One group, as stored in the `groups` table.
struct GroupInfo: Decodable, Identifiable {
    let id: UUID
    let name: String
    let inviteCode: String
    let startingBalance: Int64
    let buybackPolicy: BuybackPolicy
    let buybacksPerWeek: Int?
    let buybackAmount: Int64

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteCode = "invite_code"
        case startingBalance = "starting_balance"
        case buybackPolicy = "buyback_policy"
        case buybacksPerWeek = "buybacks_per_week"
        case buybackAmount = "buyback_amount"
    }

    /// One short phrase for lists: "Unlimited buybacks", "2 buybacks a week", "Buyback by vote".
    var buybackShort: String {
        switch buybackPolicy {
        case .unlimited: return "Unlimited buybacks"
        case .weekly:
            let n = buybacksPerWeek ?? 1
            return "\(n) buyback\(n == 1 ? "" : "s") a week"
        case .vote: return "Buyback by vote"
        }
    }

    var buybackSummary: String {
        let amount = Coins.format(buybackAmount)
        switch buybackPolicy {
        case .unlimited: return "Unlimited buybacks of \(amount) coins when you're broke"
        case .weekly: return "\(buybacksPerWeek ?? 1) buyback(s) per week of \(amount) coins when you're broke"
        case .vote: return "Buyback of \(amount) coins when the group votes yes"
        }
    }
}

/// My membership in one group (my balance there, plus the group's details).
struct GroupMembership: Decodable, Identifiable {
    let role: String
    let available: Int64
    let escrow: Int64
    let group: GroupInfo

    enum CodingKeys: String, CodingKey {
        case role, available, escrow
        case group = "groups"
    }

    var id: UUID { group.id }
    var balance: Int64 { available + escrow }
}

extension GroupMembership: Hashable {
    static func == (a: GroupMembership, b: GroupMembership) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
