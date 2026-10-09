import XCTest
import Foundation
import PostgREST
@testable import FadeModels

/// Decodes the JSON the database really returns (see supabase/tests/contract/run.sh) with the app's own model types and the same
/// decoder the Supabase library uses. A renamed column, a null where the app expects a value, or a changed type fails here
/// instead of on someone's iPhone.
final class ContractTests: XCTestCase {
    let dir: String = (ProcessInfo.processInfo.environment["FADE_CONTRACT_DIR"] ?? "/tmp/fade_contract") + "/"
    let decoder = PostgrestClient.Configuration.jsonDecoder

    func load<T: Decodable>(_ name: String, as: [T].Type = [T].self) throws -> [T] {
        let data = try Data(contentsOf: URL(fileURLWithPath: dir + name + ".json"))
        return try decoder.decode([T].self, from: data)
    }

    func testFeed() throws {
        let rows: [FeedItem] = try load("feed_listing")
        XCTAssertGreaterThan(rows.count, 8)
        print("feed kinds:", Set(rows.map { $0.kind }).sorted())
        for r in rows { _ = r.headline(.cents); _ = r.headline(.american); _ = r.subline }
    }
    func testComments() throws { let r: [CommentRow] = try load("comment_listing"); XCTAssertEqual(r.count, 2); print(r[0]) }
    func testBlocked() throws { let r: [BlockedUser] = try load("my_blocked_and_muted"); XCTAssertEqual(r.count, 1); print(r) }
    func testFriendScores() throws { let r: [FriendScore] = try load("friend_scores"); XCTAssertEqual(r.count, 2); print(r.map { ($0.username, $0.score, $0.wins, $0.losses, $0.isMe) }) }
    func testFriendScoresB() throws { let r: [FriendScore] = try load("friend_scores_b"); XCTAssertEqual(r.count, 2) }
    func testRequests() throws { let r: [FriendRequest] = try load("my_friend_requests"); XCTAssertEqual(r.count, 2); print(r.map { ($0.username, $0.direction) }) }
    func testSuggestions() throws { let r: [FriendSuggestion] = try load("friend_suggestions"); XCTAssertEqual(r.count, 1); print(r) }
    func testGroupMembers() throws { let r: [GroupMembership] = try load("group_members"); XCTAssertEqual(r.count, 3); print(r.map { ($0.group.name, $0.group.buybackPolicy, $0.balance, $0.role) }); for m in r { _ = m.group.buybackSummary } }
    func testLeaderboard() throws { let r: [LeaderboardRow] = try load("group_leaderboard"); XCTAssertGreaterThan(r.count, 4); print(r.prefix(3)) }
    func testBuybackListing() throws { let r: [BuybackRow] = try load("buyback_listing"); XCTAssertGreaterThan(r.count, 1); print(r) }
    func testMyScore() throws { let r: [MyScore] = try load("my_score"); XCTAssertEqual(r.count, 1); print(r) }
    func testVotes() throws { let r: [VoteRow] = try load("vote_listing"); XCTAssertGreaterThan(r.count, 2); print(r.map { ($0.kind, $0.status, $0.yesCount, $0.noCount, $0.myVote as Any, $0.title, $0.resultText) }) }
    func testVotesB() throws { let r: [VoteRow] = try load("vote_listing_b"); XCTAssertGreaterThan(r.count, 2) }
    func testSeasons() throws { let r: [SeasonStandingRow] = try load("season_history"); XCTAssertGreaterThan(r.count, 1); print(r.prefix(2)) }
    func testMarkets() throws { let r: [MarketRow] = try load("market_listing"); XCTAssertGreaterThan(r.count, 5); print(r.prefix(2)) }
    func testOffers() throws { let r: [OfferRow] = try load("offer_listing"); XCTAssertGreaterThan(r.count, 3); print(r.map { ($0.status, $0.sharesOpen) }) }
    func testOffersB() throws { let r: [OfferRow] = try load("offer_listing_b"); XCTAssertGreaterThan(r.count, 3) }
    func testBets() throws { let r: [BetRow] = try load("bet_listing"); XCTAssertGreaterThan(r.count, 3); print(r.map { ($0.status, $0.shares) }) }
    func testBetsB() throws { let r: [BetRow] = try load("bet_listing_b"); XCTAssertGreaterThan(r.count, 3) }
    func testProfile() throws { let r: [Profile] = try load("profiles"); XCTAssertEqual(r.count, 1); print(r[0]) }
    func testBuybackStatus() throws {
        for n in ["buyback_status_g1", "buyback_status_g2", "buyback_status_g3"] { let r: [BuybackStatus] = try load(n); XCTAssertEqual(r.count, 1, n); print(n, r[0]) }
    }
    func testPrefs() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: dir + "my_notification_prefs_obj.json"))
        let p = try decoder.decode(NotificationPrefs.self, from: data); XCTAssertFalse(p.newOffer); XCTAssertTrue(p.offerTaken)
    }
    func testSendFriendRequestString() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: dir + "send_friend_request.json"))
        let s = try decoder.decode(String.self, from: data); XCTAssertEqual(s, "sent")
    }
}
