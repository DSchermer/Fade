import Foundation
import Observation
import Supabase

/// Reads offers and bets, and sends post / take / cancel requests. The SERVER moves all coins.
@MainActor
@Observable
final class OfferStore {
    var errorMessage: String?

    // MARK: Reading

    /// Open offers in a group, optionally for one market. Hides offers whose game has already started.
    func openOffers(groupID: UUID? = nil, marketID: String? = nil) async -> [OfferRow] {
        do {
            var query = supabase.from("offer_listing").select()
                .eq("status", value: "open")
            if let groupID { query = query.eq("group_id", value: groupID) }
            if let marketID { query = query.eq("market_id", value: marketID) }
            let rows: [OfferRow] = try await query
                .order("created_at", ascending: false)
                .limit(300)
                .execute()
                .value
            errorMessage = nil
            return rows.filter { $0.gameStart > Date() && $0.sharesOpen > 0 }
        } catch {
            errorMessage = "Couldn't load offers: \(Session.describe(error))"
            return []
        }
    }

    /// One offer, as it stands right now (nil if it can't be seen).
    func offer(id: UUID) async -> OfferRow? {
        let rows: [OfferRow]? = try? await supabase.from("offer_listing").select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return rows?.first
    }

    /// The signed-in user's own offers in one group, or in every group (newest first).
    func myOffers(groupID: UUID? = nil, userID: UUID) async -> [OfferRow] {
        do {
            var query = supabase.from("offer_listing").select()
                .eq("maker_id", value: userID)
            if let groupID { query = query.eq("group_id", value: groupID) }
            let rows: [OfferRow] = try await query
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            errorMessage = nil
            return rows
        } catch {
            errorMessage = "Couldn't load your offers: \(Session.describe(error))"
            return []
        }
    }

    /// Bets where the user is the maker or the taker, in one group or in every group (newest first).
    func myBets(groupID: UUID? = nil, userID: UUID) async -> [BetRow] {
        do {
            var query = supabase.from("bet_listing").select()
                .or("maker_id.eq.\(userID.uuidString),taker_id.eq.\(userID.uuidString)")
            if let groupID { query = query.eq("group_id", value: groupID) }
            let rows: [BetRow] = try await query
                .order("created_at", ascending: false)
                .limit(200)
                .execute()
                .value
            errorMessage = nil
            return rows
        } catch {
            errorMessage = "Couldn't load your bets: \(Session.describe(error))"
            return []
        }
    }

    // MARK: Acting (each returns an error message to show, or nil on success)

    private struct PostParams: Encodable {
        let group: UUID
        let market: String
        let outcome: Int
        let price: Int
        let shares: Int

        enum CodingKeys: String, CodingKey {
            case group = "p_group"
            case market = "p_market"
            case outcome = "p_outcome"
            case price = "p_price"
            case shares = "p_shares"
        }
    }

    func postOffer(groupID: UUID, marketID: String, outcome: Int, cents: Int, shares: Int) async -> String? {
        do {
            _ = try await supabase.rpc("post_offer", params: PostParams(
                group: groupID, market: marketID, outcome: outcome, price: cents, shares: shares
            )).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    private struct TakeParams: Encodable {
        let offer: UUID
        let shares: Int

        enum CodingKeys: String, CodingKey {
            case offer = "p_offer"
            case shares = "p_shares"
        }
    }

    func takeOffer(offerID: UUID, shares: Int) async -> String? {
        do {
            _ = try await supabase.rpc("take_offer", params: TakeParams(offer: offerID, shares: shares)).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }

    func cancelOffer(offerID: UUID) async -> String? {
        do {
            _ = try await supabase.rpc("cancel_offer", params: ["p_offer": offerID.uuidString]).execute()
            return nil
        } catch {
            return Session.describe(error)
        }
    }
}
