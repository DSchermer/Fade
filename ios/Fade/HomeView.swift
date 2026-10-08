import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.3.fill").font(.largeTitle)
                Text("Hi, @\(session.profile?.username ?? "")")
                    .font(.title2)
                Text("Your groups will appear here (Milestone 3).")
                    .foregroundStyle(.secondary)
                NoMoneyNotice()
            }
            .padding()
            .navigationTitle("Fade")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}
