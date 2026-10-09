import SwiftUI

/// The Groups tab: one card per group with your balance, net profit and rank.
struct GroupsTabView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var offerStore
    @Environment(AppRouter.self) private var router

    @State private var openVotes: [VoteRow] = []
    @State private var offers: [OfferRow] = []
    @State private var opened: GroupMembership?
    @State private var openedWithBuyback = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Groups")
                        .font(.fadeScreenTitle)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    HStack(spacing: 10) {
                        Button { router.sheet = .createGroup } label: {
                            Label("Create group", systemImage: "plus")
                        }
                        .buttonStyle(.fadePrimary)
                        Button("Join with a code") { router.sheet = .joinGroup }
                            .buttonStyle(.fadeSecondary)
                    }
                    .padding(.horizontal, 16)

                    if let message = groups.errorMessage { ErrorLine(message).padding(.horizontal, 16) }

                    if groups.memberships.isEmpty && !groups.isLoading {
                        EmptyStateCard(
                            systemImage: "person.2",
                            title: "Start your first group",
                            message: "Groups are where the betting happens. Make one for your friends, or join one with a code."
                        )
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(groups.memberships) { membership in
                                GroupCardView(
                                    membership: membership,
                                    summary: groups.summaries[membership.id],
                                    resetVoteOpen: openVotes.contains { $0.groupId == membership.id && $0.kind == "reset" },
                                    openOffers: offers.filter { $0.groupId == membership.id && OrderBook.isLive($0) }.count,
                                    onOpen: { openedWithBuyback = false; opened = membership },
                                    onBuyback: { openedWithBuyback = true; opened = membership }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }

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
            .navigationDestination(item: $opened) { membership in
                GroupPageView(membership: membership, openBuybackOnAppear: openedWithBuyback)
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        guard let userID = session.profile?.id else { return }
        await groups.load(userID: userID)
        await groups.loadSummaries(userID: userID)
        openVotes = await groups.openVotes()
        offers = await offerStore.openOffers()
    }
}

/// One group on the Groups tab.
struct GroupCardView: View {
    let membership: GroupMembership
    let summary: GroupSummary?
    let resetVoteOpen: Bool
    let openOffers: Int
    let onOpen: () -> Void
    let onBuyback: () -> Void

    private var group: GroupInfo { membership.group }
    private var isBroke: Bool { membership.balance == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Text(AvatarPalette.groupInitials(group.name))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.onAvatar)
                        .frame(width: 48, height: 48)
                        .background(Color(hex: AvatarPalette.hues[0]), in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.fadeCaption)
                            .foregroundStyle(Theme.text2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.text3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(subtitle). Open group")

            HStack(spacing: 8) {
                StatTile(label: "Balance", coins: membership.balance)
                netTile
                StatTile(label: "Rank", value: summary?.myRank.map { "\($0)" } ?? "–", detail: summary.map { "of \($0.memberCount)" })
            }

            if resetVoteOpen || openOffers > 0 {
                HStack(spacing: 8) {
                    if resetVoteOpen { StatusPill(text: "Reset vote open", tone: .pending) }
                    if openOffers > 0 { StatusPill(text: "\(openOffers) open offer\(openOffers == 1 ? "" : "s")", tone: .open) }
                }
            }

            if isBroke { brokeBanner }
        }
        .fadeCard()
    }

    private var subtitle: String {
        let members = summary.map { "\($0.memberCount) member\($0.memberCount == 1 ? "" : "s") · " } ?? ""
        return members + group.buybackShort
    }

    private var netTile: some View {
        let net = summary?.myNet ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text("NET").font(.fadeLabel).tracking(0.8).foregroundStyle(Theme.text2)
            CoinAmount(centicoins: net, signed: true, font: .fadeBody.weight(.bold), iconSize: 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var brokeBanner: some View {
        HStack(spacing: 10) {
            (Text("You're out of coins. ").fontWeight(.bold).foregroundColor(Theme.text)
                + Text(group.buybackPolicy == .vote ? "Ask the group for a buyback." : "Buy back in to keep playing.").foregroundColor(Theme.text2))
                .font(.fadeBody)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(group.buybackPolicy == .vote ? "Ask" : "Buy back", action: onBuyback)
                .font(.fadeBody.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Theme.pending, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(12)
        .background(Theme.pending.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.pending.opacity(0.3), lineWidth: 1))
    }
}
