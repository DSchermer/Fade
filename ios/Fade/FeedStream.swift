import SwiftUI

/// A scrolling list of feed cards for one group, or for every group I'm in (`groupID == nil`).
/// Owns loading, pull-to-refresh, reactions, voting from a card, and opening a post or the "take this offer" sheet.
struct FeedStream<Header: View>: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(FeedStore.self) private var store
    @Environment(OfferStore.self) private var offerStore
    @Environment(AppRouter.self) private var router

    let groupID: UUID?
    /// false when the stream sits inside another scrolling screen (a group's page): no scroll view of its own.
    let scrolls: Bool
    /// Bump this to make the stream reload (the parent's pull-to-refresh does).
    let refreshTick: Int
    let header: () -> Header

    @State private var items: [FeedItem] = []
    @State private var openVotes: [UUID: VoteRow] = [:]
    @State private var loaded = false
    @State private var opened: FeedItem?
    @State private var offerToTake: OfferRow?
    @State private var actionError: String?

    init(groupID: UUID?, scrolls: Bool = true, refreshTick: Int = 0, @ViewBuilder header: @escaping () -> Header) {
        self.groupID = groupID
        self.scrolls = scrolls
        self.refreshTick = refreshTick
        self.header = header
    }

    /// Reload when the group filter changes, the parent asks, or the list of my groups changes (joined / created / left one).
    private struct LoadKey: Equatable {
        let group: UUID?
        let tick: Int
        let groupCount: Int
    }

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var myID: UUID? { session.profile?.id }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { column }
                    .refreshable { await reload() }
                    .fadeScreen()
            } else {
                column
            }
        }
        .navigationDestination(item: $opened) { item in
            FeedItemDetailView(item: items.first { $0.id == item.id } ?? item, openVote: openVote(for: item)) { await reload() }
        }
        .sheet(item: $offerToTake) { offer in
            TakeOfferSheet(offer: offer) { await reload() }
        }
        .task(id: LoadKey(group: groupID, tick: refreshTick, groupCount: groups.memberships.count)) { await reload() }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 12) {
            header()
            cards
            if let actionError {
                ErrorLine(actionError).padding(.horizontal, scrolls ? 16 : 0)
            }
            if scrolls {
                NoMoneyNotice()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder private var cards: some View {
        if groupID == nil && groups.memberships.isEmpty && groups.hasLoaded {
            EmptyStateCard(
                systemImage: "person.2",
                title: "Start your first group",
                message: "Groups are where the betting happens. Make one for your friends, or join one with a code."
            ) {
                HStack(spacing: 8) {
                    Button("Create group") { router.sheet = .createGroup }
                        .buttonStyle(.fadePrimary)
                    Button("Join with a code") { router.sheet = .joinGroup }
                        .buttonStyle(.fadeSecondary)
                }
            }
            .padding(.horizontal, scrolls ? 16 : 0)
        } else if loaded && items.isEmpty {
            EmptyStateCard(
                systemImage: "text.bubble",
                title: "Nothing yet",
                message: store.errorMessage ?? "Offers, bets, results and votes from your groups show up here."
            )
            .padding(.horizontal, scrolls ? 16 : 0)
        } else if !loaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    FeedCardView(
                        item: item,
                        format: format,
                        myID: myID,
                        reactions: item.reactions,
                        myReactions: Set(item.myReactions),
                        openVote: openVote(for: item),
                        onOpen: { opened = item },
                        onReact: { emoji in Task { await react(item, emoji) } },
                        onFade: { Task { await fade(item) } },
                        onVote: { yes in
                            if let vote = openVote(for: item) { Task { await cast(vote, yes: yes) } }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { opened = item }
                    .accessibilityAction(named: "Open post") { opened = item }
                }
            }
            .padding(.horizontal, scrolls ? 16 : 0)
        }
    }

    private func openVote(for item: FeedItem) -> VoteRow? {
        guard item.refType == "vote", let id = item.refId else { return nil }
        return openVotes[id]
    }

    // MARK: Actions

    private func reload() async {
        let fresh = await store.feed(groupID: groupID)
        if Task.isCancelled { return }            // a newer load (other chip, other tab) is already running: don't overwrite it
        let votes = await groups.openVotes()
        if Task.isCancelled { return }
        items = fresh
        openVotes = Dictionary(votes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        loaded = true
    }

    private func react(_ item: FeedItem, _ emoji: String) async {
        actionError = await store.toggleReaction(itemID: item.id, emoji: emoji)
        await reload()
    }

    private func fade(_ item: FeedItem) async {
        guard let offerID = item.refId else { return }
        guard let offer = await offerStore.offer(id: offerID), offer.status == "open", offer.sharesOpen > 0, offer.gameStart > Date() else {
            actionError = "That offer isn't available any more."
            await reload()
            return
        }
        actionError = nil
        offerToTake = offer
    }

    private func cast(_ vote: VoteRow, yes: Bool) async {
        guard let userID = myID else { return }
        actionError = await groups.castVote(voteID: vote.id, yes: yes, userID: userID)
        await reload()
    }
}

/// One group's feed, reached from the group's page.
struct GroupFeedView: View {
    let groupID: UUID

    var body: some View {
        FeedStream(groupID: groupID) { EmptyView() }
            .navigationTitle("Group feed")
            .navigationBarTitleDisplayMode(.inline)
    }
}
