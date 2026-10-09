import SwiftUI

/// Permanently deletes the account. Required by App Store rules; also the right thing to offer.
struct DeleteAccountView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var typed = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var confirmed: Bool { typed.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE" }

    private static let consequences: [(icon: String, text: String)] = [
        ("rectangle.portrait.and.arrow.right", "You leave every group. Your open offers are cancelled."),
        ("ticket", "Your unsettled bets are voided, and the other person gets their whole stake back."),
        ("circle.circle", "Any coins you hold are gone. They have no cash value and can't be recovered."),
        ("trash", "Your username, friends, comments, reactions, notifications and sign-in are deleted."),
        ("crown", "If you own a group, ownership passes to the member who has been there longest."),
        ("person", "Your name is removed from saved activity. Past results stay in other people's history as \"deleted user\"."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Delete account").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }
                .padding(.top, 8)

                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.loss)
                    Text("This can't be undone")
                        .font(.fadeHeadline.weight(.bold))
                        .foregroundStyle(Theme.loss)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(Theme.loss.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.loss.opacity(0.35), lineWidth: 1))

                VStack(spacing: 0) {
                    ForEach(Array(Self.consequences.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 12) {
                            if item.icon == "circle.circle" {
                                CoinIcon(size: 20).padding(.top, 1)
                            } else {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text2)
                                    .frame(width: 20)
                                    .padding(.top, 1)
                            }
                            Text(item.text)
                                .font(.fadeBody)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) {
                            if index < Self.consequences.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Type DELETE to confirm")
                    TextField("DELETE", text: $typed)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .font(.fadeHeadline.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused || confirmed ? Theme.loss : Theme.line, lineWidth: 1.5))
                        .contentShape(Rectangle())
                        .onTapGesture { focused = true }
                }

                if let errorMessage { ErrorLine(errorMessage) }

                Button(isWorking ? "Deleting…" : "Delete my account") { Task { await delete() } }
                    .buttonStyle(.fadeDestructiveLarge)
                    .disabled(!confirmed || isWorking)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .fadeSheet()
        .interactiveDismissDisabled(isWorking)
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
