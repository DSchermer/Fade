import SwiftUI

/// Shown once after the first sign-in: pick the name friends will find you by.
struct UsernameView: View {
    @Environment(Session.self) private var session
    @State private var username = ""
    @State private var errorMessage: String?

    private var cleaned: String { username.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isValid: Bool {
        cleaned.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Pick a username")
                .font(.title.bold())
            Text("Friends find you by this name. 3–20 letters, numbers, or underscores.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .onChange(of: username) { errorMessage = nil }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }

            Button("Continue") {
                Task { errorMessage = await session.setUsername(cleaned) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isValid || session.isBusy)

            Spacer()
            Button("Sign out") { Task { await session.signOut() } }
                .font(.footnote)
        }
        .padding()
    }
}
