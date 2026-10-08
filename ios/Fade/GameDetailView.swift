import SwiftUI

struct GameDetailView: View {
    @Environment(MarketStore.self) private var store
    let game: Game

    @State private var loaded: GameMarkets?
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                Text(game.start.formatted(date: .complete, time: .shortened))
                Text("Bets close when the game starts — there is no live betting.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if let loaded {
                if !loaded.moneylines.isEmpty {
                    Section("Moneyline") { ForEach(loaded.moneylines) { MarketLine(market: $0) } }
                }
                LinesSection(title: "Spread", rows: loaded.spreads)
                LinesSection(title: "Over / Under", rows: loaded.totals)

                Section {
                    Text("Making and taking offers on these markets arrives in the next update.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if isLoading {
                Section { ProgressView() }
            }
        }
        .navigationTitle(game.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loaded = GameMarkets(await store.markets(forGame: game.id))
            isLoading = false
        }
    }
}

/// Shows the main line first and tucks the many alternate lines behind a disclosure.
private struct LinesSection: View {
    let title: String
    let rows: [MarketRow]

    var body: some View {
        if let main = GameMarkets.mainLine(rows) {
            Section(title) {
                MarketLine(market: main)
                if rows.count > 1 {
                    DisclosureGroup("More lines (\(rows.count - 1))") {
                        ForEach(rows.filter { $0.id != main.id }) { MarketLine(market: $0) }
                    }
                }
            }
        }
    }
}

private struct MarketLine: View {
    let market: MarketRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(market.title)
            if let subtitle = market.subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
