import SwiftUI

/// Ranks a group's members. Toggle between net profit and raw balance.
struct LeaderboardView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups

    let groupID: UUID
    let startingBalance: Int64

    enum Mode: String, CaseIterable, Identifiable {
        case profit = "Net profit"
        case balance = "Raw balance"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .profit
    @State private var rows: [LeaderboardRow] = []
    @State private var buybacks: [BuybackRow] = []
    @State private var loaded = false

    private var sorted: [LeaderboardRow] {
        switch mode {
        case .profit: return rows.sorted { ($0.netProfit, $0.balance) > ($1.netProfit, $1.balance) }
        case .balance: return rows.sorted { $0.balance > $1.balance }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } footer: {
                Text(mode == .profit
                     ? "Net profit = balance − starting balance − buyback coins. Buybacks count against you."
                     : "Everything each member holds right now, including coins tied up in bets. The number in brackets is how many buybacks they've used.")
            }

            Section {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline).monospacedDigit()
                            .frame(width: 28)
                            .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(row.displayName).font(.headline)
                                if row.userId == session.profile?.id {
                                    Text("you").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.tint.opacity(0.15), in: Capsule())
                                }
                                if mode == .balance && row.buybackCount > 0 {
                                    Text("(\(row.buybackCount) buyback\(row.buybackCount == 1 ? "" : "s"))")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if mode == .profit && row.buybackCount > 0 {
                                Text("\(row.buybackCount) buyback\(row.buybackCount == 1 ? "" : "s") · \(Coins.format(row.buybackCoins)) coins")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        switch mode {
                        case .profit:
                            Text(row.netProfit.signedCoins)
                                .font(.headline).monospacedDigit()
                                .foregroundStyle(row.netProfit > 0 ? Color.green : (row.netProfit < 0 ? Color.red : Color.primary))
                        case .balance:
                            Text(Coins.format(row.balance)).font(.headline).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text("\(rows.count) member\(rows.count == 1 ? "" : "s") · started with \(Coins.format(startingBalance)) coins")
            }

            if !buybacks.isEmpty {
                Section("Buyback history") {
                    ForEach(buybacks) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.displayName) bought back in").font(.subheadline)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(Coins.format(item.amount))").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if loaded && rows.isEmpty {
                ContentUnavailableView("No members to rank", systemImage: "list.number")
            }
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        rows = await groups.leaderboard(groupID: groupID)
        buybacks = await groups.buybackHistory(groupID: groupID)
        loaded = true
    }
}
