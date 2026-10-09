import SwiftUI

/// Friends: the leaderboard of people you've added, requests in and out, and finding people to add.
struct FriendsView: View {
    enum Part: String, CaseIterable, Hashable {
        case board, requests, add
    }

    @Environment(FriendStore.self) private var store

    @State private var part: Part
    @State private var scores: [FriendScore] = []
    @State private var requests: [FriendRequest] = []
    @State private var suggestions: [FriendSuggestion] = []
    @State private var username = ""
    @State private var message: (text: String, ok: Bool)?
    @State private var friendToRemove: FriendScore?
    @State private var isBusy = false
    @FocusState private var usernameFocused: Bool

    init(initialTab: Part = .board) {
        _part = State(initialValue: initialTab)
    }

    private var incoming: [FriendRequest] { requests.filter { $0.direction == "incoming" } }
    private var outgoing: [FriendRequest] { requests.filter { $0.direction == "outgoing" } }

    private func title(_ part: Part) -> String {
        switch part {
        case .board: return "Leaderboard"
        case .requests: return incoming.isEmpty ? "Requests" : "Requests (\(incoming.count))"
        case .add: return "Add"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FadeSegmented(options: Part.allCases, title: title, selection: $part)
                    .padding(.horizontal, 16)
                switch part {
                case .board: board
                case .requests: requestsList
                case .add: addList
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await reload() }
        .fadeScreen()
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task { await reload() }
        .confirmationDialog("Remove \(friendToRemove?.displayName ?? "friend")?", isPresented: Binding(
            get: { friendToRemove != nil }, set: { if !$0 { friendToRemove = nil } }
        ), titleVisibility: .visible, presenting: friendToRemove) { friend in
            Button("Remove friend", role: .destructive) { Task { await remove(friend) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Leaderboard

    private var board: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(scores.enumerated()), id: \.element.id) { index, row in
                    FriendScoreRow(rank: index + 1, row: row)
                        .overlay(alignment: .bottom) {
                            if index < scores.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                        .contextMenu {
                            if !row.isMe {
                                Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) { friendToRemove = row }
                            }
                        }
                }
            }
            .padding(.horizontal, 14)
            .fadeCardBackground()
            if scores.count <= 1 {
                Text("Add friends to see how you rank. Try the Add tab.")
                    .font(.fadeBody)
                    .foregroundStyle(Theme.text2)
            }
            Text("Lifetime score is net profit across all your groups, past seasons included. Buybacks never count as winnings. Touch and hold a friend to remove them.")
                .font(.caption)
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let message { messageLine(message) }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Requests

    private var requestsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !incoming.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Wants to be your friend")
                    ForEach(incoming) { request in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Avatar(name: request.username ?? "?", size: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(request.username ?? "deleted user").font(.fadeHeadline.weight(.bold)).foregroundStyle(Theme.text)
                                    Text("Sent \(RelativeTime.agoText(from: request.createdAt))").font(.caption).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                            }
                            HStack(spacing: 8) {
                                Button("Accept") { Task { await respond(request, accept: true) } }
                                    .buttonStyle(FadeButtonStyle(kind: .primary, height: 44))
                                Button("Decline") { Task { await respond(request, accept: false) } }
                                    .buttonStyle(FadeButtonStyle(kind: .quiet, height: 44))
                            }
                        }
                        .fadeCard(padding: 14)
                    }
                }
            }
            if !outgoing.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Waiting for them")
                    VStack(spacing: 0) {
                        ForEach(Array(outgoing.enumerated()), id: \.element.id) { index, request in
                            HStack(spacing: 12) {
                                Avatar(name: request.username ?? "?", size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(request.username ?? "deleted user").font(.fadeHeadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text("Request sent \(RelativeTime.agoText(from: request.createdAt))").font(.caption).foregroundStyle(Theme.text2)
                                }
                                Spacer()
                                Button("Cancel") { Task { await cancel(request) } }
                                    .buttonStyle(.fadeSecondaryCompact)
                            }
                            .frame(minHeight: 64)
                            .overlay(alignment: .bottom) {
                                if index < outgoing.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .fadeCardBackground()
                }
            }
            if requests.isEmpty {
                EmptyStateCard(systemImage: "person.badge.plus", title: "No requests right now", message: "Requests you send and receive show up here.")
            }
            if let message { messageLine(message) }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Add

    private var addList: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Add by username")
                HStack(spacing: 10) {
                    Text("@").font(.fadeHeadline).foregroundStyle(Theme.text2)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($usernameFocused)
                        .font(.fadeHeadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                }
                .contentShape(Rectangle())
                .onTapGesture { usernameFocused = true }
                .padding(.horizontal, 16)
                .frame(minHeight: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                Button("Send friend request") { Task { await send(username) } }
                    .buttonStyle(.fadePrimary)
                    .disabled(username.trimmingCharacters(in: .whitespaces).count < 3 || isBusy)
                Text("Type their exact username. People who have blocked you, or whom you've blocked, can't be added.")
                    .font(.caption)
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
                if let message { messageLine(message) }
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("People from your groups")
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, person in
                            HStack(spacing: 12) {
                                Avatar(name: person.username ?? "?", size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.username ?? "deleted user").font(.fadeHeadline.weight(.semibold)).foregroundStyle(Theme.text)
                                    Text("\(person.sharedGroups) shared group\(person.sharedGroups == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(Theme.text2)
                                }
                                Spacer()
                                Button("Add") { Task { await send(person.username ?? "") } }
                                    .buttonStyle(FadeButtonStyle(kind: .quiet, height: 44, fullWidth: false))
                                    .disabled(isBusy)
                            }
                            .frame(minHeight: 64)
                            .overlay(alignment: .bottom) {
                                if index < suggestions.count - 1 { Rectangle().fill(Theme.line).frame(height: 1) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .fadeCardBackground()
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func messageLine(_ message: (text: String, ok: Bool)) -> some View {
        Text(message.text)
            .font(.fadeCaption.weight(.semibold))
            .foregroundStyle(message.ok ? Theme.win : Theme.loss)
            .fixedSize(horizontal: false, vertical: true)
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
