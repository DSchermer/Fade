import Foundation

enum PriceFormat: String, Codable, CaseIterable, Identifiable {
    case cents
    case american

    var id: String { rawValue }
    var label: String { self == .cents ? "Cents (60¢)" : "American (-150)" }
}

/// One row of the `profiles` table (only the columns the app needs).
struct Profile: Codable, Identifiable {
    let id: UUID
    var username: String?
    var priceFormat: PriceFormat
    var lifetimeWins: Int
    var lifetimeLosses: Int
    var deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case priceFormat = "price_format"
        case lifetimeWins = "lifetime_wins"
        case lifetimeLosses = "lifetime_losses"
        case deletedAt = "deleted_at"
    }
}
