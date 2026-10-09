import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var showLegal = false
    @State private var score: MyScore?

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    LabeledContent("Username", value: "@\(session.profile?.username ?? "")")
                    if let score {
                        LabeledContent("Lifetime score", value: "\(score.score.signedCoins) coins")
                    }
                    LabeledContent("Record (won–lost)",
                                   value: "\(session.profile?.lifetimeWins ?? 0)–\(session.profile?.lifetimeLosses ?? 0)")
                }

                Section {
                    Picker("Show prices as", selection: priceFormatBinding) {
                        ForEach(PriceFormat.allCases) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Price format")
                } footer: {
                    Text("Same bet either way: 60¢ is the same price as -150. You always see the exact price in cents before you confirm.")
                }

                if let message = session.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }

                Section {
                    NavigationLink("Blocked & muted people") { BlockedUsersView() }
                    Button("About coins & help") { showLegal = true }
                    Button("Sign out", role: .destructive) {
                        Task {
                            groups.clear()
                            await session.signOut()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                await session.refreshProfile()
                score = await groups.myScore()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showLegal) { LegalView() }
        }
    }

    private var priceFormatBinding: Binding<PriceFormat> {
        Binding(
            get: { session.profile?.priceFormat ?? .cents },
            set: { newValue in Task { await session.setPriceFormat(newValue) } }
        )
    }
}
