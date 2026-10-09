import SwiftUI

/// Posting your own offer on a market: pick a side, a price and a size, and see exactly what both sides put up.
struct MakeOfferSheet: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var offerStore
    @Environment(\.dismiss) private var dismiss

    let market: MarketRef
    let groupID: UUID
    let onDone: () async -> Void

    @State private var side: Int
    @State private var priceText: String
    @State private var sharesText = "10"
    @State private var errorMessage: String?
    @State private var isSaving = false
    /// Set the moment you flip ¢ / American here, so the price box doesn't wait for the setting to be saved.
    @State private var formatOverride: PriceFormat?

    init(market: MarketRef, initialSide: Int, groupID: UUID, onDone: @escaping () async -> Void) {
        self.market = market
        self.groupID = groupID
        self.onDone = onDone
        _side = State(initialValue: initialSide)
        _priceText = State(initialValue: "")
    }

    private var format: PriceFormat { formatOverride ?? session.profile?.priceFormat ?? .cents }
    private var membership: GroupMembership? { groups.memberships.first { $0.id == groupID } }
    private var available: Int64 { membership?.available ?? 0 }

    private var cents: Int? { Odds.parseCents(priceText, format: format) }
    private var shares: Int? {
        guard let n = Int(sharesText.trimmingCharacters(in: .whitespaces)), n >= 1, n <= 1_000_000 else { return nil }
        return n
    }
    private var risk: Int64? {
        guard let cents, let shares else { return nil }
        return Stakes.makerRisk(shares: shares, cents: cents)
    }
    private var canAfford: Bool { (risk ?? 0) <= available }
    private var isValid: Bool { cents != nil && shares != nil && canAfford }
    /// The most shares you could post at this price.
    private var maxShares: Int {
        guard let cents, cents > 0 else { return 1 }
        return Int(max(1, min(1_000_000, available / Int64(cents))))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                gameSummary
                sideSection
                priceSection
                sharesSection
                if let cents, let shares, let risk {
                    stakesBox(cents: cents, shares: shares, risk: risk)
                }
                if let errorMessage { ErrorLine(errorMessage) }
                if cents != nil && shares != nil && !canAfford {
                    ErrorLine("You only have \(Coins.formatFixed(available)) coins available here.")
                }
                Button(isSaving ? "Posting…" : "Post offer") { Task { await post() } }
                    .buttonStyle(.fadePrimaryLarge)
                    .disabled(!isValid || isSaving)
                Text("Unfilled shares cancel when the game starts at \(market.gameStart.formatted(date: .omitted, time: .shortened)). Fade coins are free play money with no cash value.")
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
        .onAppear {
            if priceText.isEmpty { priceText = Odds.fieldText(cents: 50, format: format) }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text("Make an offer")
                .font(.fadeSectionTitle)
                .foregroundStyle(Theme.text)
            Spacer()
            CircleIconButton(systemImage: "xmark", label: "Close") { dismiss() }
        }
    }

    private var gameSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(market.eventTitle)
                    .font(.fadeHeadline.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(market.kindLabel) · \(market.league.uppercased()) · \(GameTime.label(market.gameStart))")
                    .font(.fadeCaption)
                    .foregroundStyle(Theme.text2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text((membership?.group.name ?? "").uppercased())
                    .font(.fadeLabel)
                    .tracking(0.8)
                    .foregroundStyle(Theme.text2)
                    .lineLimit(1)
                CoinAmount(centicoins: available, font: .fadeBody.weight(.bold), iconSize: 14)
            }
        }
    }

    private var sideSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("You back")
            HStack(spacing: 10) {
                ForEach([0, 1], id: \.self) { index in
                    let selected = side == index
                    Button {
                        side = index
                    } label: {
                        Text(market.sideName(index))
                            .font(.fadeHeadline.weight(selected ? .bold : .semibold))
                            .foregroundStyle(selected ? Theme.text : Theme.text2)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(selected ? Theme.accent.opacity(0.14) : Theme.raised,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var priceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Your price")
                Spacer()
                FadeSegmented(options: PriceFormat.allCases, title: { $0 == .cents ? "¢" : "American" }, selection: formatBinding)
                    .frame(width: 170)
            }
            HStack(spacing: 0) {
                priceButton("minus", label: "Lower price") { nudge(-1) }
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        TextField(format == .cents ? "1–99" : "-150", text: $priceText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 30, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .fixedSize()
                        if format == .cents {
                            Text("¢").font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.text)
                        }
                    }
                    Text(priceCaption)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(cents == nil && !priceText.isEmpty ? Theme.loss : Theme.text2)
                }
                .frame(maxWidth: .infinity)
                priceButton("plus", label: "Raise price") { nudge(1) }
            }
            .padding(6)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var priceCaption: String {
        guard let cents else {
            return format == .cents ? "Enter a whole number from 1 to 99" : "Enter odds like -150 or +120"
        }
        return format == .cents
            ? "same as \(Odds.americanText(cents: cents)) American"
            : "same as \(cents)¢ · a friend gets \(Odds.bothText(cents: 100 - cents))"
    }

    private func priceButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 52, height: 52)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var sharesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Shares (each pays 1 coin to the winner)")
            HStack(spacing: 8) {
                QuantityStepper(text: $sharesText, minimum: 1, lessLabel: "Fewer shares", moreLabel: "More shares")
                    .frame(width: 176)
                chip("25") { sharesText = "25" }
                chip("50") { sharesText = "50" }
                chip("Max") { sharesText = String(maxShares) }
            }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(FadeButtonStyle(kind: .quiet, height: 44))
    }

    private func stakesBox(cents: Int, shares: Int, risk: Int64) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("You put up").font(.fadeBody).foregroundStyle(Theme.text2)
                Spacer()
                CoinAmount(centicoins: risk, font: .fadeBody.weight(.bold), iconSize: 14)
            }
            HStack {
                Text("A friend puts up").font(.fadeBody).foregroundStyle(Theme.text2)
                Spacer()
                CoinAmount(centicoins: Stakes.takerRisk(shares: shares, cents: cents), font: .fadeBody.weight(.bold), iconSize: 14)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Text("Winner collects").font(.fadeHeadline).foregroundStyle(Theme.text)
                Spacer()
                CoinAmount(centicoins: Stakes.pot(shares: shares), font: .fadeHeadline.weight(.heavy), iconSize: 16, tint: Theme.win)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: Actions

    /// Switching ¢ / American here changes your price setting everywhere, and rewrites the price box in the new format.
    private var formatBinding: Binding<PriceFormat> {
        Binding(
            get: { format },
            set: { newFormat in
                let current = cents
                formatOverride = newFormat
                Task { await session.setPriceFormat(newFormat) }
                if let current { priceText = Odds.fieldText(cents: current, format: newFormat) } else { priceText = "" }
            }
        )
    }

    private func nudge(_ delta: Int) {
        let base = cents ?? 50
        let next = min(99, max(1, base + delta))
        priceText = Odds.fieldText(cents: next, format: format)
    }

    private func post() async {
        guard let cents, let shares else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await offerStore.postOffer(groupID: groupID, marketID: market.id, outcome: side, cents: cents, shares: shares)
        if let userID = session.profile?.id { await groups.load(userID: userID) }
        await onDone()
        if errorMessage == nil { dismiss() }
    }
}
