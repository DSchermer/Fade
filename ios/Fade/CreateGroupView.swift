import SwiftUI

/// Making a new group: its name, how many coins everyone starts with, and what happens when someone goes broke.
struct CreateGroupView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var startingText = "100"
    @State private var policy: BuybackPolicy = .unlimited
    @State private var perWeekText = "3"
    @State private var sameBuyback = true
    @State private var buybackText = "100"
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    private static let nameLimit = 60

    private var startingCoins: Int? { Int(startingText.trimmingCharacters(in: .whitespaces)) }
    private var perWeek: Int? { Int(perWeekText.trimmingCharacters(in: .whitespaces)) }
    private var buybackCoins: Int? { sameBuyback ? startingCoins : Int(buybackText.trimmingCharacters(in: .whitespaces)) }
    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let start = startingCoins, (1...1_000_000).contains(start),
              let buyback = buybackCoins, (1...1_000_000).contains(buyback) else { return false }
        if policy == .weekly { return perWeek.map { (1...50).contains($0) } ?? false }
        return true
    }

    private func shortTitle(_ policy: BuybackPolicy) -> String {
        switch policy {
        case .unlimited: return "Unlimited"
        case .weekly: return "Per week"
        case .vote: return "By vote"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Create a group").font(.fadeSectionTitle).foregroundStyle(Theme.text)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionLabel("Group name")
                            Spacer()
                            Text("\(name.count) / \(Self.nameLimit)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.text2)
                        }
                        TextField("College Boys", text: $name)
                            .font(.fadeHeadline.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .focused($nameFocused)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 56)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(nameFocused ? Theme.accent : Theme.line, lineWidth: 1.5))
                            .onChange(of: name) { _, value in
                                if value.count > Self.nameLimit { name = String(value.prefix(Self.nameLimit)) }
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Starting balance")
                        coinStepper(text: $startingText, step: 10)
                        Text("Everyone gets this many free play-money coins when they join.")
                            .font(.caption)
                            .foregroundStyle(Theme.text2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("When someone goes broke")
                        FadeSegmented(options: BuybackPolicy.allCases, title: shortTitle, selection: $policy)
                        if policy == .weekly {
                            HStack {
                                Text("Buybacks per week").font(.fadeHeadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Spacer()
                                QuantityStepper(text: $perWeekText, minimum: 1, maximum: 50, lessLabel: "Fewer", moreLabel: "More")
                                    .frame(width: 150)
                            }
                            .padding(.leading, 16)
                            .padding(.trailing, 6)
                            .padding(.vertical, 6)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        }
                        HStack {
                            Text("Same buyback as starting balance")
                                .font(.fadeHeadline.weight(.semibold))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Toggle("Same buyback as starting balance", isOn: $sameBuyback)
                                .labelsHidden()
                                .tint(Theme.win)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        if !sameBuyback { coinStepper(text: $buybackText, step: 10) }
                        Text("Members can only buy back when they have zero coins, including coins in open offers and bets. Every buyback is shown to the group and never counts as winnings.")
                            .font(.caption)
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage { ErrorLine(errorMessage) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(isSaving ? "Creating…" : "Create group") { Task { await create() } }
                .buttonStyle(.fadePrimaryLarge)
                .disabled(!isValid || isSaving)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(Theme.bg)
        .presentationDragIndicator(.visible)
    }

    private func coinStepper(text: Binding<String>, step: Int) -> some View {
        QuantityStepper(text: text, minimum: 1, maximum: 1_000_000, step: step, showsCoin: true, lessLabel: "Less", moreLabel: "More")
    }

    private func create() async {
        guard let userID = session.profile?.id, let start = startingCoins, let buyback = buybackCoins else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await groups.createGroup(
            name: name.trimmingCharacters(in: .whitespaces),
            startingCoins: start,
            policy: policy,
            perWeek: perWeek ?? 3,
            buybackCoins: buyback,
            userID: userID
        )
        if errorMessage == nil { dismiss() }
    }
}
