import SwiftUI

/// Settings screen: people you've blocked or muted, with a way to undo it.
struct BlockedUsersView: View {
    @Environment(FeedStore.self) private var store

    @State private var rows: [BlockedUser] = []
    @State private var loaded = false

    var body: some View {
        List {
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading) {
                        Text("@\(row.username ?? "deleted user")")
                        Text(row.kind == "blocked" ? "Blocked" : "Muted").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(row.kind == "blocked" ? "Unblock" : "Unmute") {
                        Task {
                            _ = row.kind == "blocked" ? await store.unblock(userID: row.userId) : await store.unmute(userID: row.userId)
                            await reload()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .overlay {
            if loaded && rows.isEmpty {
                ContentUnavailableView("No one blocked or muted", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
        .navigationTitle("Blocked & muted")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        rows = await store.blockedAndMuted()
        loaded = true
    }
}
