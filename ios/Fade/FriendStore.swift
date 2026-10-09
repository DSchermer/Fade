import Foundation
import Supabase

/// Friends: requests by username, suggestions from shared groups, and the friends leaderboard.
@MainActor
@Observable
final class FriendStore {
    var errorMessage: String?

    func scores() async -> [FriendScore] {
        do {
            let rows: [FriendScore] = try await supabase.rpc("friend_scores").execute().value
            errorMessage = nil
            return rows
        } catch {
            errorMessage = "Couldn't load friends: \(Session.describe(error))"
            return []
        }
    }

    func requests() async -> [FriendRequest] {
        let rows: [FriendRequest]? = try? await supabase.rpc("my_friend_requests").execute().value
        return rows ?? []
    }

    func suggestions() async -> [FriendSuggestion] {
        let rows: [FriendSuggestion]? = try? await supabase.rpc("friend_suggestions").execute().value
        return rows ?? []
    }

    /// Returns a message to show: success text, or an error.
    func sendRequest(username: String) async -> (message: String, ok: Bool) {
        do {
            let result: String = try await supabase.rpc("send_friend_request", params: ["p_username": username])
                .execute().value
            return (result == "accepted" ? "You're now friends!" : "Request sent.", true)
        } catch {
            return (Session.describe(error), false)
        }
    }

    private struct RespondParams: Encodable {
        let requester: UUID
        let accept: Bool

        enum CodingKeys: String, CodingKey {
            case requester = "p_requester"
            case accept = "p_accept"
        }
    }

    func respond(to requester: UUID, accept: Bool) async -> String? {
        do {
            _ = try await supabase.rpc("respond_friend_request", params: RespondParams(requester: requester, accept: accept)).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func cancelRequest(to user: UUID) async -> String? { await userAction("cancel_friend_request", user) }
    func removeFriend(_ user: UUID) async -> String? { await userAction("remove_friend", user) }

    private func userAction(_ function: String, _ user: UUID) async -> String? {
        do {
            _ = try await supabase.rpc(function, params: ["p_user": user.uuidString]).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }
}
