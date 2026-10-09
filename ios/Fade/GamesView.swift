import SwiftUI

struct GamesView: View {
    @Environment(MarketStore.self) private var markets
    let groupID: UUID
    @State private var league: String?

    private var days: [(day: Date, games: [Game])] {
        Dictionary(grouping: markets.games) { Calendar.current.startOfDay(for: $0.start) }
            .map { (day: $0.key, games: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        List {
            ForEach(days, id: \.day) { day in
                Section(day.day.formatted(.dateTime.weekday(.wide).month().day())) {
                    ForEach(day.games) { game in
                        NavigationLink {
                            GameDetailView(game: game, groupID: groupID)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title).font(.headline)
                                Text("\(game.league.uppercased()) · \(game.start.formatted(date: .omitted, time: .shortened))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if markets.games.isEmpty && !markets.isLoading {
                ContentUnavailableView(
                    "No games right now",
                    systemImage: "sportscourt",
                    description: Text(markets.errorMessage ?? "Upcoming games appear here. The schedule refreshes every 15 minutes.")
                )
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("League", selection: $league) {
                Text("All").tag(String?.none)
                ForEach(MarketStore.leagues, id: \.self) { Text($0.uppercased()).tag(String?.some($0)) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: league) { await markets.loadGames(league: league) }
        .refreshable { await markets.loadGames(league: league) }
    }
}
