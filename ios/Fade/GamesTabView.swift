import SwiftUI

/// What the order-book sheet opens on: one market, looking at one side.
struct OrderBookTarget: Identifiable {
    let market: MarketRef
    let side: Int

    var id: String { "\(market.id)-\(side)" }
}

/// The Games tab: upcoming games with the best open price for Spread, Total and Win. Tap a price for the order book,
/// tap the team names for the full game page.
struct GamesTabView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(MarketStore.self) private var markets
    @Environment(OfferStore.self) private var offerStore
    @Environment(AppRouter.self) private var router

    @State private var league: String?
    @State private var offers: [OfferRow] = []
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var target: OrderBookTarget?
    @State private var openGame: GameLines?
    @FocusState private var searchFocused: Bool

    private struct LeagueTab: Identifiable {
        let code: String?
        let title: String
        var id: String { title }
    }

    private struct DaySection: Identifiable {
        let day: Date
        let rows: [BoardRow]
        var id: Date { day }
    }

    private static let leagueTabs: [LeagueTab] = [
        LeagueTab(code: nil, title: "All"), LeagueTab(code: "nhl", title: "NHL"), LeagueTab(code: "nba", title: "NBA"),
        LeagueTab(code: "nfl", title: "NFL"), LeagueTab(code: "mlb", title: "MLB"),
    ]

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }

    /// The group offers go to: the one picked here, or your first group.
    private var activeGroup: GroupMembership? {
        groups.memberships.first { $0.id == router.gamesGroupID } ?? groups.memberships.first
    }

    private var visibleGames: [GameLines] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return markets.board }
        return markets.board.filter { $0.eventTitle.lowercased().contains(query) || $0.teams.contains { $0.lowercased().contains(query) } }
    }

    private var days: [DaySection] {
        let rows = GamesBoard.rows(lines: visibleGames, offers: offers)
        let grouped = Dictionary(grouping: rows) { Calendar.current.startOfDay(for: $0.game.gameStart) }
        return grouped
            .map { DaySection(day: $0.key, rows: $0.value.sorted { $0.game.gameStart < $1.game.gameStart }) }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if isSearching { searchField }
                    leagueBar
                    if groups.memberships.isEmpty && !groups.isLoading {
                        noGroups
                    } else {
                        groupPicker
                        gamesList
                    }
                    NoMoneyNotice()
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
            .refreshable { await reload() }
            .fadeScreen()
            .toolbar(.hidden, for: .navigationBar)
            .fadeTabBar()
            .navigationDestination(item: $openGame) { game in
                GamePageView(game: game)
            }
            .sheet(item: $target) { target in
                OrderBookSheet(target: target) { await reloadOffers() }
            }
            .task(id: league) { await markets.loadBoard(league: league) }
            .task(id: activeGroup?.id) { await reloadOffers() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Games")
                .font(.fadeScreenTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            CircleIconButton(systemImage: isSearching ? "xmark" : "magnifyingglass", label: isSearching ? "Close search" : "Search games") {
                isSearching.toggle()
                if isSearching { searchFocused = true } else { searchText = "" }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.text2)
            TextField("Search teams", text: $searchText)
                .textFieldStyle(.plain)
                .font(.fadeBody)
                .foregroundStyle(Theme.text)
                .focused($searchFocused)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var leagueBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.leagueTabs) { tab in
                let selected = league == tab.code
                Button {
                    league = tab.code
                } label: {
                    Text(tab.title)
                        .font(.fadeBody.weight(selected ? .bold : .semibold))
                        .foregroundStyle(selected ? Theme.text : Theme.text2)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selected ? Theme.accent : Color.clear).frame(height: 2.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        .padding(.horizontal, 2)
    }

    private var groupPicker: some View {
        GroupPickerButton(groups: groups.memberships, selected: activeGroup) { id in router.gamesGroupID = id }
            .padding(.horizontal, 16)
    }

    private var noGroups: some View {
        EmptyStateCard(
            systemImage: "person.2",
            title: "Join a group to bet",
            message: "Offers are made inside a group of friends. Make one, or join one with a code."
        ) {
            HStack(spacing: 8) {
                Button("Create group") { router.sheet = .createGroup }
                    .buttonStyle(.fadePrimary)
                Button("Join with a code") { router.sheet = .joinGroup }
                    .buttonStyle(.fadeSecondary)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Games

    @ViewBuilder private var gamesList: some View {
        if markets.board.isEmpty && !markets.isLoading {
            EmptyStateCard(
                systemImage: "sportscourt",
                title: "No games right now",
                message: markets.errorMessage ?? "Leagues take breaks between seasons. New games appear here as soon as they're scheduled, and the list refreshes every 15 minutes."
            )
            .padding(.horizontal, 16)
        } else if visibleGames.isEmpty && !markets.isLoading {
            EmptyStateCard(systemImage: "magnifyingglass", title: "No matches", message: "No game matches \"\(searchText)\".")
                .padding(.horizontal, 16)
        } else {
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 10) {
                    daySectionHeader(day.day, showColumns: day.id == days.first?.id)
                    ForEach(day.rows) { row in
                        GameRowCard(
                            row: row, format: format,
                            onCell: { cell in target = OrderBookTarget(market: cell.market, side: cell.side) },
                            onOpenGame: { openGame = row.game }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func daySectionHeader(_ day: Date, showColumns: Bool) -> some View {
        HStack(alignment: .bottom) {
            Text(GameTime.dayTitle(day))
                .font(.fadeSectionTitle)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if showColumns {
                HStack(spacing: 4) {
                    ForEach(["Spread", "Total", "Win"], id: \.self) { name in
                        Text(name.uppercased())
                            .font(.fadeLabel)
                            .tracking(0.6)
                            .foregroundStyle(Theme.text2)
                            .frame(width: GameRowCard.cellWidth)
                    }
                }
                .padding(.trailing, 12)
                .accessibilityHidden(true)
            }
        }
        .padding(.top, 6)
    }

    // MARK: Loading

    private func reload() async {
        await markets.loadBoard(league: league)
        await reloadOffers()
    }

    private func reloadOffers() async {
        guard let group = activeGroup else { offers = []; return }
        offers = await offerStore.openOffers(groupID: group.id)
    }
}

/// "Offers go to  [ badge  College Boys  ⌄ ]" — switches the group offers are made in.
struct GroupPickerButton: View {
    let groups: [GroupMembership]
    let selected: GroupMembership?
    let onPick: (UUID) -> Void

    var body: some View {
        Menu {
            ForEach(groups) { membership in
                Button(membership.group.name) { onPick(membership.id) }
            }
        } label: {
            HStack(spacing: 10) {
                GroupBadge(name: selected?.group.name ?? "?", size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("OFFERS GO TO")
                        .font(.fadeLabel)
                        .tracking(0.8)
                        .foregroundStyle(Theme.text2)
                    Text(selected?.group.name ?? "Pick a group")
                        .font(.fadeBody.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        }
        .accessibilityLabel("Offers go to \(selected?.group.name ?? "no group"). Change group")
    }
}

/// One game: time, league, how many offers are open, the two teams, and a 2 × 3 grid of prices.
struct GameRowCard: View {
    static let cellWidth: CGFloat = 66

    let row: BoardRow
    let format: PriceFormat
    let onCell: (BoardCell) -> Void
    let onOpenGame: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(row.game.gameStart.formatted(date: .omitted, time: .shortened)) · \(row.game.league.uppercased())")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.text2)
                Spacer()
                if row.openOffers > 0 {
                    Text("\(row.openOffers) open offer\(row.openOffers == 1 ? "" : "s")")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 22)
                        .background(Theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<2, id: \.self) { team in
                        Text(row.game.teams[team])
                            .font(.fadeHeadline.weight(.bold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpenGame)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.game.eventTitle). Open all markets")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onOpenGame() }

                VStack(spacing: 4) {
                    ForEach(0..<2, id: \.self) { team in
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { column in
                                cellView(row.cells[team][column], team: team)
                            }
                        }
                    }
                }
            }
        }
        .fadeCard(padding: 12)
    }

    @ViewBuilder private func cellView(_ cell: BoardCell?, team: Int) -> some View {
        if let cell {
            Button {
                onCell(cell)
            } label: {
                VStack(spacing: 1) {
                    if let line = cell.line {
                        Text(line)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.text2)
                    }
                    if let cents = cell.cents {
                        Text(Odds.parts(cents: cents, format: format).main)
                            .font(.fadeBody.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text("+")
                            .font(.fadeBody.weight(.bold))
                            .foregroundStyle(Theme.text3)
                    }
                }
                .frame(width: Self.cellWidth, height: 52)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText(cell))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.raised.opacity(0.4))
                .frame(width: Self.cellWidth, height: 52)
                .accessibilityHidden(true)
        }
    }

    private func accessibilityText(_ cell: BoardCell) -> String {
        let what = cell.market.sideLabel(cell.side)
        if let cents = cell.cents { return "\(what), best price \(Odds.parts(cents: cents, format: format).main)" }
        return "\(what), no offers yet. Make one"
    }
}
