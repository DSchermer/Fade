import XCTest
@testable import Fade

final class FeedPresentationTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func item(_ json: String) throws -> FeedItem {
        try decoder.decode(FeedItem.self, from: Data(json.utf8))
    }

    private func base(kind: String, payload: String, extra: String = "") -> String {
        """
        {"id":"11111111-1111-1111-1111-111111111111","group_id":"22222222-2222-2222-2222-222222222222","kind":"\(kind)",
         "actor_id":null,"actor_username":null,"payload":\(payload),"created_at":"2026-10-09T12:00:00Z",
         "comment_count":0,"reactions":{},"my_reactions":[]\(extra)}
        """
    }

    func testOpenOfferCanBeFaded() throws {
        let i = try item(base(
            kind: "offer_posted",
            payload: #"{"maker":"maya","side":"Rangers to win","price_cents":58,"shares":40,"event_title":"Rangers vs Capitals","league":"nhl"}"#,
            extra: #","ref_type":"offer","ref_id":"33333333-3333-3333-3333-333333333333","group_name":"College Boys","offer_status":"open","offer_shares_open":40,"market_type":"moneyline","game_start":"2026-10-09T23:00:00Z","bet_status":null,"latest_comment":null"#
        ))
        let now = ISO8601DateFormatter().date(from: "2026-10-09T12:30:00Z")!
        XCTAssertEqual(i.header.name, "maya")
        XCTAssertEqual(i.header.verb, "posted an offer")
        XCTAssertEqual(i.title, "Rangers to win")
        XCTAssertEqual(i.marketKindLabel, "Moneyline")
        XCTAssertTrue(i.canBeFaded(now: now))
        XCTAssertEqual(i.statusBadge(now: now)?.text, "Open")
        XCTAssertEqual(i.statusBadge(now: now)?.tone, .open)
    }

    func testOfferStopsBeingOpenWhenTheGameStartsOrItFills() throws {
        let started = try item(base(
            kind: "offer_posted", payload: #"{"maker":"maya","side":"Over 5.5","price_cents":50,"shares":10}"#,
            extra: #","offer_status":"open","offer_shares_open":10,"game_start":"2026-10-09T23:00:00Z""#
        ))
        let after = ISO8601DateFormatter().date(from: "2026-10-09T23:30:00Z")!
        XCTAssertFalse(started.canBeFaded(now: after))
        XCTAssertEqual(started.statusBadge(now: after)?.text, "Closed")

        let filled = try item(base(
            kind: "offer_posted", payload: #"{"maker":"maya","side":"Over 5.5","price_cents":50,"shares":10}"#,
            extra: #","offer_status":"filled","offer_shares_open":0,"game_start":"2099-01-01T00:00:00Z""#
        ))
        XCTAssertFalse(filled.canBeFaded())
        XCTAssertEqual(filled.statusBadge()?.text, "Filled")
    }

    func testTakenAndSettledCards() throws {
        let taken = try item(base(
            kind: "offer_taken",
            payload: #"{"maker":"maya","taker":"theo","shares":25,"taker_side":"Penguins -1.5","price_cents":58}"#,
            extra: #","bet_status":"pending""#
        ))
        XCTAssertEqual(taken.header.name, "theo")
        XCTAssertEqual(taken.header.verb, "took 25 shares from maya")
        XCTAssertEqual(taken.statusBadge()?.text, "Pending")

        let won = try item(base(
            kind: "bet_settled",
            payload: #"{"result":"decided","winner":"theo","loser":"dre","winner_side":"Penguins -1.5","gain":1250}"#
        ))
        XCTAssertEqual(won.header.verb, "beat dre")
        XCTAssertEqual(won.title, "Penguins -1.5")
        XCTAssertEqual(won.statusBadge()?.text, "Won")

        let void = try item(base(kind: "bet_settled", payload: #"{"result":"void","maker":"maya","taker":"theo"}"#))
        XCTAssertNil(void.header.name)
        XCTAssertEqual(void.statusBadge()?.text, "Void")
    }

    func testOldViewWithoutTheNewColumnsStillDecodes() throws {
        let i = try item(base(kind: "buyback", payload: #"{"who":"sam","amount":10000,"via":"vote"}"#))
        XCTAssertNil(i.groupName)
        XCTAssertEqual(i.header.verb, "bought back in after a vote")
        XCTAssertNil(i.statusBadge())
    }
}
