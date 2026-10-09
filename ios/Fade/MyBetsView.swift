import SwiftUI

/// Your open offers (cancel here), your bets with their status, and offers that ended.
struct MyBetsView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var store

    let groupID: UUID

    @State private var offers: [OfferRow] = []
    @State private var bets: [BetRow] = []
    @State private var loaded = false
    @State private var offerToCancel: OfferRow?
    @State private var actionError: String?

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var me: UUID { session.profile?.id ?? UUID() }
    private var openOffers: [OfferRow] { offers.filter { $0.status == "open" } }
    private var endedOffers: [OfferRow] { offers.filter { $0.status != "open" && $0.sharesCancelled > 0 } }

    var body: some View {
        List {
            if let actionError {
                Section { Text(actionError).foregroundStyle(.red) }
            }

            if !openOffers.isEmpty {
                Section {
                    ForEach(openOffers) { offer in
                        VStack(alignment: .leading, spacing: 6) {
                            OfferRowView(offer: offer, format: format, isMine: true, showGame: true)
                            if offer.sharesTaken > 0 {
                                Text("\(offer.sharesTaken) shares already taken — those bets stand.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Button("Cancel \(offer.sharesOpen) unfilled shares", role: .destructive) {
                                offerToCancel = offer
                            }
                            .font(.footnote)
                        }
                    }
                } header: {
                    Text("Your open offers")
                } footer: {
                    Text("Unfilled shares are returned automatically when the game starts.")
                }
            }

            if !bets.isEmpty {
                Section("Your bets") {
                    ForEach(bets) { bet in
                        BetRowView(bet: bet, me: me, format: format)
                    }
                }
            }

            if !endedOffers.isEmpty {
                Section("Cancelled offers") {
                    ForEach(endedOffers) { offer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(offer.backedSide) · \(Odds.priceText(cents: offer.priceCents, format: format))")
                            Text("\(offer.eventTitle) — \(offer.sharesCancelled) shares returned. \(offer.cancelText).")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if loaded && offers.isEmpty && bets.isEmpty {
                ContentUnavailableView(
                    "No bets yet",
                    systemImage: "ticket",
                    description: Text("Make or take an offer on a game and it will show up here.")
                )
            }
        }
        .navigationTitle("My bets")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            "Cancel this offer?",
            isPresented: Binding(get: { offerToCancel != nil }, set: { if !$0 { offerToCancel = nil } }),
            titleVisibility: .visible,
            presenting: offerToCancel
        ) { offer in
            Button("Cancel \(offer.sharesOpen) unfilled shares", role: .destructive) {
                Task { await cancel(offer) }
            }
            Button("Keep it", role: .cancel) {}
        } message: { offer in
            Text("\(Coins.format(Stakes.makerRisk(shares: offer.sharesOpen, cents: offer.priceCents))) coins go back to your available balance. Shares already taken stand.")
        }
    }

    private func reload() async {
        guard let userID = session.profile?.id else { return }
        offers = await store.myOffers(groupID: groupID, userID: userID)
        bets = await store.myBets(groupID: groupID, userID: userID)
        loaded = true
    }

    private func cancel(_ offer: OfferRow) async {
        actionError = await store.cancelOffer(offerID: offer.id)
        if let userID = session.profile?.id { await groups.load(userID: userID) }
        await reload()
    }
}

struct BetRowView: View {
    let bet: BetRow
    let me: UUID
    let format: PriceFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(bet.eventTitle) · \(bet.gameStart.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            Text("You back \(bet.mySide(me))").font(.headline)
            Text("vs \(bet.opponent(me)) · \(bet.shares) shares")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Risk \(Coins.format(bet.myStake(me))) to win \(Coins.format(bet.theirStake(me))) coins")
                .font(.subheadline)
            Text(bet.statusText(me)).font(.footnote).foregroundStyle(.tint)
        }
        .padding(.vertical, 2)
    }
}
