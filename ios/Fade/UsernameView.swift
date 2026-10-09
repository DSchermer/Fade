import SwiftUI

/// Shown once after the first sign-in: pick the name friends will find you by.
struct UsernameView: View {
    @Environment(Session.self) private var session
    @State private var username = ""
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var cleaned: String { username.trimmingCharacters(in: .whitespaces).lowercased() }
    private var isValid: Bool {
        cleaned.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Pick a username")
                .font(.fadeScreenTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text("Friends find you by this name. 3–20 letters, numbers, or underscores.")
                .font(.fadeBody)
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("@").font(.fadeHeadline).foregroundStyle(Theme.text2)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(.fadeHeadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .onChange(of: username) { _, _ in errorMessage = nil }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? Theme.accent : Theme.line, lineWidth: 1.5))

            if let errorMessage { ErrorLine(errorMessage) }

            Button("Continue") {
                Task { errorMessage = await session.setUsername(cleaned) }
            }
            .buttonStyle(.fadePrimaryLarge)
            .disabled(!isValid || session.isBusy)

            Spacer()
            Button("Sign out") { Task { await session.signOut() } }
                .font(.fadeCaption.weight(.semibold))
                .foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fadeScreen()
    }
}
