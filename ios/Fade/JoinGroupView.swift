import SwiftUI

struct JoinGroupView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var cleaned: String { code.trimmingCharacters(in: .whitespaces).uppercased() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: code) { errorMessage = nil }
                } footer: {
                    Text("Ask a friend in the group for their code. You'll get the group's starting balance.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Join a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { Task { await join() } }
                        .disabled(cleaned.count < 4 || isSaving)
                }
            }
        }
    }

    private func join() async {
        guard let userID = session.profile?.id else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await groups.joinGroup(code: cleaned, userID: userID)
        if errorMessage == nil { dismiss() }
    }
}
