import XCTest
@testable import Fade

final class CoinsTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(Coins.format(10000), "100")
        XCTAssertEqual(Coins.format(3050), "30.5")
        XCTAssertEqual(Coins.format(3025), "30.25")
        XCTAssertEqual(Coins.format(5), "0.05")
        XCTAssertEqual(Coins.format(101), "1.01")
        XCTAssertEqual(Coins.format(0), "0")
        XCTAssertEqual(Coins.format(-150), "-1.5")
        XCTAssertEqual(Coins.format(-5), "-0.05")
        XCTAssertEqual(Coins.format(123_456_700), "1,234,567")
    }

    func testWholeCoins() {
        XCTAssertEqual(Coins.fromWholeCoins(100), 10000)
        XCTAssertEqual(Coins.fromWholeCoins(1), 100)
    }
}

final class CoinsDisplayTests: XCTestCase {
    func testFixedAlwaysTwoDecimals() {
        XCTAssertEqual(Coins.formatFixed(10000), "100.00")
        XCTAssertEqual(Coins.formatFixed(12345), "123.45")
        XCTAssertEqual(Coins.formatFixed(5), "0.05")
        XCTAssertEqual(Coins.formatFixed(0), "0.00")
        XCTAssertEqual(Coins.formatFixed(123_456_700), "1,234,567.00")
    }

    func testSignedUsesARealMinus() {
        XCTAssertEqual(Coins.formatSigned(1250), "+12.50")
        XCTAssertEqual(Coins.formatSigned(-800), "−8.00")
        XCTAssertEqual(Coins.formatSigned(0), "0.00")
    }
}
