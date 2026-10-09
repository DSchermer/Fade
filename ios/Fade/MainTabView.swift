import SwiftUI

/// The signed-in app: five tabs with Fade's own floating bar.
struct MainTabView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            FeedHomeView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.feed)
            GamesTabView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.games)
            BetsTabView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.bets)
            GroupsTabView()
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.groups)
            SettingsView(asTab: true)
                .toolbar(.hidden, for: .tabBar)
                .tag(AppTab.me)
        }
        .tint(Theme.accent)
        .sheet(item: $router.sheet, onDismiss: { session.pendingJoinCode = nil }) { sheet in
            switch sheet {
            case .createGroup: CreateGroupView()
            case .joinGroup: JoinGroupView(prefill: session.pendingJoinCode)
            }
        }
        .onDisappear {                      // signed out: the next sign-in starts fresh on the Feed tab
            router.tab = .feed
            router.sheet = nil
            router.gamesGroupID = nil
        }
        .onChange(of: session.pendingJoinCode) { _, code in
            if code != nil { router.sheet = .joinGroup }
        }
        .task(id: session.profile?.id) {
            if let userID = session.profile?.id { await groups.load(userID: userID) }
            await PushManager.shared.registerIfAuthorized()
            if session.pendingJoinCode != nil { router.sheet = .joinGroup }
        }
    }
}

/// The floating capsule: Feed, Games, Bets, Groups, Me.
struct FadeTabBar: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let selected = router.tab == tab
                Button {
                    router.tab = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selected ? tab.selectedSymbol : tab.symbol)
                            .font(.system(size: 20, weight: .medium))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(selected ? Theme.raised : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Capsule().fill(Theme.card.opacity(0.96)))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 4)
    }
}

extension View {
    /// Puts the floating tab bar at the bottom of a screen. Screens pushed on top of it don't get the bar.
    func fadeTabBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            FadeTabBar()
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }
}

/// Stand-in for the Games and Bets tabs until they are rebuilt: points to where the old screens live.
struct LegacyTabView: View {
    let tab: AppTab

    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(tab.title)
                    .font(.fadeScreenTitle)
                    .foregroundStyle(Theme.text)
                EmptyStateCard(
                    systemImage: tab.symbol,
                    title: "Being rebuilt",
                    message: "This tab gets its new look in the next step. For now, open Groups, pick a group, and use Browse games or My bets."
                ) {
                    Button("Go to Groups") { router.tab = .groups }
                        .buttonStyle(.fadePrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .fadeScreen()
        .fadeTabBar()
    }
}
