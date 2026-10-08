import SwiftUI

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        if session.isSignedIn {
            HomeView()
        } else {
            SignInView()
        }
    }
}

struct SignInView: View {
    @Environment(Session.self) private var session
    @State private var showLegal = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Fade")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
            Text("Bet your friends. Play money only.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()

            NoMoneyNotice()

            #if DEBUG
            Button("Debug sign in (debug builds only)") { session.debugSignIn() }
                .buttonStyle(.borderedProminent)
            #endif

            Button("About Fade coins & help resources") { showLegal = true }
                .font(.footnote)
        }
        .padding()
        .sheet(isPresented: $showLegal) { LegalView() }
    }
}

struct HomeView: View {
    @Environment(Session.self) private var session
    @State private var showLegal = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.3.fill").font(.largeTitle)
                Text("Hi, \(session.displayName ?? "")")
                    .font(.title2)
                Text("Your groups will appear here (Milestone 3).")
                    .foregroundStyle(.secondary)
                NoMoneyNotice()
            }
            .padding()
            .navigationTitle("Fade")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("About coins & help") { showLegal = true }
                        Button("Sign out", role: .destructive) { session.signOut() }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showLegal) { LegalView() }
        }
    }
}
