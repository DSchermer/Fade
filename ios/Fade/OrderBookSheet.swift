import SwiftUI

/// Everything on offer for one market in your group, best price first. Tap Take to fade someone, or make your own offer.
struct OrderBookSheet: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var offerStore
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let target: OrderBookTarget
    let onChanged: () async -> Void

    @State private var side: Int
    @State private var offers: [OfferRow] = []
    @State private var loaded = false
    @State private var offerToTake: OfferRow?
    @State private var showMake = false

    init(target: OrderBookTarget, onChanged: @escaping () async -> Void) {
        self.target = target
        self.onChanged = onChanged
        _side = State(initialValue: target.side)
    }

    private var market: MarketRef { target.market }
    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var group: GroupMembership? {
        groups.memberships.first { $0.id == router.gamesGroupID } ?? groups.memberships.first
    }
    private var book: [OfferRow] { OrderBook.offers(backing: side, in: offers, marketID: market.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                FadeSegmented(options: [0, 1], title: { "Back \(market.sideName($0))" }, selection: $side)
                summaryRow
                if book.isEmpty {
                    emptyBook
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(book.enumerated()), id: \.element.id) { index, offer in
                            OrderBookRow(
                                offer: offer, format: format, isBest: index == 0,
                                isMine: offer.makerId == session.profile?.id
                            ) { offerToTake = offer }
                        }
                    }
                }
                Button("Make your own offer") { showMake = true }
                    .buttonStyle(.fadeSecondaryLarge)
                    .disabled(group == nil)
                Text("You can take part of any offer. The winner collects the whole pot.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(Theme.card)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .presentationCornerRadius(Theme.Radius.sheet)
        .task(id: group?.id) { await reload() }
        .sheet(item: $offerToTake) { offer in
            TakeOfferSheet(offer: offer) {
                await reload()
                await onChanged()
            }
        }
        .sheet(isPresented: $showMake) {
            if let group {
                MakeOfferSheet(market: market, initialSide: side, groupID: group.id) {
                    await reload()
                    await onChanged()
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(market.eventTitle)
                    .font(.fadeSectionTitle)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(market.kindLabel) · \(market.league.uppercased()) · \(GameTime.label(market.gameStart))")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
    }

    private var summaryRow: some View {
        HStack {
            Menu {
                ForEach(groups.memberships) { membership in
                    Button(membership.group.name) { router.gamesGroupID = membership.id }
                }
            } label: {
                HStack(spacing: 8) {
                    GroupBadge(name: group?.group.name ?? "?", size: 22)
                    Text(group?.group.name ?? "No group")
                        .font(.fadeBody.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.text2)
                }
                .padding(.leading, 8)
                .padding(.trailing, 12)
                .frame(minHeight: 44)
                .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                .contentShape(Capsule())
            }
            .accessibilityLabel("Group: \(group?.group.name ?? "none"). Change group")
            Spacer()
            if let best = book.first {
                Text("\(book.count) open offer\(book.count == 1 ? "" : "s") · best \(Odds.parts(cents: best.takerCents, format: format).main)")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text2)
            }
        }
    }

    private var emptyBook: some View {
        VStack(spacing: 6) {
            Text(loaded ? "No one is offering \(market.sideName(side)) yet" : "Loading offers…")
                .font(.fadeHeadline)
                .foregroundStyle(Theme.text)
            if loaded {
                Text("Be the first: make an offer and your friends can take it.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func reload() async {
        guard let group else { offers = []; loaded = true; return }
        offers = await offerStore.openOffers(groupID: group.id, marketID: market.id)
        loaded = true
    }
}

/// One offer in the order book: who, the price you'd pay, how much is on offer, and a Take button.
struct OrderBookRow: View {
    let offer: OfferRow
    let format: PriceFormat
    let isBest: Bool
    let isMine: Bool
    let onTake: () -> Void

    var body: some View {
        let price = Odds.parts(cents: offer.takerCents, format: format)
        HStack(spacing: 12) {
            Avatar(name: offer.makerUsername ?? "?", size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(price.main)
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text(price.alt)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text2)
                    Text("· " + (offer.makerUsername ?? "deleted user"))
                        .font(.caption)
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                }
                Text("\(offer.sharesOpen) share\(offer.sharesOpen == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                HStack(spacing: 5) {
                    Text("Risk")
                        .font(.caption)
                        .foregroundStyle(Theme.text2)
                    CoinAmount(centicoins: Stakes.takerRisk(shares: offer.sharesOpen, cents: offer.priceCents), font: .caption.weight(.semibold), iconSize: 11)
                    Text("to win")
                        .font(.caption)
                        .foregroundStyle(Theme.text2)
                    CoinAmount(centicoins: Stakes.makerRisk(shares: offer.sharesOpen, cents: offer.priceCents), font: .caption.weight(.semibold), iconSize: 11)
                }
            }
            Spacer(minLength: 4)
            if isMine {
                Text("Yours")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 26)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous))
            } else {
                Button("Take", action: onTake)
                    .buttonStyle(FadeButtonStyle(kind: isBest ? .primary : .quiet, height: 44, fullWidth: false))
                    .accessibilityLabel("Take \(offer.sharesOpen) shares from \(offer.makerName) at \(price.main)")
            }
        }
        .padding(12)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }
}
