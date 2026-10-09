import SwiftUI

/// Taking some (or all) of the shares in someone's offer, with the exact coins at stake on both sides.
struct TakeOfferSheet: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var offerStore
    @Environment(\.dismiss) private var dismiss

    let offer: OfferRow
    let onDone: () async -> Void

    @State private var sharesText: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(offer: OfferRow, onDone: @escaping () async -> Void) {
        self.offer = offer
        self.onDone = onDone
        _sharesText = State(initialValue: String(min(offer.sharesOpen, 10)))
    }

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var available: Int64 { groups.memberships.first { $0.id == offer.groupId }?.available ?? 0 }
    private var shares: Int? {
        guard let n = Int(sharesText.trimmingCharacters(in: .whitespaces)), n >= 1, n <= offer.sharesOpen else { return nil }
        return n
    }
    private var myRisk: Int64 { Stakes.takerRisk(shares: shares ?? 0, cents: offer.priceCents) }
    private var theirRisk: Int64 { Stakes.makerRisk(shares: shares ?? 0, cents: offer.priceCents) }
    private var pot: Int64 { Stakes.pot(shares: shares ?? 0) }
    private var canAfford: Bool { myRisk <= available }
    /// The most shares you can afford right now, up to what's left.
    private var maxShares: Int {
        let perShare = Int64(offer.takerCents)
        guard perShare > 0 else { return offer.sharesOpen }
        return Int(max(0, min(Int64(offer.sharesOpen), available / perShare)))
    }
    private var isValid: Bool { shares != nil && canAfford }

    var body: some View {
        let price = Odds.parts(cents: offer.takerCents, format: format)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fade \(offer.makerName)")
                            .font(.fadeSectionTitle)
                            .foregroundStyle(Theme.text)
                        Text("\(offer.eventTitle) · \(GameTime.label(offer.gameStart))")
                            .font(.fadeCaption)
                            .foregroundStyle(Theme.text2)
                    }
                    Spacer(minLength: 8)
                    CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
                }

                // what you're backing
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("You back")
                        Text(offer.takerSide)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        SectionLabel("At")
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(price.main).font(.title2.weight(.heavy)).monospacedDigit().foregroundStyle(Theme.accent)
                            Text(price.alt).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text2)
                        }
                    }
                }
                .padding(14)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))

                // how many
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionLabel("Shares (each pays 1 coin)")
                        Spacer()
                        Text("\(offer.sharesOpen) left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.text2)
                    }
                    HStack(spacing: 8) {
                        QuantityStepper(text: $sharesText, minimum: 1, maximum: offer.sharesOpen, lessLabel: "Fewer shares", moreLabel: "More shares")
                            .frame(width: 176)
                        quickButton("All") { sharesText = String(offer.sharesOpen) }
                        quickButton("Max") { sharesText = String(max(1, maxShares)) }
                    }
                }

                stakesBox

                if let errorMessage { ErrorLine(errorMessage) }
                if shares != nil && !canAfford {
                    ErrorLine("You only have \(Coins.formatFixed(available)) coins available here.")
                }

                Button(isSaving ? "Taking…" : "Take \(shares ?? 0) share\(shares == 1 ? "" : "s")") {
                    Task { await confirm() }
                }
                .buttonStyle(.fadePrimaryLarge)
                .disabled(!isValid || isSaving)

                Text("The winner collects the whole pot. Fade coins are free play money with no cash value.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.card)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.card)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(FadeButtonStyle(kind: .quiet, height: 44))
    }

    private var stakesBox: some View {
        VStack(spacing: 10) {
            stakeRow("You put up", centicoins: myRisk)
            stakeRow("\(offer.makerName) puts up", centicoins: theirRisk)
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Text("Winner collects").font(.fadeHeadline).foregroundStyle(Theme.text)
                Spacer()
                CoinAmount(centicoins: pot, font: .fadeHeadline.weight(.heavy), iconSize: 16, tint: Theme.win)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func stakeRow(_ title: String, centicoins: Int64) -> some View {
        HStack {
            Text(title).font(.fadeBody).foregroundStyle(Theme.text2)
            Spacer()
            CoinAmount(centicoins: centicoins, font: .fadeBody.weight(.bold), iconSize: 14)
        }
    }

    private func confirm() async {
        guard let shares else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await offerStore.takeOffer(offerID: offer.id, shares: shares)
        if let userID = session.profile?.id { await groups.load(userID: userID) }
        await onDone()
        if errorMessage == nil { dismiss() }
    }
}
