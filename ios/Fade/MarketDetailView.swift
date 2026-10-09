import SwiftUI

/// One market (e.g. "Cavaliers -1.5"): the open offers on it in this group, and a button to make your own.
struct MarketDetailView: View {
    @Environment(Session.self) private var session
    @Environment(OfferStore.self) private var store

    let groupID: UUID
    let market: MarketRow

    @State private var offers: [OfferRow] = []
    @State private var showMake = false
    @State private var offerToTake: OfferRow?

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }

    var body: some View {
        List {
            Section {
                Text(market.title).font(.headline)
                Text(market.gameStart.formatted(date: .complete, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                if offers.isEmpty {
                    Text("No open offers on this market yet. Make the first one!")
                        .foregroundStyle(.secondary)
                }
                ForEach(offers) { offer in
                    let mine = offer.makerId == session.profile?.id
                    Button {
                        if !mine { offerToTake = offer }
                    } label: {
                        OfferRowView(offer: offer, format: format, isMine: mine)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Open offers in this group")
            } footer: {
                Text("Tap someone else's offer to take part or all of it. Your own offers are managed under My bets.")
            }

            Section {
                Button { showMake = true } label: {
                    Label("Make an offer", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Bets close when the game starts — there is no live betting.")
            }
        }
        .navigationTitle(market.sideLabel(0))
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showMake) {
            MakeOfferView(groupID: groupID, market: market) { await reload() }
        }
        .sheet(item: $offerToTake) { offer in
            TakeOfferView(offer: offer) { await reload() }
        }
    }

    private func reload() async {
        offers = await store.openOffers(groupID: groupID, marketID: market.id)
    }
}
