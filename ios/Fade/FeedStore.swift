import Foundation
import Observation
import Supabase

/// The group feed, reactions, comments, and the safety tools (report / block / mute).
@MainActor
@Observable
final class FeedStore {
    var errorMessage: String?

    /// The feed of one group, or (with no group) of every group I'm in, newest first.
    func feed(groupID: UUID? = nil) async -> [FeedItem] {
        do {
            var query = supabase.from("feed_listing").select()
            if let groupID { query = query.eq("group_id", value: groupID) }
            let rows: [FeedItem] = try await query
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            errorMessage = nil
            return rows
        } catch {
            errorMessage = "Couldn't load the feed: \(Session.describe(error))"
            return []
        }
    }

    func comments(itemID: UUID) async -> [CommentRow] {
        do {
            let rows: [CommentRow] = try await supabase.from("comment_listing").select()
                .eq("feed_item_id", value: itemID)
                .order("created_at", ascending: true)
                .limit(200)
                .execute()
                .value
            return rows
        } catch {
            errorMessage = "Couldn't load comments: \(Session.describe(error))"
            return []
        }
    }

    private struct ReactionParams: Encodable {
        let item: UUID
        let emoji: String

        enum CodingKeys: String, CodingKey {
            case item = "p_item"
            case emoji = "p_emoji"
        }
    }

    func toggleReaction(itemID: UUID, emoji: String) async -> String? {
        do {
            _ = try await supabase.rpc("toggle_reaction", params: ReactionParams(item: itemID, emoji: emoji)).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    private struct CommentParams: Encodable {
        let item: UUID
        let body: String

        enum CodingKeys: String, CodingKey {
            case item = "p_item"
            case body = "p_body"
        }
    }

    func addComment(itemID: UUID, body: String) async -> String? {
        do {
            _ = try await supabase.rpc("add_comment", params: CommentParams(item: itemID, body: body)).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func deleteComment(id: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("delete_my_comment", params: ["p_comment": id.uuidString]).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    // MARK: Safety

    private struct ReportParams: Encodable {
        let type: String
        let id: UUID
        let reason: String
        let details: String?

        enum CodingKeys: String, CodingKey {
            case type = "p_type"
            case id = "p_id"
            case reason = "p_reason"
            case details = "p_details"
        }
    }

    /// type: "comment", "user" or "feed_item"
    func report(type: String, id: UUID, reason: ReportReason, details: String) async -> String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await supabase.rpc("report_content", params: ReportParams(
                type: type, id: id, reason: reason.rawValue, details: trimmed.isEmpty ? nil : trimmed
            )).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func block(userID: UUID) async -> String? { await userAction("block_user", userID) }
    func unblock(userID: UUID) async -> String? { await userAction("unblock_user", userID) }
    func mute(userID: UUID) async -> String? { await userAction("mute_user", userID) }
    func unmute(userID: UUID) async -> String? { await userAction("unmute_user", userID) }

    private func userAction(_ function: String, _ userID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc(function, params: ["p_user": userID.uuidString]).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func blockedAndMuted() async -> [BlockedUser] {
        let rows: [BlockedUser]? = try? await supabase.rpc("my_blocked_and_muted").execute().value
        return rows ?? []
    }
}
