import SwiftUI

/// Shown on a group's screen when you have no coins left (nothing available AND nothing tied up in bets).
struct BuybackSection: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups

    let groupID: UUID
    /// Changes whenever my balance changes, so the status is re-checked.
    let balance: Int64

    @State private var status: BuybackStatus?
    @State private var showConfirm = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        Group {
            if balance == 0, let status, status.busted {
                Section {
                    Label("You're out of coins", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.orange)

                    if status.canClaim {
                        Button("Buy back in for \(Coins.format(status.amount)) coins") { showConfirm = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)
                    } else if status.reason == "weekly_limit" {
                        Text("You've used all \(status.allowed ?? 0) of this group's buybacks for the week.")
                        if let next = status.nextAvailable {
                            Text("Your next one is available \(next.formatted(date: .abbreviated, time: .shortened)).")
                                .foregroundStyle(.secondary)
                        }
                    } else if status.reason == "needs_vote" {
                        Text("This group lets members vote on buybacks. Voting arrives in a later update.")
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                } footer: {
                    Text("A buyback is recorded in the group's history, and it counts against your net profit.")
                }
            }
        }
        .task(id: balance) { status = await groups.buybackStatus(groupID: groupID) }
        .confirmationDialog("Buy back in?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Buy back in for \(Coins.format(status?.amount ?? 0)) coins") { Task { await claim() } }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Everyone in the group can see it, and the coins count against your net profit.")
        }
    }

    private func claim() async {
        guard let userID = session.profile?.id else { return }
        isWorking = true
        defer { isWorking = false }
        errorMessage = await groups.claimBuyback(groupID: groupID, userID: userID)
        status = await groups.buybackStatus(groupID: groupID)
    }
}
