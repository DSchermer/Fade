import Foundation
import Supabase

/// Loads and changes the groups you belong to. All coin changes happen on the server.
@MainActor
@Observable
final class GroupStore {
    var memberships: [GroupMembership] = []
    var isLoading = false
    var errorMessage: String?

    func clear() {
        memberships = []
        errorMessage = nil
    }

    func load(userID: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [GroupMembership] = try await supabase.from("group_members")
                .select("role, available, escrow, groups(id, name, invite_code, starting_balance, buyback_policy, buybacks_per_week, buyback_amount)")
                .eq("user_id", value: userID)
                .eq("status", value: "active")
                .order("joined_at", ascending: false)
                .execute()
                .value
            memberships = rows
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your groups: \(Session.describe(error))"
        }
    }

    func members(of groupID: UUID) async -> [GroupMember] {
        do {
            let rows: [GroupMember] = try await supabase.from("group_members")
                .select("user_id, role, available, escrow, buyback_count, profiles(username)")
                .eq("group_id", value: groupID)
                .eq("status", value: "active")
                .execute()
                .value
            return rows.sorted { $0.balance > $1.balance }
        } catch {
            errorMessage = "Couldn't load members: \(Session.describe(error))"
            return []
        }
    }

    private struct CreateParams: Encodable {
        let name: String
        let startingBalance: Int64
        let policy: String
        let perWeek: Int?
        let buybackAmount: Int64

        enum CodingKeys: String, CodingKey {
            case name = "p_name"
            case startingBalance = "p_starting_balance"
            case policy = "p_buyback_policy"
            case perWeek = "p_buybacks_per_week"
            case buybackAmount = "p_buyback_amount"
        }
    }

    /// Returns an error message to show, or nil on success.
    func createGroup(name: String, startingCoins: Int, policy: BuybackPolicy,
                     perWeek: Int, buybackCoins: Int, userID: UUID) async -> String? {
        let params = CreateParams(
            name: name,
            startingBalance: Coins.fromWholeCoins(startingCoins),
            policy: policy.rawValue,
            perWeek: policy == .weekly ? perWeek : nil,
            buybackAmount: Coins.fromWholeCoins(buybackCoins)
        )
        do {
            _ = try await supabase.rpc("create_group", params: params).execute()
            await load(userID: userID)
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    /// Returns an error message to show, or nil on success.
    func joinGroup(code: String, userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("join_group", params: ["p_code": code]).execute()
            await load(userID: userID)
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    // MARK: Leaderboard, buybacks, score

    func leaderboard(groupID: UUID) async -> [LeaderboardRow] {
        do {
            let rows: [LeaderboardRow] = try await supabase.from("group_leaderboard").select()
                .eq("group_id", value: groupID)
                .execute()
                .value
            return rows
        } catch {
            errorMessage = "Couldn't load the leaderboard: \(Session.describe(error))"
            return []
        }
    }

    func buybackHistory(groupID: UUID) async -> [BuybackRow] {
        do {
            let rows: [BuybackRow] = try await supabase.from("buyback_listing").select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value
            return rows
        } catch {
            errorMessage = "Couldn't load buybacks: \(Session.describe(error))"
            return []
        }
    }

    func buybackStatus(groupID: UUID) async -> BuybackStatus? {
        do {
            let rows: [BuybackStatus] = try await supabase.rpc("buyback_status", params: ["p_group": groupID.uuidString])
                .execute()
                .value
            return rows.first
        } catch {
            errorMessage = "Couldn't check buyback status: \(Session.describe(error))"
            return nil
        }
    }

    /// Returns an error message to show, or nil on success.
    func claimBuyback(groupID: UUID, userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("claim_buyback", params: ["p_group": groupID.uuidString]).execute()
            await load(userID: userID)
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func myScore() async -> MyScore? {
        let rows: [MyScore]? = try? await supabase.from("my_score").select().execute().value
        return rows?.first
    }
}
