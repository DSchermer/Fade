import SwiftUI

@main
struct FadeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = Session()
    @State private var groups = GroupStore()
    @State private var markets = MarketStore()
    @State private var offers = OfferStore()
    @State private var feed = FeedStore()
    @State private var friends = FriendStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(groups)
                .environment(markets)
                .environment(offers)
                .environment(feed)
                .environment(friends)
                .onOpenURL { session.handle(url: $0) }
                .task { await session.restore() }
        }
    }
}
