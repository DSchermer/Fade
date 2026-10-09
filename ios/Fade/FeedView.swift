import SwiftUI

/// A group's activity: offers, takes, results, buybacks, votes. React with emoji; tap to comment.
struct FeedView: View {
    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var store

    let groupID: UUID

    @State private var items: [FeedItem] = []
    @State private var loaded = false

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }

    var body: some View {
        List(items) { item in
            NavigationLink {
                FeedItemDetailView(item: item, onChange: { await reload() })
            } label: {
                FeedItemRow(item: item, format: format) { emoji in
                    Task { await react(item, emoji) }
                }
            }
        }
        .overlay {
            if loaded && items.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "text.bubble",
                                       description: Text(store.errorMessage ?? "Offers, bets, results and votes show up here."))
            }
        }
        .navigationTitle("Group feed")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        items = await store.feed(groupID: groupID)
        loaded = true
    }

    private func react(_ item: FeedItem, _ emoji: String) async {
        _ = await store.toggleReaction(itemID: item.id, emoji: emoji)
        await reload()
    }
}

struct FeedItemRow: View {
    let item: FeedItem
    let format: PriceFormat
    let onReact: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.icon).foregroundStyle(.tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.headline(format)).font(.subheadline)
                    if let sub = item.subline {
                        Text(sub).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(item.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(item.reactions.sorted { $0.key < $1.key }, id: \.key) { emoji, count in
                    Button { onReact(emoji) } label: {
                        Text("\(emoji) \(count)")
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(item.myReactions.contains(emoji) ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if item.commentCount > 0 {
                    Label("\(item.commentCount)", systemImage: "bubble.left").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

/// One feed item with its comments. Long-press a comment to report, mute or block its author.
struct FeedItemDetailView: View {
    @Environment(Session.self) private var session
    @Environment(FeedStore.self) private var store

    let item: FeedItem
    let onChange: () async -> Void

    @State private var comments: [CommentRow] = []
    @State private var myReactions: Set<String> = []
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var reportTarget: ReportTarget?
    @State private var confirmBlock: CommentRow?
    @State private var isSending = false

    private var format: PriceFormat { session.profile?.priceFormat ?? .cents }
    private var me: UUID? { session.profile?.id }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.headline(format)).font(.headline)
                    if let sub = item.subline { Text(sub).font(.subheadline).foregroundStyle(.secondary) }
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(reactionEmoji, id: \.self) { emoji in
                            Button { Task { await toggle(emoji) } } label: {
                                Text(emoji).font(.title2)
                                    .padding(6)
                                    .background(myReactions.contains(emoji) ? Color.accentColor.opacity(0.25) : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let actor = item.actorId, actor != me {
                    Button("Report this post", systemImage: "flag") {
                        reportTarget = ReportTarget(type: "feed_item", id: item.id, title: "this post")
                    }
                    .font(.footnote)
                }
            }

            Section {
                if comments.isEmpty {
                    Text("No comments yet.").foregroundStyle(.secondary)
                }
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.displayName).font(.caption.weight(.semibold))
                        Text(comment.body)
                        Text(comment.createdAt.formatted(.relative(presentation: .named)))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        if comment.userId == me {
                            Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(comment) } }
                        } else {
                            Button("Report", systemImage: "flag") {
                                reportTarget = ReportTarget(type: "comment", id: comment.id, title: "this comment")
                            }
                            Button("Mute \(comment.displayName)", systemImage: "speaker.slash") { Task { await mute(comment) } }
                            Button("Block \(comment.displayName)", systemImage: "hand.raised.slash", role: .destructive) { confirmBlock = comment }
                        }
                    }
                }
            } header: {
                Text("Comments")
            } footer: {
                Text("Touch and hold a comment to report it, mute, or block its author. Comments with offensive language are rejected.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                Button("Send") { Task { await send() } }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(.bar)
        }
        .task {
            myReactions = Set(item.myReactions)
            await reload()
        }
        .sheet(item: $reportTarget) { target in ReportView(target: target) }
        .confirmationDialog("Block \(confirmBlock?.displayName ?? "this person")?", isPresented: Binding(
            get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }
        ), titleVisibility: .visible, presenting: confirmBlock) { comment in
            Button("Block", role: .destructive) { Task { await block(comment) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You won't see each other's comments or feed activity. You can unblock in Settings. To avoid someone's offers entirely, leave the group.")
        }
    }

    private func reload() async {
        comments = await store.comments(itemID: item.id)
    }

    private func toggle(_ emoji: String) async {
        errorMessage = await store.toggleReaction(itemID: item.id, emoji: emoji)
        if errorMessage == nil {
            if myReactions.contains(emoji) { myReactions.remove(emoji) } else { myReactions.insert(emoji) }
            await onChange()
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        errorMessage = await store.addComment(itemID: item.id, body: draft)
        if errorMessage == nil { draft = "" }
        await reload()
        await onChange()
    }

    private func delete(_ comment: CommentRow) async {
        errorMessage = await store.deleteComment(id: comment.id)
        await reload()
        await onChange()
    }

    private func mute(_ comment: CommentRow) async {
        errorMessage = await store.mute(userID: comment.userId)
        await reload()
    }

    private func block(_ comment: CommentRow) async {
        errorMessage = await store.block(userID: comment.userId)
        await reload()
        await onChange()
    }
}

struct ReportTarget: Identifiable {
    let type: String
    let id: UUID
    let title: String
}

/// Choose a reason and send a report. The app's owner reviews reports and can hide content or ban accounts.
struct ReportView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let target: ReportTarget

    @State private var reason: ReportReason = .harassment
    @State private var details = ""
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label("Thanks — report sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("We review reports and remove content or accounts that break the rules. You can also block or mute the person from the comment menu.")
                            .font(.footnote)
                    }
                } else {
                    Section("What's wrong with \(target.title)?") {
                        Picker("Reason", selection: $reason) {
                            ForEach(ReportReason.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section("Anything else? (optional)") {
                        TextField("Details", text: $details, axis: .vertical).lineLimit(2...5)
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(sent ? "Done" : "Cancel") { dismiss() } }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }
                    }
                }
            }
        }
    }

    private func send() async {
        errorMessage = await store.report(type: target.type, id: target.id, reason: reason, details: details)
        if errorMessage == nil { sent = true }
    }
}

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
