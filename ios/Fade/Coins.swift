import Foundation

/// Coins are stored as whole numbers of hundredths of a coin ("centicoins"): 100 = 1 coin.
enum Coins {
    /// 10000 → "100", 3050 → "30.5", 3025 → "30.25", -150 → "-1.5", 123456700 → "1,234,567"
    static func format(_ centicoins: Int64) -> String {
        let sign = centicoins < 0 ? "-" : ""
        let magnitude = centicoins.magnitude
        let whole = Int64(magnitude / 100)
        let fraction = Int(magnitude % 100)
        let wholeText = whole.formatted()
        if fraction == 0 { return sign + wholeText }
        if fraction % 10 == 0 { return sign + wholeText + "." + String(fraction / 10) }
        return sign + wholeText + "." + (fraction < 10 ? "0" : "") + String(fraction)
    }

    static func fromWholeCoins(_ coins: Int) -> Int64 { Int64(coins) * 100 }
}
