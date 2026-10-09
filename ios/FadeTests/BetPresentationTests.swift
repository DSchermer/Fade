import XCTest
@testable import Fade

final class BetPresentationTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let me = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let now = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z")!

    private func bet(maker: String, status: String = "pending", start: String = "2026-10-09T14:14:00Z") throws -> BetRow {
        let other = "44444444-4444-4444-4444-444444444444"
        let makerID = maker == "me" ? me.uuidString : other
        let takerID = maker == "me" ? other : me.uuidString
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","offer_id":"00000000-0000-0000-0000-000000000002",
         "group_id":"22222222-2222-2222-2222-222222222222","market_id":"m","maker_id":"\(makerID)","maker_username":"maya",
         "taker_id":"\(takerID)","taker_username":"theo","maker_outcome":0,"price_cents":58,"shares":25,"maker_stake":1450,
         "taker_stake":1050,"status":"\(status)","created_at":"2026-10-09T10:00:00Z","settled_at":null,"question":"q",
         "outcomes":["Rangers","Capitals"],"market_type":"moneyline","line":null,"game_start":"\(start)",
         "event_title":"Rangers vs Capitals","league":"nhl","phase":"upcoming"}
        """
        return try decoder.decode(BetRow.self, from: Data(json.utf8))
    }

    func testMyPrice() throws {
        XCTAssertEqual(try bet(maker: "me").myPriceCents(me), 58)
        XCTAssertEqual(try bet(maker: "other").myPriceCents(me), 42)
    }

    func testStartsInAndAwaitingResult() throws {
        let upcoming = try bet(maker: "me")
        XCTAssertEqual(upcoming.startsInText(now: now), "Starts in 2h 14m")
        XCTAssertFalse(upcoming.isAwaitingResult(now: now))

        let started = try bet(maker: "me", start: "2026-10-09T11:00:00Z")
        XCTAssertNil(started.startsInText(now: now))
        XCTAssertTrue(started.isAwaitingResult(now: now))

        let won = try bet(maker: "me", status: "won_maker", start: "2026-10-09T11:00:00Z")
        XCTAssertNil(won.startsInText(now: now))
        XCTAssertFalse(won.isAwaitingResult(now: now))
    }

    func testContextLine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let line = try bet(maker: "me", start: "2026-10-09T23:00:00Z").contextLine(now: now, calendar: calendar)
        XCTAssertEqual(line, "Moneyline · NHL · Tonight 11:00 PM")
    }
}

final class GroupSummaryTests: XCTestCase {
    private func row(_ group: String, _ user: String, net: Int64, balance: Int64) -> LeaderboardRow {
        let json = """
        {"group_id":"\(group)","user_id":"\(user)","username":"u","role":"member","available":\(balance),"escrow":0,"balance":\(balance),
         "buyback_count":0,"buyback_coins":0,"net_profit":\(net)}
        """
        return try! JSONDecoder().decode(LeaderboardRow.self, from: Data(json.utf8))
    }

    func testRankAndCounts() {
        let g1 = "11111111-1111-1111-1111-111111111111", g2 = "22222222-2222-2222-2222-222222222222"
        let a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", c = "cccccccc-cccc-cccc-cccc-cccccccccccc"
        let rows = [
            row(g1, a, net: 500, balance: 10500), row(g1, b, net: 2450, balance: 12450), row(g1, c, net: -100, balance: 9900),
            row(g2, a, net: 0, balance: 10000), row(g2, b, net: 0, balance: 10000),
        ]
        let summaries = GroupSummary.build(from: rows, me: UUID(uuidString: a)!)
        XCTAssertEqual(summaries[UUID(uuidString: g1)!], GroupSummary(memberCount: 3, myRank: 2, myNet: 500, myBuybacks: 0))
        XCTAssertEqual(summaries[UUID(uuidString: g2)!]?.memberCount, 2)
        XCTAssertEqual(summaries[UUID(uuidString: g2)!]?.myNet, 0)
    }
}
