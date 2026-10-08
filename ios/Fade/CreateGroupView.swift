import SwiftUI

struct CreateGroupView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var startingCoins = 100
    @State private var policy: BuybackPolicy = .unlimited
    @State private var perWeek = 3
    @State private var sameBuyback = true
    @State private var buybackCoins = 100
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var effectiveBuyback: Int { sameBuyback ? startingCoins : buybackCoins }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (1...1_000_000).contains(startingCoins)
            && (1...1_000_000).contains(effectiveBuyback)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Group name", text: $name)
                }

                Section {
                    TextField("Coins", value: $startingCoins, format: .number)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Starting balance (coins)")
                } footer: {
                    Text("Everyone gets this many free play-money coins when they join.")
                }

                Section {
                    Picker("Buybacks", selection: $policy) {
                        ForEach(BuybackPolicy.allCases) { Text($0.label).tag($0) }
                    }
                    if policy == .weekly {
                        Stepper("\(perWeek) per week", value: $perWeek, in: 1...50)
                    }
                    Toggle("Same amount as starting balance", isOn: $sameBuyback)
                    if !sameBuyback {
                        TextField("Buyback coins", value: $buybackCoins, format: .number)
                            .keyboardType(.numberPad)
                    }
                } header: {
                    Text("When someone goes broke")
                } footer: {
                    Text("A member is only eligible once they have zero coins, including coins tied up in bets.")
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func create() async {
        guard let userID = session.profile?.id else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await groups.createGroup(
            name: name.trimmingCharacters(in: .whitespaces),
            startingCoins: startingCoins,
            policy: policy,
            perWeek: perWeek,
            buybackCoins: effectiveBuyback,
            userID: userID
        )
        if errorMessage == nil { dismiss() }
    }
}
