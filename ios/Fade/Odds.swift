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

    /// The price in the viewer's format first, the other format beside it: 58 → ("58¢", "-138") or ("-138", "58¢").
    static func parts(cents: Int, format: PriceFormat) -> (main: String, alt: String) {
        guard (1...99).contains(cents) else { return ("—", "") }
        let c = "\(cents)¢"
        let a = americanText(cents: cents)
        return format == .cents ? (c, a) : (a, c)
    }

    /// What was typed in the price box → whole cents, or nil if it isn't valid in that format.
    /// American odds that don't land on a whole cent are rounded to the nearest cent (the screen shows the real price).
    static func parseCents(_ text: String, format: PriceFormat) -> Int? {
        guard let n = Int(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        switch format {
        case .cents: return (1...99).contains(n) ? n : nil
        case .american: return cents(fromAmerican: n)
        }
    }

    /// The text to put in the price box for a price: "58" in cents, "-138" in American.
    static func fieldText(cents: Int, format: PriceFormat) -> String {
        guard (1...99).contains(cents) else { return "" }
        return format == .cents ? String(cents) : americanText(cents: cents)
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
