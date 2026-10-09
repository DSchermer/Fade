import SwiftUI
import UIKit

/// Joining a group with the 8-character code a friend shared.
struct JoinGroupView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss

    var prefill: String? = nil

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private static let length = 8

    private var characters: [String] {
        let typed = code.map { String($0) }
        return typed + Array(repeating: "", count: max(0, Self.length - typed.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Join a group").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Enter the \(Self.length)-character code a friend shared with you.")
                    .font(.fadeHeadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack {
                    TextField("", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .opacity(0.02)
                        .accessibilityLabel("Invite code")
                    codeBoxes
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { focused = true }

                Button {
                    if let text = UIPasteboard.general.string { code = Self.clean(text) }
                } label: {
                    Text("Paste from clipboard")
                        .font(.fadeBody.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage { ErrorLine(errorMessage) }
                Button(isSaving ? "Joining…" : "Join group") { Task { await join() } }
                    .buttonStyle(.fadePrimaryLarge)
                    .disabled(code.count < Self.length || isSaving)
                Text("You start with the group's starting balance. If you leave and rejoin later, you start from zero.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .presentationDragIndicator(.visible)
        .onChange(of: code) { _, value in
            let cleaned = Self.clean(value)
            if cleaned != value { code = cleaned }
            errorMessage = nil
        }
        .onAppear {
            if let prefill, code.isEmpty { code = Self.clean(prefill) }
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)     // wait for the sheet to finish sliding up
            focused = true
        }
    }

    private var codeBoxes: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.length, id: \.self) { index in
                let isNext = index == code.count && focused
                Text(characters[index])
                    .font(.system(size: 24, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isNext ? Theme.accent : Theme.line, lineWidth: isNext ? 1.5 : 1))
            }
        }
        .accessibilityHidden(true)
    }

    /// Letters and numbers only, capitals, at most 8.
    static func clean(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(length))
    }

    private func join() async {
        guard let userID = session.profile?.id else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await groups.joinGroup(code: code, userID: userID)
        if errorMessage == nil { dismiss() }
    }
}
