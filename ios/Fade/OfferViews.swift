import SwiftUI

/// One offer in a list: who, which side, at what price, how much is left.
struct OfferRowView: View {
    let offer: OfferRow
    let format: PriceFormat
    let isMine: Bool
    var showGame = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showGame {
                Text("\(offer.eventTitle) · \(offer.gameStart.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(isMine ? "You back \(offer.backedSide)" : "\(offer.makerName) backs \(offer.backedSide)")
                    .font(.headline)
                Spacer()
                Text(Odds.priceText(cents: offer.priceCents, format: format)).font(.headline).monospacedDigit()
            }
            Text("\(offer.sharesOpen) of \(offer.sharesTotal) shares left")
                .font(.subheadline).foregroundStyle(.secondary)
            if !isMine {
                Text("Take it to back \(offer.takerSide) at \(Odds.priceText(cents: offer.takerCents, format: format))")
                    .font(.footnote).foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Confirms taking some shares of someone's offer, showing exactly what both sides risk.
struct TakeOfferView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let offer: OfferRow
    let onDone: () async -> Void

    @State private var shares = 1
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var available: Int64 { groups.memberships.first { $0.id == offer.groupId }?.available ?? 0 }
    private var myRisk: Int64 { Stakes.takerRisk(shares: shares, cents: offer.priceCents) }
    private var theirRisk: Int64 { Stakes.makerRisk(shares: shares, cents: offer.priceCents) }
    private var canAfford: Bool { myRisk <= available }

    var body: some View {
        NavigationStack {
            Form {
                Section("The offer") {
                    LabeledContent("Game", value: offer.eventTitle)
                    LabeledContent("From", value: offer.makerName)
                    LabeledContent("They back", value: offer.backedSide)
                    LabeledContent("At", value: Odds.bothText(cents: offer.priceCents))
                }

                Section {
                    LabeledContent("You back", value: offer.takerSide)
                    LabeledContent("Your price", value: Odds.bothText(cents: offer.takerCents))
                    Stepper("Shares: \(shares)", value: $shares, in: 1...max(1, offer.sharesOpen))
                    if offer.sharesOpen > 1 {
                        Button("Take all \(offer.sharesOpen) remaining") { shares = offer.sharesOpen }
                    }
                } header: {
                    Text("Your side")
                } footer: {
                    Text("Each share pays 1 coin to whoever is right. \(offer.sharesOpen) shares are left.")
                }

                Section("Exactly what's at stake") {
                    LabeledContent("You risk", value: "\(Coins.format(myRisk)) coins")
                    LabeledContent("You win", value: "+\(Coins.format(theirRisk)) coins")
                    LabeledContent("\(offer.makerName) risks", value: "\(Coins.format(theirRisk)) coins")
                    LabeledContent("Winner collects", value: "\(Coins.format(Stakes.pot(shares: shares))) coins")
                    if !canAfford {
                        Text("You only have \(Coins.format(available)) coins available.")
                            .foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Take offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { Task { await confirm() } }
                        .disabled(!canAfford || isSaving)
                }
            }
        }
    }

    private func confirm() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = await store.takeOffer(offerID: offer.id, shares: shares)
        if let userID = session.profile?.id { await groups.load(userID: userID) }
        await onDone()
        if errorMessage == nil { dismiss() }
    }
}

/// Posting your own offer on a market. Price is typed in your chosen format.
struct MakeOfferView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(OfferStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let groupID: UUID
    let market: MarketRow
    let onDone: () async -> Void

    @State private var side = 0
    @State private var priceText = ""
    @State private var sharesText = "10"
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var available: Int64 { groups.memberships.first { $0.id == groupID }?.available ?? 0 }

    /// The price in whole cents, or nil if what's typed isn't valid in the chosen format.
    private var cents: Int? {
        guard let number = Int(priceText.trimmingCharacters(in: .whitespaces)) else { return nil }
        switch format {
        case .cents: return (1...99).contains(number) ? number : nil
        case .american: return Odds.cents(fromAmerican: number)
        }
    }
    private var shares: Int? {
        guard let n = Int(sharesText.trimmingCharacters(in: .whitespaces)), n >= 1 else { return nil }
        return n
    }
    private var risk: Int64? {
        guard let cents, let shares else { return nil }
        return Stakes.makerRisk(shares: shares, cents: cents)
    }
    private var canAfford: Bool { (risk ?? 0) <= available }
    private var isValid: Bool { cents != nil && shares != nil && canAfford }

    var body: some View {
        NavigationStack {
            Form {
                Section("Game") {
                    Text(market.eventTitle)
                    Text(market.title).font(.footnote).foregroundStyle(.secondary)
                }

                Section("You back") {
                    Picker("Side", selection: $side) {
                        Text(market.sideLabel(0)).tag(0)
                        Text(market.sideLabel(1)).tag(1)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField(format == .cents ? "Price in cents, 1–99" : "American odds, like -150 or +120",
                              text: $priceText)
                        .keyboardType(.numbersAndPunctuation)
                } header: {
                    Text("Your price (\(format == .cents ? "cents" : "American odds"))")
                } footer: {
                    if let cents {
                        Text("Actual price: \(Odds.bothText(cents: cents)). Someone who takes it gets the other side at \(Odds.bothText(cents: 100 - cents)).")
                    } else if !priceText.isEmpty {
                        Text(format == .cents ? "Enter a whole number from 1 to 99."
                                              : "Enter odds like -150 or +120 (not between -99 and +99).")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Shares", text: $sharesText).keyboardType(.numberPad)
                } header: {
                    Text("Size (shares)")
                } footer: {
                    Text("Each share pays 1 coin to whoever is right. Other members can take part or all of it.")
                }

                if let cents, let shares, let risk {
                    Section("Exactly what's at stake") {
                        LabeledContent("You risk", value: "\(Coins.format(risk)) coins")
                        LabeledContent("You win (if fully taken)",
                                       value: "+\(Coins.format(Stakes.takerRisk(shares: shares, cents: cents))) coins")
                        LabeledContent("Winner collects", value: "\(Coins.format(Stakes.pot(shares: shares))) coins")
                        if !canAfford {
                            Text("You only have \(Coins.format(available)) coins available.").foregroundStyle(.red)
                        } else {
                            Text("These coins are set aside while the offer is open. Unfilled shares are returned automatically when the game starts, or any time you cancel.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Make an offer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { Task { await post() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    private func post() async {
        guard let cents, let shares else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = await store.postOffer(groupID: groupID, marketID: market.id, outcome: side,
                                             cents: cents, shares: shares)
        if let userID = session.profile?.id { await groups.load(userID: userID) }
        await onDone()
        if errorMessage == nil { dismiss() }
    }
}
