import SwiftUI

/// Permanently deletes the account. Required by App Store rules; also the right thing to offer.
struct DeleteAccountView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This can't be undone", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.headline)
                    Text("When you delete your account:")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• You leave every group. Your open offers are cancelled.")
                        Text("• Your unsettled bets are voided, and the other person gets their whole stake back.")
                        Text("• Any coins you hold are gone. They have no cash value and can't be recovered.")
                        Text("• Your username, friends, comments, reactions, notifications and sign-in are deleted.")
                        Text("• If you own a group, ownership passes to the member who has been there longest.")
                        Text("• Your name is removed from saved activity. Past results stay in other people's history as \"deleted user\".")
                    }
                    .font(.subheadline)
                }

                Section {
                    TextField("Type DELETE to confirm", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                Section {
                    Button("Delete my account", role: .destructive) { Task { await delete() } }
                        .disabled(typed.trimmingCharacters(in: .whitespaces).uppercased() != "DELETE" || isWorking)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func delete() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = await session.deleteAccount()
        if errorMessage == nil {
            groups.clear()
            dismiss()
        }
    }
}
