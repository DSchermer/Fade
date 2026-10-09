import SwiftUI
import UIKit

struct GroupDetailView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(FeedStore.self) private var feedStore
    @Environment(\.dismiss) private var dismiss
    let membership: GroupMembership   // as it was when this screen opened

    @State private var members: [LeaderboardRow] = []
    @State private var copied = false
    @State private var showLeaveConfirm = false
    @State private var memberToPromote: LeaderboardRow?
    @State private var actionError: String?
    @State private var openVotes: [VoteRow] = []
    @State private var reportTarget: ReportTarget?
    @State private var memberToBlock: LeaderboardRow?
    @State private var buyback: BuybackStatus?

    private var group: GroupInfo { membership.group }
    /// Always the latest balance (it changes whenever you post, take or cancel).
    private var live: GroupMembership { groups.memberships.first { $0.id == membership.id } ?? membership }

    var body: some View {
        List {
            if let reset = openVotes.first(where: { $0.kind == "reset" }) {
                Section {
                    NavigationLink {
                        VotesView(group: group)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Reset vote in progress", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline).foregroundStyle(.orange)
                            Text("If it passes, ALL unsettled bets will be voided and refunded. Yes \(reset.yesCount), no \(reset.noCount) of \(reset.electorate). Closes \(reset.closesAt.formatted(date: .abbreviated, time: .shortened)).")
                                .font(.footnote)
                        }
                    }
                }
            }

            Section("Your balance") {
                LabeledContent("Total", value: "\(Coins.format(live.balance)) coins")
                LabeledContent("Available to bet", value: "\(Coins.format(live.available)) coins")
                if live.escrow > 0 {
                    LabeledContent("Tied up in offers & bets", value: "\(Coins.format(live.escrow)) coins")
                }
            }

            BuybackSection(groupID: group.id, balance: live.balance, status: $buyback)

            Section {
                HStack {
                    Text(group.inviteCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = group.inviteCode
                        copied = true
                    }
                    .buttonStyle(.bordered)
                }
                ShareLink(item: "Join my Fade group “\(group.name)”! Open Fade → Join with a code → \(group.inviteCode)") {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
            } header: {
                Text("Invite friends")
            } footer: {
                Text("Anyone with this code can join. Invite links that open the app directly come later.")
            }

            Section("Activity") {
                NavigationLink {
                    FeedView(groupID: group.id)
                } label: {
                    Label("Group feed", systemImage: "text.bubble")
                }
            }

            Section("Bets") {
                NavigationLink {
                    GamesView(groupID: group.id)
                } label: {
                    Label("Browse games", systemImage: "sportscourt")
                }
                NavigationLink {
                    OpenOffersView(groupID: group.id)
                } label: {
                    Label("Open offers", systemImage: "tray.full")
                }
                NavigationLink {
                    MyBetsView(groupID: group.id)
                } label: {
                    Label("My bets", systemImage: "ticket")
                }
                NavigationLink {
                    LeaderboardView(groupID: group.id, startingBalance: group.startingBalance)
                } label: {
                    Label("Leaderboard", systemImage: "list.number")
                }
                NavigationLink {
                    VotesView(group: group)
                } label: {
                    Label(openVotes.isEmpty ? "Votes & seasons" : "Votes & seasons (\(openVotes.count) open)", systemImage: "hand.raised")
                }
            }

            Section {
                ForEach(members) { member in
                    HStack {
                        Text(member.displayName)
                        if member.role == "owner" {
                            Text("owner").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Coins.format(member.balance))").monospacedDigit()
                    }
                    .swipeActions(edge: .trailing) {
                        if canHandOver(to: member) {
                            Button("Make owner") { memberToPromote = member }.tint(.orange)
                        }
                    }
                    .contextMenu {
                        if canHandOver(to: member) {
                            Button("Make owner", systemImage: "crown") { memberToPromote = member }
                        }
                        if member.userId != session.profile?.id {
                            Button("Report \(member.displayName)", systemImage: "flag") {
                                reportTarget = ReportTarget(type: "user", id: member.userId, title: member.displayName)
                            }
                            Button("Mute \(member.displayName)", systemImage: "speaker.slash") {
                                Task { actionError = await feedStore.mute(userID: member.userId) }
                            }
                            Button("Block \(member.displayName)", systemImage: "hand.raised.slash", role: .destructive) {
                                memberToBlock = member
                            }
                        }
                    }
                }
            } header: {
                Text("Members (\(members.count))")
            } footer: {
                if live.role == "owner" && members.count > 1 {
                    Text("You're the owner. Swipe a member left to hand ownership to them. Touch and hold any member to report, mute or block them.")
                } else {
                    Text("Touch and hold a member to report, mute or block them.")
                }
            }

            Section("Group rules") {
                LabeledContent("Starting balance", value: "\(Coins.format(group.startingBalance)) coins")
                Text(group.buybackSummary).font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Button("Leave group", role: .destructive) { showLeaveConfirm = true }
                if live.role == "owner" && members.count > 1 {
                    Text("You're the owner. Make another member the owner before you can leave.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let actionError {
                    Text(actionError).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("Leaving cancels and refunds your open offers, and the coins you hold here are gone. Your profit or loss stays in your lifetime score. You can't leave with unsettled bets. If you rejoin later you start with 0 coins.")
            }

            Section {
                NoMoneyNotice()
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Leave \(group.name)?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) { Task { await leave() } }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("You hold \(Coins.format(live.balance)) coins here. They'll be gone, and your net profit of \(netProfitText) stays in your lifetime score.")
        }
        .confirmationDialog(
            "Make \(memberToPromote?.displayName ?? "them") the owner?",
            isPresented: Binding(get: { memberToPromote != nil }, set: { if !$0 { memberToPromote = nil } }),
            titleVisibility: .visible,
            presenting: memberToPromote
        ) { member in
            Button("Make owner") { Task { await promote(member) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You'll become an ordinary member. Only one person can own a group.")
        }
        .sheet(item: $reportTarget) { target in ReportView(target: target) }
        .confirmationDialog("Block \(memberToBlock?.displayName ?? "this person")?", isPresented: Binding(
            get: { memberToBlock != nil }, set: { if !$0 { memberToBlock = nil } }
        ), titleVisibility: .visible, presenting: memberToBlock) { member in
            Button("Block", role: .destructive) { Task { actionError = await feedStore.block(userID: member.userId) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's comments or feed activity, and you can't be friends. Bets in this group still work normally — to avoid someone's offers entirely, leave the group.")
        }
        .task {
            members = await groups.members(of: group.id)
            openVotes = await groups.votes(groupID: group.id).filter(\.isOpen)
        }
        .task(id: live.balance) {      // re-checked whenever my balance changes
            buyback = await groups.buybackStatus(groupID: group.id)
        }
        .refreshable {
            members = await groups.members(of: group.id)
            openVotes = await groups.votes(groupID: group.id).filter(\.isOpen)
            buyback = await groups.buybackStatus(groupID: group.id)
        }
    }

    // MARK: Leaving and ownership

    private var myNetProfit: Int64? {
        members.first { $0.userId == session.profile?.id }?.netProfit
    }

    private var netProfitText: String {
        myNetProfit.map { "\($0.signedCoins) coins" } ?? "so far"
    }

    private func canHandOver(to member: LeaderboardRow) -> Bool {
        live.role == "owner" && member.userId != session.profile?.id
    }

    private func leave() async {
        guard let userID = session.profile?.id else { return }
        actionError = await groups.leaveGroup(groupID: group.id, userID: userID)
        if actionError == nil { dismiss() }
    }

    private func promote(_ member: LeaderboardRow) async {
        guard let userID = session.profile?.id else { return }
        actionError = await groups.transferOwnership(groupID: group.id, to: member.userId, userID: userID)
        members = await groups.members(of: group.id)
    }
}
