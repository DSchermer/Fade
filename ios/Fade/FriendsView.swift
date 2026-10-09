import SwiftUI

/// Friends leaderboard, requests, and finding people to add.
struct FriendsView: View {
    @Environment(FriendStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable, Identifiable {
        case board = "Leaderboard"
        case requests = "Requests"
        case add = "Add"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .board
    @State private var scores: [FriendScore] = []
    @State private var requests: [FriendRequest] = []
    @State private var suggestions: [FriendSuggestion] = []
    @State private var username = ""
    @State private var message: (text: String, ok: Bool)?
    @State private var friendToRemove: FriendScore?
    @State private var isBusy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Text(t == .requests && incoming > 0 ? "Requests (\(incoming))" : t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch tab {
                case .board: board
                case .requests: requestList
                case .add: addList
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await reload() }
            .refreshable { await reload() }
            .confirmationDialog("Remove \(friendToRemove?.displayName ?? "friend")?", isPresented: Binding(
                get: { friendToRemove != nil }, set: { if !$0 { friendToRemove = nil } }
            ), titleVisibility: .visible, presenting: friendToRemove) { friend in
                Button("Remove friend", role: .destructive) { Task { await remove(friend) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var incoming: Int { requests.filter { $0.direction == "incoming" }.count }

    // MARK: Leaderboard

    private var board: some View {
        List {
            Section {
                ForEach(Array(scores.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.headline).monospacedDigit().frame(width: 28)
                            .foregroundStyle(index == 0 ? Color.orange : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.isMe ? "\(row.displayName) (you)" : row.displayName).font(.headline)
                            Text("Record \(row.wins)–\(row.losses)").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.score.signedCoins)
                            .font(.headline).monospacedDigit()
                            .foregroundStyle(row.score > 0 ? Color.green : (row.score < 0 ? Color.red : Color.primary))
                    }
                    .swipeActions {
                        if !row.isMe {
                            Button("Remove", role: .destructive) { friendToRemove = row }
                        }
                    }
                }
            } footer: {
                Text("Global lifetime score: net profit across all your groups, past seasons included. Buybacks count against you. Swipe a friend to remove them.")
            }
            if scores.count <= 1 {
                Section {
                    Text("Add friends to see how you rank. Try the Add tab.").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Requests

    private var requestList: some View {
        List {
            let incomingRows = requests.filter { $0.direction == "incoming" }
            let outgoingRows = requests.filter { $0.direction == "outgoing" }
            if !incomingRows.isEmpty {
                Section("Wants to be your friend") {
                    ForEach(incomingRows) { request in
                        HStack {
                            Text(request.displayName)
                            Spacer()
                            Button("Decline") { Task { await respond(request, accept: false) } }.buttonStyle(.bordered)
                            Button("Accept") { Task { await respond(request, accept: true) } }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            if !outgoingRows.isEmpty {
                Section("Waiting for them") {
                    ForEach(outgoingRows) { request in
                        HStack {
                            Text(request.displayName)
                            Spacer()
                            Button("Cancel") { Task { await cancel(request) } }.buttonStyle(.bordered)
                        }
                    }
                }
            }
            if requests.isEmpty {
                Section { Text("No requests right now.").foregroundStyle(.secondary) }
            }
            if let message { Section { Text(message.text).foregroundStyle(message.ok ? Color.green : Color.red) } }
        }
    }

    // MARK: Add

    private var addList: some View {
        List {
            Section {
                TextField("Their username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Send friend request") { Task { await send(username) } }
                    .disabled(username.trimmingCharacters(in: .whitespaces).count < 3 || isBusy)
            } header: {
                Text("Add by username")
            } footer: {
                Text("Type their exact username. People who have blocked you, or whom you've blocked, can't be added.")
            }

            if let message { Section { Text(message.text).foregroundStyle(message.ok ? Color.green : Color.red) } }

            if !suggestions.isEmpty {
                Section("People from your groups") {
                    ForEach(suggestions) { person in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(person.displayName)
                                Text("\(person.sharedGroups) shared group\(person.sharedGroups == 1 ? "" : "s")")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Add") { Task { await send(person.username ?? "") } }
                                .buttonStyle(.bordered).disabled(isBusy)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func reload() async {
        scores = await store.scores()
        requests = await store.requests()
        suggestions = await store.suggestions()
    }

    private func send(_ name: String) async {
        isBusy = true
        defer { isBusy = false }
        let result = await store.sendRequest(username: name)
        message = (result.message, result.ok)
        if result.ok { username = "" }
        await reload()
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        message = nil
        if let error = await store.respond(to: request.userId, accept: accept) { message = (error, false) }
        await reload()
    }

    private func cancel(_ request: FriendRequest) async {
        message = nil
        if let error = await store.cancelRequest(to: request.userId) { message = (error, false) }
        await reload()
    }

    private func remove(_ friend: FriendScore) async {
        if let error = await store.removeFriend(friend.userId) { message = (error, false) }
        await reload()
    }
}
