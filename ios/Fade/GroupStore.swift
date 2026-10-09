import Foundation
import Observation
import Supabase

/// Loads and changes the groups you belong to. All coin changes happen on the server.
@MainActor
@Observable
final class GroupStore {
    var memberships: [GroupMembership] = []
    /// Member counts and my standing per group, for the Groups tab.
    var summaries: [UUID: GroupSummary] = [:]
    var isLoading = false
    /// true once the list of groups has loaded successfully at least once (so an empty list really means "no groups").
    var hasLoaded = false
    var errorMessage: String?

    func clear() {
        memberships = []
        summaries = [:]
        hasLoaded = false
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
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your groups: \(Session.describe(error))"
        }
    }

    func loadSummaries(userID: UUID) async {
        let rows: [LeaderboardRow]? = try? await supabase.from("group_leaderboard").select().execute().value
        if let rows { summaries = GroupSummary.build(from: rows, me: userID) }
    }

    func members(of groupID: UUID) async -> [LeaderboardRow] {
        let rows = await leaderboard(groupID: groupID)
        return rows.sorted { $0.balance > $1.balance }
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

    // MARK: Leaving and ownership

    /// Returns an error message to show, or nil on success.
    func leaveGroup(groupID: UUID, userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("leave_group", params: ["p_group": groupID.uuidString]).execute()
            await load(userID: userID)
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    private struct TransferParams: Encodable {
        let group: UUID
        let newOwner: UUID

        enum CodingKeys: String, CodingKey {
            case group = "p_group"
            case newOwner = "p_new_owner"
        }
    }

    func transferOwnership(groupID: UUID, to newOwner: UUID, userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("transfer_ownership",
                                       params: TransferParams(group: groupID, newOwner: newOwner)).execute()
            await load(userID: userID)
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    // MARK: Votes and seasons

    func votes(groupID: UUID) async -> [VoteRow] {
        do {
            let rows: [VoteRow] = try await supabase.from("vote_listing").select()
                .eq("group_id", value: groupID)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            return rows
        } catch {
            errorMessage = "Couldn't load votes: \(Session.describe(error))"
            return []
        }
    }

    /// Every vote that is open right now in any of my groups.
    func openVotes() async -> [VoteRow] {
        let rows: [VoteRow]? = try? await supabase.from("vote_listing").select()
            .eq("status", value: "open")
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value
        return rows ?? []
    }

    private struct CallVoteParams: Encodable {
        let group: UUID
        let kind: String

        enum CodingKeys: String, CodingKey {
            case group = "p_group"
            case kind = "p_kind"
        }
    }

    /// kind: "reset" or "buyback". Returns an error message to show, or nil on success.
    func callVote(groupID: UUID, kind: String, userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("call_vote", params: CallVoteParams(group: groupID, kind: kind)).execute()
            await load(userID: userID)
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    private struct CastParams: Encodable {
        let vote: UUID
        let yes: Bool

        enum CodingKeys: String, CodingKey {
            case vote = "p_vote"
            case yes = "p_yes"
        }
    }

    func castVote(voteID: UUID, yes: Bool, userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("cast_vote", params: CastParams(vote: voteID, yes: yes)).execute()
            await load(userID: userID)          // a passed reset changes everyone's balance
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func seasonHistory(groupID: UUID) async -> [SeasonStandingRow] {
        do {
            let rows: [SeasonStandingRow] = try await supabase.from("season_history").select()
                .eq("group_id", value: groupID)
                .order("number", ascending: false)
                .execute()
                .value
            return rows
        } catch {
            errorMessage = "Couldn't load past seasons: \(Session.describe(error))"
            return []
        }
    }
}
