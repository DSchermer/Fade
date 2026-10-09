import XCTest
@testable import Fade

final class OddsTests: XCTestCase {
    func testCentsToAmerican() {
        let expected: [Int: String] = [
            60: "-150", 40: "+150", 50: "+100", 99: "-9900", 1: "+9900", 55: "-122", 45: "+122",
            33: "+203", 67: "-203", 75: "-300", 25: "+300", 51: "-104", 49: "+104", 90: "-900", 10: "+900", 62: "-163",
        ]
        for (cents, text) in expected {
            XCTAssertEqual(Odds.americanText(cents: cents), text, "\(cents)¢")
        }
    }

    func testAmericanToCents() {
        let expected: [Int: Int] = [
            -150: 60, 150: 40, 100: 50, -100: 50, -110: 52, 110: 48, -200: 67, 200: 33,
            -9900: 99, 9900: 1, -100000: 99, 100000: 1,
        ]
        for (american, cents) in expected {
            XCTAssertEqual(Odds.cents(fromAmerican: american), cents, "\(american)")
        }
        for invalid in [-99, -1, 0, 1, 99] {
            XCTAssertNil(Odds.cents(fromAmerican: invalid), "\(invalid) is not valid American odds")
        }
    }

    func testEveryPriceSurvivesTheRoundTrip() {
        for cents in 1...99 {
            let text = Odds.americanText(cents: cents)
            XCTAssertEqual(Odds.cents(fromAmerican: Int(text)!), cents, "\(cents)¢ via \(text)")
        }
    }

    func testStakesAlwaysFillThePotExactly() {
        for cents in 1...99 {
            for shares in [1, 2, 7, 50, 100, 12345] {
                XCTAssertEqual(
                    Stakes.makerRisk(shares: shares, cents: cents) + Stakes.takerRisk(shares: shares, cents: cents),
                    Stakes.pot(shares: shares)
                )
            }
        }
        // The example from the rules: 50 shares at 60¢ → maker 30 coins, taker 20 coins, pot 50 coins.
        XCTAssertEqual(Stakes.makerRisk(shares: 50, cents: 60), 3000)
        XCTAssertEqual(Stakes.takerRisk(shares: 50, cents: 60), 2000)
        XCTAssertEqual(Stakes.pot(shares: 50), 5000)
    }

    func testPriceText() {
        XCTAssertEqual(Odds.priceText(cents: 60, format: .cents), "60¢")
        XCTAssertEqual(Odds.priceText(cents: 60, format: .american), "-150")
        XCTAssertEqual(Odds.bothText(cents: 40), "40¢ (+150)")
    }
}
