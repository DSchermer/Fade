import SwiftUI

@main
struct FadeApp: App {
    @State private var session = Session()
    @State private var groups = GroupStore()
    @State private var markets = MarketStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(groups)
                .environment(markets)
                .task { await session.restore() }
        }
    }
}
