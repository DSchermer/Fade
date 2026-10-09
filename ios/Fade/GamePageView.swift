import SwiftUI

/// One game with every market: Win, Spread (main line first, the rest under "More lines"), and Total.
struct GamePageView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(MarketStore.self) private var marketStore
    @Environment(OfferStore.self) private var offerStore
    @Environment(AppRouter.self) private var router

    let game: GameLines

    @State private var loaded: GameMarkets?
    @State private var offers: [OfferRow] = []
    @State private var target: OrderBookTarget?

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var activeGroup: GroupMembership? {
        groups.memberships.first { $0.id == router.gamesGroupID } ?? groups.memberships.first
    }
    private var best: [String: MarketBest] { OrderBook.best(from: offers) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.eventTitle)
                        .font(.fadeSectionTitle)
                        .foregroundStyle(Theme.text)
                    Text("\(game.league.uppercased()) · \(GameTime.label(game.gameStart))")
                        .font(.fadeCaption)
                        .foregroundStyle(Theme.text2)
                }
                .padding(.horizontal, 16)

                GroupPickerButton(groups: groups.memberships, selected: activeGroup) { id in router.gamesGroupID = id }
                    .padding(.horizontal, 16)

                if let loaded, loaded.moneylines.isEmpty && loaded.spreads.isEmpty && loaded.totals.isEmpty {
                    EmptyStateCard(
                        systemImage: "sportscourt",
                        title: "No markets right now",
                        message: marketStore.errorMessage ?? "This game's markets aren't open for betting, or haven't loaded yet. Pull down to try again."
                    )
                    .padding(.horizontal, 16)
                } else if let loaded {
                    MarketCard(title: "Win", markets: loaded.moneylines.map(\.ref), best: best, format: format, initiallyShown: 1) { target = $0 }
                    MarketCard(title: "Spread", markets: orderedLines(loaded.spreads), best: best, format: format, initiallyShown: 1) { target = $0 }
                    MarketCard(title: GamesBoard.totalTitle(league: game.league), markets: orderedLines(loaded.totals), best: best, format: format, initiallyShown: 1) { target = $0 }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }

                Text("Bets close when the game starts. There is no live betting.")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                NoMoneyNotice()
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .padding(.top, 8)
        }
        .refreshable { await reload() }
        .fadeScreen()
        .navigationTitle(game.eventTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(item: $target) { target in
            OrderBookSheet(target: target) { await reloadOffers() }
        }
        .task { await reload() }
        .task(id: activeGroup?.id) { await reloadOffers() }
    }

    /// The line closest to 50/50 first, then the others in line order.
    private func orderedLines(_ rows: [MarketRow]) -> [MarketRef] {
        guard let main = GameMarkets.mainLine(rows) else { return [] }
        return [main.ref] + rows.filter { $0.id != main.id }.map(\.ref)
    }

    private func reload() async {
        loaded = GameMarkets(await marketStore.markets(forGame: game.eventId))
        await reloadOffers()
    }

    private func reloadOffers() async {
        guard let group = activeGroup else { offers = []; return }
        offers = await offerStore.openOffers(groupID: group.id).filter { $0.eventId == game.eventId }
    }
}

/// A card for one kind of market. Shows the first market (the main line) and tucks the rest under "More lines".
struct MarketCard: View {
    let title: String
    let markets: [MarketRef]
    let best: [String: MarketBest]
    let format: PriceFormat
    let initiallyShown: Int
    let onTap: (OrderBookTarget) -> Void

    @State private var expanded = false

    private var shown: [MarketRef] { expanded ? markets : Array(markets.prefix(initiallyShown)) }

    var body: some View {
        if !markets.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.fadeHeadline.weight(.heavy))
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button {
                        if let first = markets.first { onTap(OrderBookTarget(market: first, side: 0)) }
                    } label: {
                        HStack(spacing: 6) {
                            Text("Order book")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(.fadeCaption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(shown) { market in
                    HStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { side in
                            PriceButton(market: market, side: side, best: best[market.id], format: format) {
                                onTap(OrderBookTarget(market: market, side: side))
                            }
                        }
                    }
                }
                if markets.count > initiallyShown {
                    Button {
                        expanded.toggle()
                    } label: {
                        Text(expanded ? "Fewer lines" : "More lines (\(markets.count - initiallyShown))")
                            .font(.fadeBody.weight(.semibold))
                            .foregroundStyle(Theme.text2)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .fadeCard(padding: 14)
            .padding(.horizontal, 16)
        }
    }
}

/// One side of one market: its name, the best price to back it, and how many offers stand behind it.
struct PriceButton: View {
    let market: MarketRef
    let side: Int
    let best: MarketBest?
    let format: PriceFormat
    let action: () -> Void

    var body: some View {
        let cents = best?.cents[side] ?? nil
        let count = best?.offers[side] ?? 0
        Button(action: action) {
            VStack(spacing: 2) {
                Text(market.sideName(side))
                    .font(.fadeCaption.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let cents {
                        Text(Odds.parts(cents: cents, format: format).main)
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                        Text("\(count) offer\(count == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.text2)
                    } else {
                        Text("+")
                            .font(.title3.weight(.heavy))
                            .foregroundStyle(Theme.text3)
                        Text("make offer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.text2)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cents.map { "\(market.sideName(side)), best price \(Odds.parts(cents: $0, format: format).main), \(count) offers" }
            ?? "\(market.sideName(side)), no offers yet. Make one")
    }
}
