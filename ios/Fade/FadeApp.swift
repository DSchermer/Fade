import SwiftUI

@main
struct FadeApp: App {
    @State private var session = Session()
    @State private var groups = GroupStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(groups)
                .task { await session.restore() }
        }
    }
}
