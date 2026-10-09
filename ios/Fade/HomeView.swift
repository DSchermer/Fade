import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session
    @Environment(GroupStore.self) private var groups
    @State private var showSettings = false
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showFriends = false

    var body: some View {
        NavigationStack {
            Group {
                if groups.memberships.isEmpty && !groups.isLoading {
                    ContentUnavailableView {
                        Label("No groups yet", systemImage: "person.3")
                    } description: {
                        Text("Create a group for your friends, or join one with an invite code.")
                    } actions: {
                        Button("Create a group") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                        Button("Join with a code") { showJoin = true }
                    }
                } else {
                    List(groups.memberships) { membership in
                        NavigationLink {
                            GroupDetailView(membership: membership)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(membership.group.name).font(.headline)
                                Text("\(Coins.format(membership.balance)) coins")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fade")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showFriends = true } label: { Image(systemName: "person.2") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Create a group", systemImage: "plus") { showCreate = true }
                        Button("Join with a code", systemImage: "ticket") { showJoin = true }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 4) {
                    if let message = groups.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                    NoMoneyNotice()
                }
                .padding()
            }
            .refreshable { await reload() }
            .task(id: session.profile?.id) {
                await reload()
                if session.pendingJoinCode != nil { showJoin = true }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showCreate) { CreateGroupView() }
            .sheet(isPresented: $showJoin, onDismiss: { session.pendingJoinCode = nil }) {
                JoinGroupView(prefill: session.pendingJoinCode)
            }
            .sheet(isPresented: $showFriends) { FriendsView() }
            .onChange(of: session.pendingJoinCode) { _, code in if code != nil { showJoin = true } }
        }
    }

    private func reload() async {
        guard let userID = session.profile?.id else { return }
        await groups.load(userID: userID)
    }
}
