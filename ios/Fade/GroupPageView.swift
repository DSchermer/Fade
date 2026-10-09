import SwiftUI

/// One group: your numbers, a leaderboard, the group's feed, votes and members.
struct GroupPageView: View {
    enum Part: String, CaseIterable {
        case leaderboard, feed, votes, members

        var title: String {
            switch self {
            case .leaderboard: return "Leaderboard"
            case .feed: return "Feed"
            case .votes: return "Votes"
            case .members: return "Members"
            }
        }
    }

    enum Sheet: Identifiable {
        case invite
        case buyback
        case leave
        case leaveBlocked([BetRow])
        case handOver(LeaderboardRow)

        var id: String {
            switch self {
            case .invite: return "invite"
            case .buyback: return "buyback"
            case .leave: return "leave"
            case .leaveBlocked: return "leaveBlocked"
            case .handOver(let member): return "handOver-\(member.userId)"
            }
        }
    }

    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var offerStore
    @Environment(FeedStore.self) private var feedStore
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    let membership: GroupMembership          // as it was when this screen opened
    var openBuybackOnAppear = false

    @State private var part: Part = .leaderboard
    @State private var mode: LeaderboardMode = .profit
    @State private var members: [LeaderboardRow] = []
    @State private var openVotes: [VoteRow] = []
    @State private var buyback: BuybackStatus?
    @State private var sheet: Sheet?
    @State private var refreshTick = 0
    @State private var actionError: String?
    @State private var reportTarget: ReportTarget?
    @State private var memberToBlock: LeaderboardRow?
    @State private var didAutoOpen = false
    @State private var openOfferCount = 0

    private var group: GroupInfo { membership.group }
    /// Always the latest balance (it changes whenever you post, take or cancel).
    private var live: GroupMembership { groups.memberships.first { $0.id == membership.id } ?? membership }
    private var me: UUID? { session.profile?.id }
    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var myNet: Int64 { members.first { $0.userId == me }?.netProfit ?? 0 }
    private var isOwner: Bool { live.role == "owner" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                numbers
                if let reset = openVotes.first(where: { $0.kind == "reset" }) { resetBanner(reset) }
                if live.balance == 0, let buyback, buyback.busted { BuybackCard(status: buyback, busy: false, onClaim: { sheet = .buyback }, onAsk: { Task { await askForVote() } }) }
                UnderlineTabs(
                    items: Part.allCases.map { UnderlineTabs<Part>.Item(value: $0, title: $0.title, count: $0 == .votes ? openVotes.count : nil) },
                    selection: $part
                )
                .padding(.horizontal, 2)
                sectionContent
                    .padding(.horizontal, 16)
                if let actionError { ErrorLine(actionError).padding(.horizontal, 16) }
                NoMoneyNotice()
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
            .padding(.top, 4)
        }
        .refreshable { await reload(); refreshTick += 1 }
        .fadeScreen()
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .invite } label: { Label("Invite", systemImage: "person.badge.plus") }
            }
        }
        .task { await reload() }
        .task(id: live.balance) { buyback = await groups.buybackStatus(groupID: group.id) }
        .onChange(of: buyback?.canClaim) { _, _ in
            if openBuybackOnAppear, !didAutoOpen, buyback?.canClaim == true {
                didAutoOpen = true
                sheet = .buyback
            }
        }
        .sheet(item: $sheet) { sheet in sheetView(sheet) }
        .sheet(item: $reportTarget) { target in ReportView(target: target) }
        .confirmationDialog("Block \(memberToBlock?.displayName ?? "this person")?", isPresented: Binding(
            get: { memberToBlock != nil }, set: { if !$0 { memberToBlock = nil } }
        ), titleVisibility: .visible, presenting: memberToBlock) { member in
            Button("Block", role: .destructive) { Task { actionError = await feedStoreBlock(member) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's comments or feed activity, and you can't be friends. Bets in this group still work normally. To avoid someone's offers entirely, leave the group.")
        }
    }

    // MARK: Top of the page

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatTile(label: "Balance", coins: live.balance)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NET").font(.fadeLabel).tracking(0.8).foregroundStyle(Theme.text2)
                    CoinAmount(centicoins: myNet, signed: true, font: .fadeBody.weight(.bold), iconSize: 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .accessibilityElement(children: .combine)
                StatTile(label: "In play", coins: live.escrow)
            }
            Text("\(members.count > 0 ? "\(members.count) member\(members.count == 1 ? "" : "s") · " : "")\(group.buybackShort)")
                .font(.fadeCaption)
                .foregroundStyle(Theme.text2)
        }
        .padding(.horizontal, 16)
    }

    private func resetBanner(_ vote: VoteRow) -> some View {
        Button { part = .votes } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.pending)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset vote in progress").font(.fadeBody.weight(.bold)).foregroundStyle(Theme.text)
                    Text("If it passes, all unsettled bets are voided and refunded. \(vote.yesCount) yes · \(vote.noCount) no of \(vote.electorate).")
                        .font(.fadeCaption)
                        .foregroundStyle(Theme.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text3)
            }
            .padding(14)
            .background(Theme.pending.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.pending.opacity(0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: Sections

    @ViewBuilder private var sectionContent: some View {
        switch part {
        case .leaderboard:
            VStack(alignment: .leading, spacing: 12) {
                FadeSegmented(options: LeaderboardMode.allCases, title: { $0.title }, selection: $mode)
                LeaderboardList(rows: members, mode: mode, me: me)
                Text(mode == .profit
                     ? "Net profit = balance − starting balance − buyback coins. Buybacks never count as winnings."
                     : "Everything each member holds right now, including coins tied up in bets.")
                    .font(.caption)
                    .foregroundStyle(Theme.text3)
            }
        case .feed:
            FeedStream(groupID: group.id, scrolls: false, refreshTick: refreshTick) { EmptyView() }
        case .votes:
            VotesContent(group: group, refreshTick: refreshTick) { Task { await reloadVotes() } }
        case .members:
            membersSection
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isOwner && members.count > 1 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "crown").foregroundStyle(Theme.pending)
                    (Text("You own this group. ").fontWeight(.bold).foregroundColor(Theme.text)
                        + Text("Make another member the owner before you can leave.").foregroundColor(Theme.text2))
                        .font(.fadeBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Theme.pending.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.pending.opacity(0.35), lineWidth: 1))
            }

            SectionLabel("Members · \(members.count)")
            VStack(spacing: 0) {
                ForEach(Array(members.sorted { $0.balance > $1.balance }.enumerated()), id: \.element.id) { index, member in
                    memberRow(member)
                    if index < members.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
            .padding(.horizontal, 14)
            .fadeCardBackground()

            SectionLabel("Group rules")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Starting balance").font(.fadeBody).foregroundStyle(Theme.text2)
                    Spacer()
                    CoinAmount(centicoins: group.startingBalance, font: .fadeBody.weight(.bold), iconSize: 14)
                }
                Text(group.buybackSummary).font(.fadeCaption).foregroundStyle(Theme.text2)
            }
            .fadeCard(padding: 14)

            Button { sheet = .invite } label: {
                Label("Invite friends", systemImage: "person.badge.plus")
            }
            .buttonStyle(.fadeSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Button("Leave group") { Task { await tryLeave() } }
                    .buttonStyle(.fadeDestructiveOutline)
                    .disabled(isOwner && members.count > 1)
                Text("Leaving cancels and refunds your open offers, and the coins you hold here are gone. Your profit or loss stays in your lifetime score. You can't leave with unsettled bets. If you rejoin later you start with 0 coins.")
                    .font(.caption)
                    .foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private func memberRow(_ member: LeaderboardRow) -> some View {
        let isMe = member.userId == me
        return HStack(spacing: 12) {
            Avatar(name: member.username ?? "?", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isMe ? "\(member.username ?? "you") (you)" : (member.username ?? "deleted user"))
                        .font(.fadeHeadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    if member.role == "owner" {
                        Text("Owner")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.pending)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 22)
                            .background(Theme.pending.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                CoinAmount(centicoins: member.balance, font: .fadeCaption.weight(.semibold), iconSize: 12, tint: Theme.text2)
            }
            Spacer(minLength: 4)
            if isOwner && !isMe {
                Button("Make owner") { sheet = .handOver(member) }
                    .buttonStyle(.fadeSecondaryCompact)
            }
            if !isMe {
                Menu {
                    Button("Report \(member.displayName)", systemImage: "flag") {
                        reportTarget = ReportTarget(type: "user", id: member.userId, title: member.displayName,
                                                    userID: member.userId, userName: member.username)
                    }
                    Button("Mute \(member.displayName)", systemImage: "speaker.slash") {
                        Task { actionError = await feedStoreMute(member) }
                    }
                    Button("Block \(member.displayName)", systemImage: "hand.raised.slash", role: .destructive) {
                        memberToBlock = member
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More for \(member.displayName)")
            }
        }
        .frame(minHeight: 64)
    }

    // MARK: Sheets

    @ViewBuilder private func sheetView(_ sheet: Sheet) -> some View {
        switch sheet {
        case .invite:
            InviteSheet(group: group)
        case .buyback:
            if let buyback {
                BuybackConfirmSheet(groupName: group.name, status: buyback, myNet: myNet) {
                    guard let userID = me else { return "You're signed out. Please sign in again." }
                    let error = await groups.claimBuyback(groupID: group.id, userID: userID)
                    await reload()
                    return error
                }
            }
        case .leave:
            LeaveGroupSheet(
                groupName: group.name,
                openOffers: openOfferCount,
                coinsHeld: live.balance,
                netProfit: myNet
            ) {
                guard let userID = me else { return "You're signed out. Please sign in again." }
                let error = await groups.leaveGroup(groupID: group.id, userID: userID)
                if error == nil { dismiss() }
                return error
            }
        case .leaveBlocked(let bets):
            LeaveBlockedSheet(groupName: group.name, bets: bets, me: me ?? UUID(), format: format) { router.tab = .bets }
        case .handOver(let member):
            HandOverSheet(member: member) {
                guard let userID = me else { return "You're signed out. Please sign in again." }
                let error = await groups.transferOwnership(groupID: group.id, to: member.userId, userID: userID)
                await reload()
                return error
            }
        }
    }

    // MARK: Actions

    private func reload() async {
        members = await groups.members(of: group.id)
        await reloadVotes()
        buyback = await groups.buybackStatus(groupID: group.id)
        if let userID = me { await groups.load(userID: userID) }
    }

    private func reloadVotes() async {
        openVotes = await groups.votes(groupID: group.id).filter(\.isOpen)
    }

    private func askForVote() async {
        guard let userID = me else { return }
        actionError = await groups.callVote(groupID: group.id, kind: "buyback", userID: userID)
        await reloadVotes()
        if actionError == nil { part = .votes }
    }

    /// Checks for unsettled bets first, so the person sees the reason up front instead of an error afterwards.
    private func tryLeave() async {
        guard let userID = me else { return }
        let myBets = await offerStore.myBets(groupID: group.id, userID: userID)
        let pending = myBets.filter { $0.status == "pending" }
        if !pending.isEmpty {
            sheet = .leaveBlocked(pending)
            return
        }
        let myOffers = await offerStore.myOffers(groupID: group.id, userID: userID)
        openOfferCount = myOffers.filter { $0.status == "open" }.count
        sheet = .leave
    }

    private func feedStoreMute(_ member: LeaderboardRow) async -> String? {
        await feedStore.mute(userID: member.userId)
    }

    private func feedStoreBlock(_ member: LeaderboardRow) async -> String? {
        await feedStore.block(userID: member.userId)
    }
}

/// The two ways to sort a leaderboard.
enum LeaderboardMode: String, CaseIterable, Hashable {
    case profit, balance

    var title: String { self == .profit ? "Net profit" : "Raw balance" }
}

/// The ranked list of members.
struct LeaderboardList: View {
    let rows: [LeaderboardRow]
    let mode: LeaderboardMode
    let me: UUID?

    private var sorted: [LeaderboardRow] {
        switch mode {
        case .profit: return rows.sorted { ($0.netProfit, $0.balance) > ($1.netProfit, $1.balance) }
        case .balance: return rows.sorted { $0.balance > $1.balance }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                let isMe = row.userId == me
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.fadeBody.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(index == 0 ? Theme.pending : (isMe ? Theme.text : Theme.text2))
                        .frame(width: 22)
                    Avatar(name: row.username ?? "?", size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isMe ? "you" : (row.username ?? "deleted user"))
                            .font(.fadeHeadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if row.buybackCount > 0 {
                            Text("\(row.buybackCount) buyback\(row.buybackCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.text2)
                        }
                    }
                    Spacer(minLength: 4)
                    switch mode {
                    case .profit:
                        CoinAmount(centicoins: row.netProfit, signed: true, font: .fadeHeadline.weight(.heavy), iconSize: 14)
                    case .balance:
                        CoinAmount(centicoins: row.balance, font: .fadeHeadline.weight(.heavy), iconSize: 14)
                    }
                }
                .frame(minHeight: 56)
                .padding(.horizontal, isMe ? 8 : 0)
                .background(isMe ? Theme.accent.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottom) {
                    if index < sorted.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
            if rows.isEmpty {
                Text("No members to rank yet.").font(.fadeBody).foregroundStyle(Theme.text2).padding(.vertical, 16)
            }
        }
    }
}

/// The "You're out of coins" card, in its three states (see the design canvas, "Out of coins").
struct BuybackCard: View {
    let status: BuybackStatus
    let busy: Bool
    let onClaim: () -> Void
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.pending)
                Text("You're out of coins")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.text)
            }
            if status.canClaim {
                Text("You have nothing left, and nothing tied up in bets. Buy back in to keep playing.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Buy back in for \(Coins.formatFixed(status.amount)) coins", action: onClaim)
                    .buttonStyle(.fadePrimary)
                    .disabled(busy)
            } else if status.reason == "weekly_limit" {
                Text("You've used all \(status.allowed ?? 0) of this group's buybacks for the week.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
                if let next = status.nextAvailable {
                    HStack(spacing: 10) {
                        Image(systemName: "clock").foregroundStyle(Theme.text2)
                        (Text("Your next one is available ") + Text(next.formatted(date: .abbreviated, time: .shortened)).fontWeight(.bold))
                            .font(.fadeBody)
                            .foregroundColor(Theme.text)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                }
            } else if status.reason == "needs_vote" {
                Text("This group decides buybacks by vote. Members have 24 hours to vote, and you can follow it under Votes.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Ask the group for a buyback", action: onAsk)
                    .buttonStyle(.fadePrimary)
                    .disabled(busy)
            }
            Text("A buyback is recorded in the group's history. Buyback coins never count as winnings.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
        }
        .fadeCard(stroke: Theme.pending.opacity(0.4))
        .padding(.horizontal, 16)
    }
}
