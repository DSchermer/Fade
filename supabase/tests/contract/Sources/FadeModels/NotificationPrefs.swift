import Foundation
struct NotificationPrefs: Decodable {
    var newOffer: Bool
    var offerTaken: Bool
    var betSettled: Bool
    var voteCalled: Bool
    var voteResult: Bool
    enum CodingKeys: String, CodingKey {
        case newOffer = "new_offer"
        case offerTaken = "offer_taken"
        case betSettled = "bet_settled"
        case voteCalled = "vote_called"
        case voteResult = "vote_result"
    }
}
