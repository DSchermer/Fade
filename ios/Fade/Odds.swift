import Foundation

/// Prices are stored as whole cents (1–99) = the chance, in %, of the side the maker backs.
/// American odds exist only for entering and showing prices.
enum Odds {
    /// 60 → "-150", 40 → "+150", 50 → "+100"
    static func americanText(cents p: Int) -> String {
        precondition((1...99).contains(p), "price must be 1–99¢")
        if p == 50 { return "+100" }
        if p > 50 {
            return "-" + String(Int((Double(100 * p) / Double(100 - p)).rounded()))
        }
        return "+" + String(Int((Double(100 * (100 - p)) / Double(p)).rounded()))
    }

    /// -150 → 60, +150 → 40. Returns nil if the number isn't valid American odds (between -99 and +99).
    /// Rounds to the nearest cent, so show the user the result before they confirm.
    static func cents(fromAmerican a: Int) -> Int? {
        guard abs(a) >= 100 else { return nil }
        let p = a < 0
            ? 100.0 * Double(-a) / Double(-a + 100)
            : 10000.0 / Double(a + 100)
        return min(99, max(1, Int(p.rounded())))
    }

    static func priceText(cents: Int, format: PriceFormat) -> String {
        format == .cents ? "\(cents)¢" : americanText(cents: cents)
    }

    /// "60¢ (-150)" — both, for confirmation screens.
    static func bothText(cents: Int) -> String {
        "\(cents)¢ (\(americanText(cents: cents)))"
    }
}

/// The exact money of a bet, in hundredths of a coin. Each share is a 1-coin pot (100).
enum Stakes {
    static func makerRisk(shares: Int, cents: Int) -> Int64 { Int64(shares) * Int64(cents) }
    static func takerRisk(shares: Int, cents: Int) -> Int64 { Int64(shares) * Int64(100 - cents) }
    static func pot(shares: Int) -> Int64 { Int64(shares) * 100 }
}
