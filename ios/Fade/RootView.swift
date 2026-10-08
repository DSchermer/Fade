import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
        case .signedOut:
            SignInView()
        case .needsUsername:
            UsernameView()
        case .ready:
            HomeView()
        }
    }
}
