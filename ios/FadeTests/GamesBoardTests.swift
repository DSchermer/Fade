import XCTest
@testable import Fade

final class GamesBoardTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-09T12:00:00Z")!
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// A maker backing `outcome` of `market` at `price`.
    private func offer(_ id: Int, market: String = "m-ml", event: String = "e1", outcome: Int, price: Int, open: Int = 10,
                       status: String = "open", start: String = "2026-10-09T23:00:00Z", created: String = "2026-10-09T10:00:00Z",
                       type: String = "moneyline", line: String? = nil) throws -> OfferRow {
        let json = """
        {"id":"00000000-0000-0000-0000-00000000000\(id)","group_id":"22222222-2222-2222-2222-222222222222",
         "maker_id":"33333333-3333-3333-3333-333333333333","maker_username":"maya","market_id":"\(market)","outcome":\(outcome),
         "price_cents":\(price),"shares_total":10,"shares_open":\(open),"shares_cancelled":0,"status":"\(status)","cancel_reason":null,
         "created_at":"\(created)","question":"q","outcomes":["Rangers","Capitals"],"market_type":"\(type)","line":\(line ?? "null"),
         "game_start":"\(start)","event_title":"Rangers vs Capitals","league":"nhl","event_id":"\(event)"}
        """
        return try decoder.decode(OfferRow.self, from: Data(json.utf8))
    }

    private func game() throws -> GameLines {
        let json = """
        {"event_id":"e1","event_title":"Rangers vs Capitals","league":"nhl","game_start":"2026-10-09T23:00:00Z",
         "ml_market":"m-ml","ml_outcomes":["Rangers","Capitals"],
         "sp_market":"m-sp","sp_outcomes":["Capitals","Rangers"],"sp_line":1.5,
         "to_market":"m-to","to_outcomes":["Over","Under"],"to_line":5.5}
        """
        return try decoder.decode(GameLines.self, from: Data(json.utf8))
    }

    func testBestPriceIsTheCheapestWayToBackEachSide() throws {
        // Makers back Rangers (outcome 0) at 58 and 60 → a taker backs Capitals for 42 or 40. Another maker backs Capitals at 55 → taker backs Rangers at 45.
        let offers = [
            try offer(1, outcome: 0, price: 58), try offer(2, outcome: 0, price: 60), try offer(3, outcome: 1, price: 55),
        ]
        let best = OrderBook.best(from: offers, now: now)["m-ml"]
        XCTAssertEqual(best?.cents[1], 40, "cheapest way to back Capitals")
        XCTAssertEqual(best?.cents[0], 45, "only way to back Rangers")
        XCTAssertEqual(best?.offers, [1, 2])
    }

    func testDeadOffersAreIgnored() throws {
        let offers = [
            try offer(1, outcome: 0, price: 58, open: 0),                                  // nothing left
            try offer(2, outcome: 0, price: 59, status: "cancelled"),                      // cancelled
            try offer(3, outcome: 0, price: 60, start: "2026-10-09T11:00:00Z"),            // game already started
        ]
        XCTAssertNil(OrderBook.best(from: offers, now: now)["m-ml"])
        XCTAssertEqual(OrderBook.liveOfferCount(eventID: "e1", in: offers, now: now), 0)
    }

    func testOrderBookIsSortedCheapestFirstThenOldestFirst() throws {
        let offers = [
            try offer(1, outcome: 0, price: 58, created: "2026-10-09T10:05:00Z"),
            try offer(2, outcome: 0, price: 60, created: "2026-10-09T10:09:00Z"),
            try offer(3, outcome: 0, price: 60, created: "2026-10-09T10:01:00Z"),
            try offer(4, outcome: 1, price: 50),
        ]
        let book = OrderBook.offers(backing: 1, in: offers, marketID: "m-ml", now: now)
        XCTAssertEqual(book.map { $0.takerCents }, [40, 40, 42])
        XCTAssertEqual(book.first?.createdAt, ISO8601DateFormatter().date(from: "2026-10-09T10:01:00Z"))
        XCTAssertEqual(OrderBook.offers(backing: 0, in: offers, marketID: "m-ml", now: now).count, 1)
    }

    func testRowCellsLineUpWithTeams() throws {
        let offers = [
            try offer(1, outcome: 0, price: 58),                                                          // win market: back Capitals at 42
            try offer(2, market: "m-sp", outcome: 0, price: 56, type: "spreads", line: "1.5"),            // spread: maker backs Capitals +1.5 → taker backs Rangers −1.5 at 44
            try offer(3, market: "m-to", outcome: 1, price: 53, type: "totals", line: "5.5"),             // total: maker backs Under → taker backs Over at 47
        ]
        let row = try XCTUnwrap(GamesBoard.rows(lines: [try game()], offers: offers, now: now).first)
        XCTAssertEqual(row.openOffers, 3)

        // Row 0 is Rangers. The spread market lists Capitals first (line +1.5), so Rangers is outcome 1 with −1.5.
        let rangersSpread = try XCTUnwrap(row.cells[0][0])
        XCTAssertEqual(rangersSpread.side, 1)
        XCTAssertEqual(rangersSpread.line, "−1.5")
        XCTAssertEqual(rangersSpread.cents, 44)
        let capitalsSpread = try XCTUnwrap(row.cells[1][0])
        XCTAssertEqual(capitalsSpread.side, 0)
        XCTAssertEqual(capitalsSpread.line, "+1.5")
        XCTAssertNil(capitalsSpread.cents, "no one offers Capitals +1.5")

        XCTAssertEqual(row.cells[0][1]?.line, "O 5.5")
        XCTAssertEqual(row.cells[0][1]?.cents, 47)
        XCTAssertEqual(row.cells[1][1]?.line, "U 5.5")
        XCTAssertNil(row.cells[1][1]?.cents)

        XCTAssertNil(row.cells[0][2]?.line)
        XCTAssertNil(row.cells[0][2]?.cents)
        XCTAssertEqual(row.cells[1][2]?.cents, 42)
    }

    func testGamesWithoutSpreadOrTotalStillShowTheWinCells() throws {
        let json = """
        {"event_id":"e2","event_title":"A vs B","league":"nfl","game_start":"2026-10-12T17:00:00Z","ml_market":"x","ml_outcomes":["A","B"],
         "sp_market":null,"sp_outcomes":null,"sp_line":null,"to_market":null,"to_outcomes":null,"to_line":null}
        """
        let game = try decoder.decode(GameLines.self, from: Data(json.utf8))
        let row = try XCTUnwrap(GamesBoard.rows(lines: [game], offers: [], now: now).first)
        XCTAssertNil(row.cells[0][0])
        XCTAssertNil(row.cells[0][1])
        XCTAssertNotNil(row.cells[0][2])
        XCTAssertEqual(row.openOffers, 0)
    }

    func testLineText() {
        XCTAssertEqual(GamesBoard.lineText(5.5), "5.5")
        XCTAssertEqual(GamesBoard.lineText(6), "6")
        XCTAssertEqual(GamesBoard.signedLine(-1.5), "−1.5")
        XCTAssertEqual(GamesBoard.signedLine(2), "+2")
        XCTAssertEqual(GamesBoard.signedLine(0), "0")
        XCTAssertEqual(GamesBoard.totalTitle(league: "nhl"), "Total goals")
        XCTAssertEqual(GamesBoard.totalTitle(league: "nba"), "Total points")
        XCTAssertEqual(GamesBoard.totalTitle(league: "mlb"), "Total runs")
    }
}
