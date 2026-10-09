import SwiftUI

struct SettingsView: View {
    /// true when shown as the Me tab (no Done button; floating tab bar), false as a sheet.
    var asTab = false

    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss
    @State private var showLegal = false
    @State private var showDelete = false
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
                    NavigationLink("Notifications") { NotificationSettingsView() }
                    NavigationLink("Blocked & muted people") { BlockedUsersView() }
                    Button("About coins & help") { showLegal = true }
                    if let url = URL(string: AppConfig.privacyURL) { Link("Privacy policy", destination: url) }
                    if let url = URL(string: AppConfig.termsURL) { Link("Terms of use", destination: url) }
                    if let url = URL(string: AppConfig.supportURL) { Link("Help & support", destination: url) }
                    Button("Sign out", role: .destructive) {
                        Task {
                            groups.clear()
                            await session.signOut()
                            dismiss()
                        }
                    }
                }

                Section {
                    Button("Delete my account…", role: .destructive) { showDelete = true }
                } footer: {
                    Text("Permanently removes your account and personal information. Coins have no cash value and can't be recovered.")
                }
            }
            .navigationTitle("Settings")
            .task {
                await session.refreshProfile()
                score = await groups.myScore()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !asTab {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if asTab { FadeTabBar().padding(.horizontal, 16).padding(.bottom, 4) }
            }
            .sheet(isPresented: $showLegal) { LegalView() }
            .sheet(isPresented: $showDelete) { DeleteAccountView() }
        }
    }

    private var priceFormatBinding: Binding<PriceFormat> {
        Binding(
            get: { session.profile?.priceFormat ?? .cents },
            set: { newValue in Task { await session.setPriceFormat(newValue) } }
        )
    }
}
