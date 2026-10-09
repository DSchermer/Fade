import SwiftUI

struct ReportTarget: Identifiable {
    let type: String
    let id: UUID
    let title: String
    /// The person behind the thing being reported, so the "report sent" screen can offer to mute or block them.
    var userID: UUID?
    var userName: String?
}

/// Choose a reason and send a report. The app's owner reviews reports and can hide content or ban accounts.
struct ReportView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: ReportTarget

    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var errorMessage: String?
    @State private var sent = false
    @State private var isSending = false
    @State private var followUp: String?

    private var personName: String { "@" + (target.userName ?? "this person") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if sent { sentContent } else { formContent }
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.card)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    // MARK: The form

    @ViewBuilder private var formContent: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Report").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                Text("What's wrong with \(target.title)?").font(.fadeBody).foregroundStyle(Theme.text2)
            }
            Spacer()
            CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }

        VStack(spacing: 0) {
            ForEach(Array(ReportReason.allCases.enumerated()), id: \.element.id) { index, option in
                reasonRow(option)
                if index < ReportReason.allCases.count - 1 {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
        }
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reason")

        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Anything else? (optional)")
            TextField("Add details that help us review it", text: $details, axis: .vertical)
                .lineLimit(3...6)
                .font(.fadeBody)
                .foregroundStyle(Theme.text)
                .padding(14)
                .frame(minHeight: 84, alignment: .topLeading)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }

        if let errorMessage { ErrorLine(errorMessage) }

        Button("Send report") { Task { await send() } }
            .buttonStyle(.fadePrimaryLarge)
            .disabled(isSending)

        Text("Only the Fade team sees your report. We remove content and accounts that break the rules.")
            .font(.caption)
            .foregroundStyle(Theme.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func reasonRow(_ option: ReportReason) -> some View {
        let selected = option == reason
        return Button {
            reason = option
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(selected ? Theme.accent : Theme.text3, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().fill(selected ? Theme.accent : Color.clear).frame(width: 10, height: 10))
                Text(option.label)
                    .font(.fadeHeadline.weight(selected ? .bold : .regular))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(selected ? Theme.accent.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: After sending

    @ViewBuilder private var sentContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Theme.win)
                .frame(width: 64, height: 64)
                .background(Theme.win.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            Text("Thanks, report sent").font(.fadeSectionTitle).foregroundStyle(Theme.text)
            Text("We review reports and remove content or accounts that break the rules.")
                .font(.fadeBody)
                .foregroundStyle(Theme.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)

        if target.userID != nil {
            if let followUp {
                Text(followUp)
                    .font(.fadeBody.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .fadeCard(fill: Theme.bg)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Don't want to see \(personName)?")
                    VStack(spacing: 0) {
                        followUpRow(
                            icon: "speaker.slash", title: "Mute \(personName)",
                            detail: "You stop seeing their comments. They aren't told.", tint: Theme.text2, titleColor: Theme.text
                        ) { Task { await mute() } }
                        Rectangle().fill(Theme.line).frame(height: 1)
                        followUpRow(
                            icon: "hand.raised.slash", title: "Block \(personName)",
                            detail: "Neither of you sees the other's comments or posts.", tint: Theme.loss, titleColor: Theme.loss
                        ) { Task { await block() } }
                    }
                    .padding(.horizontal, 14)
                    .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                }
            }
        }

        if let errorMessage { ErrorLine(errorMessage) }

        Button("Done") { dismiss() }
            .buttonStyle(.fadePrimaryLarge)
    }

    private func followUpRow(icon: String, title: String, detail: String, tint: Color, titleColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.fadeHeadline).foregroundStyle(titleColor)
                    Text(detail).font(.caption).foregroundStyle(Theme.text2).multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func send() async {
        isSending = true
        defer { isSending = false }
        errorMessage = await store.report(type: target.type, id: target.id, reason: reason, details: details)
        if errorMessage == nil { sent = true }
    }

    private func mute() async {
        guard let userID = target.userID else { return }
        errorMessage = await store.mute(userID: userID)
        if errorMessage == nil { followUp = "Muted \(personName). Undo it any time in Me → Blocked & muted." }
    }

    private func block() async {
        guard let userID = target.userID else { return }
        errorMessage = await store.block(userID: userID)
        if errorMessage == nil { followUp = "Blocked \(personName). Undo it any time in Me → Blocked & muted." }
    }
}
