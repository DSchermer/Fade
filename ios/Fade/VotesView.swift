import SwiftUI

/// Votes in a group as a screen of its own.
struct VotesView: View {
    let group: GroupInfo

    var body: some View {
        ScrollView {
            VotesContent(group: group)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
        .fadeScreen()
        .navigationTitle("Votes and seasons")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Open votes to vote on, calling a reset vote, recent results, and past seasons. Used on a group's page and on its own screen.
struct VotesContent: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups

    let group: GroupInfo
    var refreshTick = 0
    var onVotesChanged: () -> Void = {}

    @State private var votes: [VoteRow] = []
    @State private var standings: [SeasonStandingRow] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var showCallReset = false
    @State private var isWorking = false

    private struct LoadKey: Equatable {
        let tick: Int
    }

    private var openVotes: [VoteRow] { votes.filter(\.isOpen) }
    private var finished: [VoteRow] { Array(votes.filter { !$0.isOpen }.prefix(10)) }
    private var hasOpenReset: Bool { openVotes.contains { $0.kind == "reset" } }
    private var seasonNumbers: [Int] { Array(Set(standings.map(\.number))).sorted(by: >) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let errorMessage { ErrorLine(errorMessage) }

            ForEach(openVotes) { vote in
                VoteCard(vote: vote, startingBalance: group.startingBalance, isWorking: isWorking) { yes in
                    Task { await cast(vote, yes: yes) }
                }
            }

            Button("Call a vote to reset the group") { showCallReset = true }
                .buttonStyle(.fadeQuiet)
                .disabled(hasOpenReset || isWorking)
            Text("Any member can call a reset vote. It runs for 24 hours and passes when more than half of all members vote yes, or when time runs out and yes beats no with a few members voting.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)

            if !finished.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Recent results")
                    VStack(spacing: 0) {
                        ForEach(Array(finished.enumerated()), id: \.element.id) { index, vote in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(vote.title).font(.fadeBody.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text(resultDetail(vote)).font(.caption).foregroundStyle(Theme.text2)
                                }
                                Spacer(minLength: 8)
                                StatusPill(text: pillText(vote), tone: pillTone(vote))
                            }
                            .frame(minHeight: 60)
                            .overlay(alignment: .bottom) {
                                if index < finished.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .fadeCardBackground()
                }
            }

            if !seasonNumbers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Past seasons")
                    VStack(spacing: 0) {
                        ForEach(seasonNumbers, id: \.self) { number in
                            NavigationLink {
                                SeasonDetailView(number: number, rows: standings.filter { $0.number == number })
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Season \(number)").font(.fadeBody.weight(.semibold)).foregroundStyle(Theme.text)
                                        Text(seasonDetail(number)).font(.caption).foregroundStyle(Theme.text2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text3)
                                }
                                .frame(minHeight: 60)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .fadeCardBackground()
                }
            }

            if loaded && votes.isEmpty && standings.isEmpty {
                Text("No votes yet. Call a reset vote if the group wants a fresh start.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
            }
        }
        .task(id: LoadKey(tick: refreshTick)) { await reload() }
        .confirmationDialog("Call a reset vote?", isPresented: $showCallReset, titleVisibility: .visible) {
            Button("Call the vote") { Task { await callReset() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If it passes, all unsettled bets are voided and refunded, open offers are cancelled, and everyone goes back to \(Coins.formatFixed(group.startingBalance)) coins.")
        }
    }

    // MARK: Text

    private func resultDetail(_ vote: VoteRow) -> String {
        var text = "yes \(vote.yesCount) · no \(vote.noCount)"
        if let decided = vote.decidedAt { text += " · " + decided.formatted(.dateTime.month(.abbreviated).day()) }
        return text
    }

    private func pillText(_ vote: VoteRow) -> String {
        switch vote.status {
        case "passed": return "Passed"
        case "failed": return "Failed"
        default: return "Cancelled"
        }
    }

    private func pillTone(_ vote: VoteRow) -> FeedTone {
        switch vote.status {
        case "passed": return .win
        case "failed": return .loss
        default: return .neutral
        }
    }

    private func seasonDetail(_ number: Int) -> String {
        let rows = standings.filter { $0.number == number }
        var parts: [String] = []
        if let ended = rows.first?.endedAt { parts.append("Ended " + ended.formatted(.dateTime.month(.abbreviated).day())) }
        if let winner = rows.max(by: { $0.netProfit < $1.netProfit }) {
            parts.append("winner \(winner.username ?? "deleted user") \(Coins.formatSigned(winner.netProfit))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func reload() async {
        votes = await groups.votes(groupID: group.id)
        standings = await groups.seasonHistory(groupID: group.id)
        loaded = true
    }

    private func callReset() async {
        guard let userID = session.profile?.id else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = await groups.callVote(groupID: group.id, kind: "reset", userID: userID)
        await reload()
        onVotesChanged()
    }

    private func cast(_ vote: VoteRow, yes: Bool) async {
        guard let userID = session.profile?.id else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = await groups.castVote(voteID: vote.id, yes: yes, userID: userID)
        await reload()
        onVotesChanged()
    }
}

/// The yes / no / not-yet-voted bar.
struct VoteProgressBar: View {
    let yes: Int
    let no: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            let count = CGFloat(max(total, 1))
            let width = proxy.size.width
            HStack(spacing: 2) {
                Rectangle().fill(Theme.win).frame(width: max(0, width * CGFloat(yes) / count))
                Rectangle().fill(Theme.loss).frame(width: max(0, width * CGFloat(no) / count))
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 10, alignment: .leading)
            .background(Theme.raised)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// One open vote: where it stands and the Yes / No buttons.
struct VoteCard: View {
    let vote: VoteRow
    let startingBalance: Int64
    let isWorking: Bool
    let onVote: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("VOTE OPEN")
                    .font(.fadeLabel)
                    .tracking(1)
                    .foregroundStyle(Theme.pending)
                Spacer()
                Text("Closes in \(RelativeTime.remaining(until: vote.closesAt))")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vote.title).font(.fadeSectionTitle).foregroundStyle(Theme.text)
                Text("Called by \(vote.calledByUsername ?? "deleted user")").font(.fadeCaption).foregroundStyle(Theme.text2)
            }

            VStack(alignment: .leading, spacing: 8) {
                VoteProgressBar(yes: vote.yesCount, no: vote.noCount, total: vote.electorate)
                HStack {
                    Text("\(vote.yesCount) yes").foregroundStyle(Theme.win)
                    Spacer()
                    Text("\(vote.noCount) no").foregroundStyle(Theme.loss)
                    Spacer()
                    Text("\(max(0, vote.electorate - vote.yesCount - vote.noCount)) haven't voted").foregroundStyle(Theme.text2)
                }
                .font(.fadeCaption.weight(.bold))
                .monospacedDigit()
                Text("Passes at \(vote.electorate / 2 + 1) yes votes, or when time runs out with at least \(vote.quorum) votes and more yes than no.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            consequence

            HStack(spacing: 10) {
                voteButton(yes: true)
                voteButton(yes: false)
            }
            .disabled(isWorking)

            if let mine = vote.myVote {
                Text("You voted \(mine ? "yes" : "no"). You can change it until the vote closes.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity)
            }
        }
        .fadeCard(padding: 18, fill: Theme.pending.opacity(0.09), stroke: Theme.pending.opacity(0.32))
    }

    @ViewBuilder private var consequence: some View {
        if vote.kind == "reset" {
            (Text("If it passes: open offers are cancelled, ")
                + Text("all unsettled bets are voided and refunded").fontWeight(.bold)
                + Text(", everyone returns to \(Coins.formatFixed(startingBalance)) coins and a new season starts. Everyone keeps this season's profit or loss in their lifetime score."))
                .font(.fadeBody)
                .foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("If this passes, \(vote.subjectUsername ?? "deleted user") gets the group's buyback amount.")
                .font(.fadeBody)
                .foregroundStyle(Theme.text)
        }
    }

    private func voteButton(yes: Bool) -> some View {
        let selected = vote.myVote == yes
        let tint = yes ? Theme.win : Theme.loss
        return Button {
            onVote(yes)
        } label: {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)) }
                Text(yes ? "Yes" : "No")
            }
            .font(.fadeHeadline.weight(.bold))
            .foregroundStyle(selected ? tint : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? tint.opacity(0.14) : Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).strokeBorder(selected ? tint : Theme.line, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(yes ? "Vote yes" : "Vote no")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Final standings of one finished season.
struct SeasonDetailView: View {
    let number: Int
    let rows: [SeasonStandingRow]

    private var sorted: [SeasonStandingRow] { rows.sorted { $0.netProfit > $1.netProfit } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.fadeBody.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(index == 0 ? Theme.pending : Theme.text2)
                                .frame(width: 22)
                            Avatar(name: row.username ?? "?", size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.username ?? "deleted user").font(.fadeHeadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text("Finished with \(Coins.formatFixed(row.finalBalance))" + (row.buybackCount > 0 ? " · \(row.buybackCount) buyback\(row.buybackCount == 1 ? "" : "s")" : ""))
                                    .font(.caption)
                                    .foregroundStyle(Theme.text2)
                            }
                            Spacer(minLength: 4)
                            CoinAmount(centicoins: row.netProfit, signed: true, font: .fadeHeadline.weight(.heavy), iconSize: 14)
                        }
                        .frame(minHeight: 60)
                        .overlay(alignment: .bottom) {
                            if index < sorted.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .fadeCardBackground()
                if let ended = rows.first?.endedAt {
                    Text("Season \(number) ended \(ended.formatted(date: .abbreviated, time: .omitted)). Net profit = balance − starting balance − buyback coins.")
                        .font(.caption)
                        .foregroundStyle(Theme.text3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .fadeScreen()
        .navigationTitle("Season \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}
