import SwiftUI

/// The Bets tab: what you have riding (Pending), your open offers, and how your bets ended (Settled).
struct BetsTabView: View {
    enum Part: String, CaseIterable {
        case pending, offers, settled
    }

    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var offerStore
    @Environment(AppRouter.self) private var router

    @State private var part: Part = .pending
    @State private var groupFilter: UUID?
    @State private var offers: [OfferRow] = []
    @State private var bets: [BetRow] = []
    @State private var loaded = false
    @State private var offerToCancel: OfferRow?
    @State private var actionError: String?

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var me: UUID { session.profile?.id ?? UUID() }

    private var activeFilter: UUID? {
        guard let groupFilter, groups.memberships.contains(where: { $0.id == groupFilter }) else { return nil }
        return groupFilter
    }
    private func inScope(_ id: UUID) -> Bool { activeFilter == nil || activeFilter == id }

    private var pendingBets: [BetRow] { bets.filter { $0.status == "pending" && inScope($0.groupId) } }
    private var settledBets: [BetRow] { bets.filter { $0.status != "pending" && inScope($0.groupId) } }
    private var openOffers: [OfferRow] { offers.filter { $0.status == "open" && inScope($0.groupId) } }
    private var endedOffers: [OfferRow] { offers.filter { $0.status != "open" && $0.sharesCancelled > 0 && inScope($0.groupId) } }

    /// Coins tied up in offers and bets (what the server calls escrow).
    private var inPlay: Int64 {
        groups.memberships.filter { inScope($0.id) }.reduce(0) { $0 + $1.escrow }
    }

    private func groupName(_ id: UUID) -> String {
        groups.memberships.first { $0.id == id }?.group.name ?? "Group"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    UnderlineTabs(
                        items: [
                            UnderlineTabs<Part>.Item(value: .pending, title: "Pending", count: pendingBets.count),
                            UnderlineTabs<Part>.Item(value: .offers, title: "Open offers", count: openOffers.count),
                            UnderlineTabs<Part>.Item(value: .settled, title: "Settled"),
                        ],
                        selection: $part
                    )
                    .padding(.horizontal, 2)
                    if groups.memberships.count > 1 { chips }
                    content
                    NoMoneyNotice()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
            .refreshable { await reload() }
            .fadeScreen()
            .toolbar(.hidden, for: .navigationBar)
            .fadeTabBar()
            .task { await reload() }
            .confirmationDialog(
                "Cancel this offer?",
                isPresented: Binding(get: { offerToCancel != nil }, set: { if !$0 { offerToCancel = nil } }),
                titleVisibility: .visible,
                presenting: offerToCancel
            ) { offer in
                Button("Cancel \(offer.sharesOpen) unfilled shares", role: .destructive) { Task { await cancel(offer) } }
                Button("Keep it", role: .cancel) {}
            } message: { offer in
                Text("\(Coins.formatFixed(Stakes.makerRisk(shares: offer.sharesOpen, cents: offer.priceCents))) coins go back to your available balance. Shares already taken stand.")
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center) {
            Text("Bets")
                .font(.fadeScreenTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("IN PLAY")
                    .font(.fadeLabel)
                    .tracking(0.8)
                    .foregroundStyle(Theme.text2)
                CoinAmount(centicoins: inPlay, font: .title3.weight(.heavy), iconSize: 18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All groups", isSelected: activeFilter == nil) { groupFilter = nil }
                ForEach(groups.memberships) { membership in
                    FilterChip(title: membership.group.name, isSelected: activeFilter == membership.id) {
                        groupFilter = membership.id
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 12) {
            if let actionError { ErrorLine(actionError) }
            switch part {
            case .pending:
                if pendingBets.isEmpty { empty("No bets in play", "Take an offer or make one on the Games tab. Your bets show up here until the result is official.", showGames: true) }
                ForEach(pendingBets) { bet in
                    BetCardView(bet: bet, me: me, format: format, groupName: groupName(bet.groupId))
                }
            case .offers:
                if openOffers.isEmpty { empty("No open offers", "Offers you post wait here until a friend takes them, or until the game starts.", showGames: true) }
                ForEach(openOffers) { offer in
                    OpenOfferCard(offer: offer, format: format, groupName: groupName(offer.groupId)) { offerToCancel = offer }
                }
            case .settled:
                if settledBets.isEmpty && endedOffers.isEmpty { empty("Nothing settled yet", "Finished bets show up here with what you won or lost.", showGames: false) }
                ForEach(settledBets) { bet in
                    BetCardView(bet: bet, me: me, format: format, groupName: groupName(bet.groupId))
                }
                ForEach(endedOffers) { offer in
                    EndedOfferCard(offer: offer, format: format, groupName: groupName(offer.groupId))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func empty(_ title: String, _ message: String, showGames: Bool) -> some View {
        if loaded {
            EmptyStateCard(systemImage: "ticket", title: title, message: message) {
                if showGames {
                    Button("Browse games") { router.tab = .games }
                        .buttonStyle(.fadePrimaryCompact)
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
        }
    }

    // MARK: Loading and actions

    private func reload() async {
        guard let userID = session.profile?.id else { return }
        offers = await offerStore.myOffers(userID: userID)
        bets = await offerStore.myBets(userID: userID)
        await groups.load(userID: userID)          // balances change when bets settle
        loaded = true
    }

    private func cancel(_ offer: OfferRow) async {
        actionError = await offerStore.cancelOffer(offerID: offer.id)
        await reload()
    }
}

// MARK: - Cards

/// A bet you are in: pending (with its stakes) or settled (with what you won or lost).
struct BetCardView: View {
    let bet: BetRow
    let me: UUID
    let format: PriceFormat
    let groupName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(bet.mySide(me)).fontWeight(.bold).foregroundColor(Theme.text)
                        + Text("  " + Odds.parts(cents: bet.myPriceCents(me), format: format).main).fontWeight(.semibold).foregroundColor(Theme.text2))
                        .font(.fadeHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(bet.contextLine())
                        .font(.fadeCaption)
                        .foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 8)
                StatusPill(text: pill.text, tone: pill.tone)
            }
            HStack(spacing: 8) {
                Avatar(name: opponentName, size: 22)
                (Text("You vs ") + Text(opponentName).fontWeight(.semibold).foregroundColor(Theme.text)
                    + Text(" · \(groupName) · \(bet.shares) share\(bet.shares == 1 ? "" : "s")"))
                    .font(.fadeCaption)
                    .foregroundColor(Theme.text2)
                    .lineLimit(2)
            }
            if bet.status == "pending" { pendingBody } else { settledBody }
        }
        .fadeCard()
    }

    private var opponentName: String { String(bet.opponent(me).dropFirst()) }

    private var pill: (text: String, tone: FeedTone) {
        switch bet.status {
        case "void": return ("Void", .neutral)
        case "won_maker", "won_taker": return bet.iWon(me) == true ? ("Won", .win) : ("Lost", .loss)
        default: return ("Pending", .pending)
        }
    }

    @ViewBuilder private var pendingBody: some View {
        if bet.isAwaitingResult() {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.pending)
                Text(bet.statusText(me) + ". Your coins stay set aside until it is confirmed.")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Theme.pending.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).strokeBorder(Theme.pending.opacity(0.25), lineWidth: 1))
        }
        HStack(spacing: 8) {
            StatTile(label: "You put up", coins: bet.myStake(me))
            StatTile(label: "To win", coins: bet.theirStake(me))
        }
        if let starts = bet.startsInText() {
            HStack {
                Text(starts).font(.fadeCaption).foregroundStyle(Theme.text2)
                Spacer()
                ShareLink(item: "I'm backing \(bet.mySide(me)) at \(Odds.parts(cents: bet.myPriceCents(me), format: format).main) on Fade: \(bet.eventTitle).") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.fadeCaption.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .frame(minHeight: 44)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }

    @ViewBuilder private var settledBody: some View {
        if bet.status == "void" {
            Text("Voided. Both stakes were refunded.")
                .font(.fadeBody)
                .foregroundStyle(Theme.text2)
        } else if let won = bet.iWon(me) {
            CoinAmount(
                centicoins: won ? bet.theirStake(me) : -bet.myStake(me),
                signed: true, font: .title.weight(.heavy), iconSize: 24
            )
            .accessibilityLabel(won ? "Won" : "Lost")
        }
    }
}

/// One of your open offers, with a Cancel button for the unfilled shares.
struct OpenOfferCard: View {
    let offer: OfferRow
    let format: PriceFormat
    let groupName: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(offer.backedSide).fontWeight(.bold).foregroundColor(Theme.text)
                        + Text("  " + Odds.parts(cents: offer.priceCents, format: format).main).fontWeight(.semibold).foregroundColor(Theme.text2))
                        .font(.fadeHeadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(offer.eventTitle) · \(GameTime.label(offer.gameStart)) · \(groupName)")
                        .font(.fadeCaption)
                        .foregroundStyle(Theme.text2)
                }
                Spacer(minLength: 8)
                StatusPill(text: "Open", tone: .open)
            }
            HStack(spacing: 8) {
                StatTile(label: "Shares left", value: "\(offer.sharesOpen)", detail: "of \(offer.sharesTotal)")
                StatTile(label: "Set aside", coins: Stakes.makerRisk(shares: offer.sharesOpen, cents: offer.priceCents))
            }
            if offer.sharesTaken > 0 {
                Text("\(offer.sharesTaken) shares already taken. Those bets stand.")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text2)
            }
            Button("Cancel \(offer.sharesOpen) unfilled shares", action: onCancel)
                .buttonStyle(.fadeSecondary)
            Text("Unfilled shares are returned automatically when the game starts.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
        }
        .fadeCard()
    }
}

/// An offer that ended with shares returned (cancelled, or the game started).
struct EndedOfferCard: View {
    let offer: OfferRow
    let format: PriceFormat
    let groupName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(offer.backedSide)  \(Odds.parts(cents: offer.priceCents, format: format).main)")
                    .font(.fadeHeadline)
                    .foregroundStyle(Theme.text)
                Spacer()
                StatusPill(text: "Void", tone: .neutral)
            }
            Text("\(offer.eventTitle) · \(groupName)")
                .font(.fadeCaption)
                .foregroundStyle(Theme.text2)
            Text("\(offer.sharesCancelled) shares returned. \(offer.cancelText).")
                .font(.fadeCaption)
                .foregroundStyle(Theme.text2)
        }
        .fadeCard()
    }
}
