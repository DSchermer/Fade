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
    let header: () -> Header

    @State private var items: [FeedItem] = []
    @State private var openVotes: [UUID: VoteRow] = [:]
    @State private var loaded = false
    @State private var opened: FeedItem?
    @State private var offerToTake: OfferRow?
    @State private var actionError: String?

    init(groupID: UUID?, @ViewBuilder header: @escaping () -> Header) {
        self.groupID = groupID
        self.header = header
    }

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var myID: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header()
                cards
                if let actionError {
                    ErrorLine(actionError).padding(.horizontal, 16)
                }
                NoMoneyNotice()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .refreshable { await reload() }
        .fadeScreen()
        .navigationDestination(item: $opened) { item in
            FeedItemDetailView(item: item, openVote: openVote(for: item)) { await reload() }
        }
        .sheet(item: $offerToTake) { offer in
            TakeOfferSheet(offer: offer) { await reload() }
        }
        .task(id: groupID) { await reload() }
    }

    @ViewBuilder private var cards: some View {
        if groupID == nil && groups.memberships.isEmpty && !groups.isLoading {
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
            .padding(.horizontal, 16)
        } else if loaded && items.isEmpty {
            EmptyStateCard(
                systemImage: "text.bubble",
                title: "Nothing yet",
                message: store.errorMessage ?? "Offers, bets, results and votes from your groups show up here."
            )
            .padding(.horizontal, 16)
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
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func openVote(for item: FeedItem) -> VoteRow? {
        guard item.refType == "vote", let id = item.refId else { return nil }
        return openVotes[id]
    }

    // MARK: Actions

    private func reload() async {
        items = await store.feed(groupID: groupID)
        let votes = await groups.openVotes()
        openVotes = Dictionary(votes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        loaded = true
    }

    private func react(_ item: FeedItem, _ emoji: String) async {
        actionError = await store.toggleReaction(itemID: item.id, emoji: emoji)
        await reload()
    }

    private func fade(_ item: FeedItem) async {
        guard let offerID = item.refId else { return }
        guard let offer = await offerStore.offer(id: offerID) else {
            actionError = "That offer isn't available any more."
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
