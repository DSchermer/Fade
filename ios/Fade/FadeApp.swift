import SwiftUI

@main
struct FadeApp: App {
    @State private var session = Session()
    @State private var groups = GroupStore()
    @State private var markets = MarketStore()
    @State private var offers = OfferStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(groups)
                .environment(markets)
                .environment(offers)
                .task { await session.restore() }
        }
    }
}
