import SwiftUI

/// Votes in a group: open ones to vote on, calling a reset vote, recent results, and past seasons.
struct VotesView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups

    let group: GroupInfo

    @State private var votes: [VoteRow] = []
    @State private var standings: [SeasonStandingRow] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var showCallReset = false
    @State private var isWorking = false

    private var openVotes: [VoteRow] { votes.filter(\.isOpen) }
    private var finished: [VoteRow] { votes.filter { !$0.isOpen }.prefix(10).map { $0 } }
    private var hasOpenReset: Bool { openVotes.contains { $0.kind == "reset" } }
    private var seasonNumbers: [Int] { Array(Set(standings.map(\.number))).sorted(by: >) }

    var body: some View {
        List {
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            if !openVotes.isEmpty {
                Section("Open votes") {
                    ForEach(openVotes) { vote in
                        VoteCard(vote: vote, startingBalance: group.startingBalance,
                                 isWorking: isWorking) { yes in Task { await cast(vote, yes: yes) } }
                    }
                }
            }

            Section {
                Button("Call a vote to reset the group") { showCallReset = true }
                    .disabled(hasOpenReset || isWorking)
            } footer: {
                Text("Any member can call a reset vote. It runs for 24 hours and passes when more than half of all members vote yes — or, when time runs out, when yes beats no with at least a few members voting.")
            }

            if !finished.isEmpty {
                Section("Recent results") {
                    ForEach(finished) { vote in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vote.title).font(.subheadline)
                            Text("\(vote.resultText) · yes \(vote.yesCount) / no \(vote.noCount)")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let decided = vote.decidedAt {
                                Text(decided.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !seasonNumbers.isEmpty {
                Section("Past seasons") {
                    ForEach(seasonNumbers, id: \.self) { number in
                        NavigationLink("Season \(number)") {
                            SeasonDetailView(number: number, rows: standings.filter { $0.number == number })
                        }
                    }
                }
            }
        }
        .overlay {
            if loaded && votes.isEmpty && standings.isEmpty {
                ContentUnavailableView("No votes yet", systemImage: "hand.raised",
                                       description: Text("Call a reset vote if the group wants a fresh start."))
            }
        }
        .navigationTitle("Votes & seasons")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog("Call a reset vote?", isPresented: $showCallReset, titleVisibility: .visible) {
            Button("Call the vote") { Task { await callReset() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If it passes, all unsettled bets are voided and refunded, open offers are cancelled, and everyone goes back to \(Coins.format(group.startingBalance)) coins.")
        }
    }

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
    }

    private func cast(_ vote: VoteRow, yes: Bool) async {
        guard let userID = session.profile?.id else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = await groups.castVote(voteID: vote.id, yes: yes, userID: userID)
        await reload()
    }
}

private struct VoteCard: View {
    let vote: VoteRow
    let startingBalance: Int64
    let isWorking: Bool
    let onVote: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vote.title).font(.headline)
            Text("Called by @\(vote.calledByUsername ?? "unknown") · closes \(vote.closesAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote).foregroundStyle(.secondary)

            if vote.kind == "reset" {
                Text("If this passes: open offers are cancelled, ALL unsettled bets are voided and refunded, everyone returns to \(Coins.format(startingBalance)) coins, buyback counts clear and a new season starts. Everyone keeps this season's profit or loss in their lifetime score.")
                    .font(.footnote).foregroundStyle(.orange)
            } else {
                Text("If this passes, @\(vote.subjectUsername ?? "unknown") gets the group's buyback amount.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            HStack {
                Label("\(vote.yesCount) yes", systemImage: "hand.thumbsup")
                Spacer()
                Label("\(vote.noCount) no", systemImage: "hand.thumbsdown")
                Spacer()
                Text("\(vote.electorate) members").foregroundStyle(.secondary)
            }
            .font(.subheadline)

            ProgressView(value: Double(vote.yesCount), total: Double(max(vote.electorate, 1)))

            Text("Passes at \(vote.electorate / 2 + 1) yes votes, or when time runs out with at least \(vote.quorum) votes and more yes than no.")
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button { onVote(true) } label: {
                    Label("Yes", systemImage: vote.myVote == true ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                Button { onVote(false) } label: {
                    Label("No", systemImage: vote.myVote == false ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .disabled(isWorking)
            if let mine = vote.myVote {
                Text("You voted \(mine ? "yes" : "no"). You can change it until the vote closes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Final standings of one finished season.
struct SeasonDetailView: View {
    let number: Int
    let rows: [SeasonStandingRow]

    private var sorted: [SeasonStandingRow] { rows.sorted { $0.netProfit > $1.netProfit } }

    var body: some View {
        List {
            Section {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text("\(index + 1)").font(.headline).monospacedDigit().frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.displayName).font(.headline)
                            Text("Finished with \(Coins.format(row.finalBalance))"
                                 + (row.buybackCount > 0 ? " · \(row.buybackCount) buyback\(row.buybackCount == 1 ? "" : "s")" : ""))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.netProfit.signedCoins)
                            .font(.headline).monospacedDigit()
                            .foregroundStyle(row.netProfit > 0 ? Color.green : (row.netProfit < 0 ? Color.red : Color.primary))
                    }
                }
            } footer: {
                if let ended = rows.first?.endedAt {
                    Text("Season \(number) ended \(ended.formatted(date: .abbreviated, time: .omitted)). Net profit = balance − starting balance − buyback coins.")
                }
            }
        }
        .navigationTitle("Season \(number)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
