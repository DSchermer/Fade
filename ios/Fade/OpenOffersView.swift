import SwiftUI

/// Everything currently on offer in a group — the quickest way to find a bet to fade.
struct OpenOffersView: View {
    @Environment(Session.self) private var session
    @Environment(OfferStore.self) private var store

    let groupID: UUID

    @State private var offers: [OfferRow] = []
    @State private var loaded = false
    @State private var offerToTake: OfferRow?

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }

    var body: some View {
        List(offers) { offer in
            let mine = offer.makerId == session.profile?.id
            Button {
                if !mine { offerToTake = offer }
            } label: {
                OfferRowView(offer: offer, format: format, isMine: mine, showGame: true)
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if offers.isEmpty && loaded {
                ContentUnavailableView(
                    "No open offers",
                    systemImage: "tray",
                    description: Text(store.errorMessage ?? "Browse games and make an offer to get things going.")
                )
            }
        }
        .navigationTitle("Open offers")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $offerToTake) { offer in
            TakeOfferView(offer: offer) { await reload() }
        }
    }

    private func reload() async {
        offers = await store.openOffers(groupID: groupID)
        loaded = true
    }
}
